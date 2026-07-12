import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { PostModel } from '../model/PostModel';
import { CommentModel } from '../model/CommentModel';
import { PostRepository } from '../repository/PostRepository';
import { CommentRepository } from '../repository/CommentRepository';
import { UUIDUtil } from '../utils/UUIDUtil';
import { CloudCredential, CloudCredentialStore } from '../common/CloudCredentialStore';
import { SyncEventBus, SyncRequestListener } from '../distributed/SyncEventBus';
import {
  SyncAnnouncement, SyncCommentData, SyncPostData, SyncEnvelope
} from '../distributed/SyncProtocol';

// ===== 枚举 =====

export enum SyncConnectionState {
  IDLE = 0,
  CONNECTING = 1,
  CONNECTED = 2,
  SYNCING = 3,
  ERROR = 4,
  SYNCED
}

// ===== 状态类 =====
export class DistributedSyncState {
  state: SyncConnectionState = SyncConnectionState.IDLE;
  devices: SyncDeviceInfo[] = [];
  lastMessage: string = '';
  lastSyncTime: number = 0;
  transferProgress: number = 0;
  receivedPostCount: number = 0;
  receivedCommentCount: number = 0;
}

export class SyncDeviceInfo {
  deviceId: string = '';
  deviceName: string = '';
  deviceType: string = '';
  networkId: string = '';
  trusted: boolean = false;
  connected: boolean = false;
}

export class SyncResult {
  success: boolean = false;
  syncCount: number = 0;
  errorMsg: string = '';
}

export type SyncStateListener = (state: DistributedSyncState) => void;

// ===== API 接口 =====
export interface LoginResponse {
  userId: string;
  token: string;
  expiresAt: number;
}

export interface SyncUploadResponse {
  acceptedPostIds: string[];
  acceptedCommentIds: string[];
}

export interface SyncDownloadResponse {
  posts: SyncPostData[];
  comments: SyncCommentData[];
  lastSyncTimestamp: number;
}

export interface UploadImageResponse {
  remoteUrls: string[];
}

export interface ApiResponse<T> {
  success: boolean;
  message: string;
  data: T | null;
}

interface LoginBody {
  username: string;
  password: string;
  deviceName: string;
}

interface RegisterBody {
  username: string;
  password: string;
  deviceName: string;
}

interface UploadImageBody {
  fileName: string;
  fileData: string;
  fileType: string;
}

interface SyncUploadBody {
  posts: SyncPostData[];
  comments: SyncCommentData[];
  deviceId: string;
}

interface SyncDownloadBody {
  lastSyncTimestamp: number;
  deviceId: string;
}

interface LogoutBody {
  dummy: string;
}

interface SyncTransferResult {
  upload: SyncUploadResponse;
  download: SyncDownloadResponse;
  totalCount: number;
}

// ===== JSON 工具 =====
class JsonSafe {
  static parseObject(text: string): Record<string, Object> {
    return JSON.parse(text) as Record<string, Object>;
  }

  static stringify(data: Object): string {
    return JSON.stringify(data);
  }
}

// ===== 数组工具 =====
class ArrayUtil {
  static copy<T>(source: T[]): T[] {
    let result: T[] = [];
    for (let i = 0; i < source.length; i++) {
      result.push(source[i]);
    }
    return result;
  }

  static indexOf<T>(source: T[], target: T): number {
    for (let i = 0; i < source.length; i++) {
      if (source[i] === target) {
        return i;
      }
    }
    return -1;
  }
}

// ===== 轮询任务 =====
class PollingTask {
  private timerId: number = -1;
  private running: boolean = false;

  start(intervalMs: number, callback: () => void): void {
    if (this.running) {
      return;
    }
    this.running = true;
    let self: PollingTask = this;
    let loop: () => void = (): void => {
      if (!self.running) {
        return;
      }
      callback();
      self.timerId = setTimeout(loop, intervalMs);
    };
    self.timerId = setTimeout(loop, intervalMs);
  }

  stop(): void {
    this.running = false;
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }
}

/**
 * 分布式同步中心（云服务器模式）
 * 使用 @ohos.net.http + HTTP 明文请求
 */
export class DistributedService {
  private static instance: DistributedService | null = null;
  private context: common.UIAbilityContext | null = null;

  // ⭐ 使用 HTTP（不是 HTTPS）
  private static readonly API_BASE: string = 'http://39.106.70.214:3000/api';
  private static readonly AUTH_TOKEN_KEY: string = 'cloud_sync_token';
  private static readonly USER_ID_KEY: string = 'cloud_user_id';
  private static readonly LAST_SYNC_KEY: string = 'cloud_last_sync';
  private static readonly POLL_INTERVAL: number = 30000;

  // ⭐ 使用 @ohos.net.http
  private httpClient: http.HttpRequest | null = null;

  private postRepository: PostRepository = new PostRepository();
  private commentRepository: CommentRepository = new CommentRepository();
  private eventBus: SyncEventBus = SyncEventBus.getInstance();

  public deviceMap: Map<string, SyncDeviceInfo> = new Map<string, SyncDeviceInfo>();
  public localDeviceId: string = '';

  private stateListeners: SyncStateListener[] = [];
  private currentState: DistributedSyncState = new DistributedSyncState();
  private initialized: boolean = false;
  private syncing: boolean = false;
  private activeSyncTask: Promise<SyncResult> | null = null;
  private activeSyncIsFull: boolean = false;
  private authRecoveryTask: Promise<boolean> | null = null;
  private pollTask: PollingTask = new PollingTask();

  private syncRequestListener: SyncRequestListener = this.onSyncRequestedInternal.bind(this);

  private constructor() {}

  static getInstance(): DistributedService {
    if (DistributedService.instance === null) {
      DistributedService.instance = new DistributedService();
    }
    return DistributedService.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.context = context;

    // ⭐ 创建 HTTP 客户端
    if (this.httpClient === null) {
      this.httpClient = http.createHttp();
    }

    const dbResult = await DatabaseHelper.getInstance().init(context);
    if (!dbResult.success) {
      throw new Error('数据库初始化失败: ' + dbResult.errorMsg);
    }

    AppStorage.setOrCreate<string>('deviceName', context.abilityInfo.name);

    let savedToken: string | undefined = AppStorage.get<string>(DistributedService.AUTH_TOKEN_KEY);
    let savedUserId: string | undefined = AppStorage.get<string>(DistributedService.USER_ID_KEY);
    if (savedToken !== undefined && savedToken.length > 0 &&
      savedUserId !== undefined && savedUserId.length > 0) {
      this.localDeviceId = savedUserId;
      this.currentState.lastMessage = '已恢复登录状态';
    } else {
      this.localDeviceId = 'local_' + UUIDUtil.generateShort();
    }

    this.eventBus.onSyncRequested(this.syncRequestListener);
    this.initialized = true;
    this.currentState.lastMessage = '分布式同步服务已就绪（云模式）';
    this.emitState();
  }

  isReady(): boolean {
    return this.initialized;
  }

  getLocalDeviceId(): string {
    return this.localDeviceId;
  }

  onStateChanged(listener: SyncStateListener): void {
    let idx: number = ArrayUtil.indexOf<SyncStateListener>(this.stateListeners, listener);
    if (idx < 0) {
      this.stateListeners.push(listener);
    }
    listener(this.copyState());
  }

  offStateChanged(listener: SyncStateListener): void {
    let idx: number = ArrayUtil.indexOf<SyncStateListener>(this.stateListeners, listener);
    if (idx >= 0) {
      let newList: SyncStateListener[] = [];
      for (let i = 0; i < this.stateListeners.length; i++) {
        if (i !== idx) {
          newList.push(this.stateListeners[i]);
        }
      }
      this.stateListeners = newList;
    }
  }

  getState(): DistributedSyncState {
    return this.copyState();
  }

  // ===== 登录 =====
  async login(username: string, password: string, syncAfterLogin: boolean = true): Promise<boolean> {
    this.currentState.state = SyncConnectionState.CONNECTING;
    this.emitState();

    console.info('[DistributedService] ======== 开始登录 ========');
    console.info('[DistributedService] 用户名: ' + username);
    console.info('[DistributedService] 服务地址: ' + DistributedService.API_BASE + '/auth/login');

    this.currentState.state = SyncConnectionState.CONNECTING;
    this.currentState.lastMessage = '正在登录云服务器...';
    this.emitState();

    try {
      let loginBody: LoginBody = {
        username: username,
        password: password,
        deviceName: AppStorage.get<string>('deviceName') ?? 'HarmonyOS设备'
      };
      let responseObj: Record<string, Object> = await this.post('/auth/login', JsonSafe.stringify(loginBody));
      let response: ApiResponse<LoginResponse> = this.toApiResponse<LoginResponse>(responseObj);
      const loginData: LoginResponse = this.requireResponseData<LoginResponse>(response, '登录失败');

      this.applyLoginResponse(loginData, '登录成功', syncAfterLogin);
      return true;
    } catch (err) {
      this.currentState.state = SyncConnectionState.ERROR;
      const error: BusinessError = err as BusinessError;
      this.currentState.lastMessage = '登录失败: ' + error.message;
      this.emitState();
      return false;
    }
  }

  // ===== 注册 =====
  async register(username: string, password: string): Promise<boolean> {
    this.currentState.state = SyncConnectionState.CONNECTING;
    this.currentState.lastMessage = '正在注册云端账号...';
    this.emitState();

    console.info('[DistributedService] ======== 开始注册 ========');
    console.info('[DistributedService] 用户名: ' + username);
    console.info('[DistributedService] 服务地址: ' + DistributedService.API_BASE + '/auth/register');

    try {
      let registerBody: RegisterBody = {
        username: username,
        password: password,
        deviceName: AppStorage.get<string>('deviceName') ?? 'HarmonyOS设备'
      };
      let responseObj: Record<string, Object> = await this.post('/auth/register', JsonSafe.stringify(registerBody));
      let response: ApiResponse<LoginResponse> = this.toApiResponse<LoginResponse>(responseObj);
      const registerData: LoginResponse = this.requireResponseData<LoginResponse>(response, '注册失败');

      this.applyLoginResponse(registerData, '注册成功');
      return true;
    } catch (err) {
      this.currentState.state = SyncConnectionState.ERROR;
      const error: BusinessError = err as BusinessError;
      this.currentState.lastMessage = '注册失败: ' + error.message;
      this.emitState();
      return false;
    }
  }

  // ===== 退出登录 =====
  async logout(): Promise<void> {
    this.currentState.lastMessage = '正在退出登录...';
    this.emitState();

    try {
      const token: string = this.getToken();
      if (token.length > 0) {
        let logoutBody: LogoutBody = { dummy: '' };
        await this.post('/auth/logout', JsonSafe.stringify(logoutBody));
      }
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.warn('[DistributedService] 服务端登出失败:', error.message);
    }

    this.pollTask.stop();

    AppStorage.delete(DistributedService.AUTH_TOKEN_KEY);
    AppStorage.delete(DistributedService.USER_ID_KEY);
    AppStorage.delete(DistributedService.LAST_SYNC_KEY);

    this.localDeviceId = 'local_' + UUIDUtil.generateShort();
    this.currentState.state = SyncConnectionState.IDLE;
    this.currentState.lastMessage = '已退出登录';
    this.currentState.receivedPostCount = 0;
    this.currentState.receivedCommentCount = 0;
    this.currentState.transferProgress = 0;
    this.emitState();
  }

  // ===== 主动同步 =====
  async syncNow(forceFull: boolean = false): Promise<SyncResult> {
    if (!this.initialized) {
      const result: SyncResult = new SyncResult();
      result.errorMsg = '分布式同步服务未初始化';
      return result;
    }

    // ⭐ 修复：改为判断 localDeviceId 是否来自登录
    //    登录后 localDeviceId = 服务器返回的 userId（不以 "local_" 开头）
    //    未登录时 localDeviceId = "local_xxx"
    if (this.localDeviceId.startsWith('local_')) {
      const result: SyncResult = new SyncResult();
      result.errorMsg = '未登录';
      return result;
    }

    if (this.activeSyncTask !== null) {
      const activeWasFull: boolean = this.activeSyncIsFull;
      const activeResult: SyncResult = await this.activeSyncTask;
      if (forceFull && !activeWasFull && activeResult.success) {
        return await this.syncNow(true);
      }
      return activeResult;
    }

    this.activeSyncIsFull = forceFull;
    const task: Promise<SyncResult> = this.runSync(forceFull);
    this.activeSyncTask = task;
    try {
      return await task;
    } finally {
      if (this.activeSyncTask === task) {
        this.activeSyncTask = null;
        this.activeSyncIsFull = false;
      }
    }
  }

  private async runSync(forceFull: boolean): Promise<SyncResult> {
    const result: SyncResult = new SyncResult();

    this.syncing = true;
    this.currentState.state = SyncConnectionState.SYNCING;
    this.currentState.lastMessage = forceFull ? '正在进行全量同步' : '正在同步最新变化';
    this.currentState.transferProgress = 0;
    this.emitState();

    try {
      let transfer: SyncTransferResult;
      try {
        transfer = await this.performSyncTransfer(forceFull);
      } catch (err) {
        const firstError: BusinessError = err as BusinessError;
        if (!this.isAuthTokenError(firstError.message)) {
          throw new Error(firstError.message);
        }

        this.currentState.lastMessage = '登录凭据已过期，正在自动恢复登录...';
        this.emitState();
        const recovered: boolean = await this.recoverAuthentication();
        if (!recovered) {
          throw new Error('登录凭据已失效，自动重新登录失败，请检查账号密码');
        }

        this.currentState.state = SyncConnectionState.SYNCING;
        this.currentState.lastMessage = '登录已恢复，正在继续同步';
        this.emitState();
        transfer = await this.performSyncTransfer(forceFull);
      }

      result.success = true;
      result.syncCount = transfer.totalCount;
      this.currentState.state = SyncConnectionState.CONNECTED;
      this.currentState.lastSyncTime = Date.now();
      this.currentState.lastMessage = '已发送 ' + transfer.upload.acceptedPostIds.length + ' 条帖子、'
        + transfer.upload.acceptedCommentIds.length + ' 条评论，接收 '
        + transfer.download.posts.length + ' 条帖子、' + transfer.download.comments.length + ' 条评论';
      this.currentState.transferProgress = 100;
      this.emitState();

      if (transfer.totalCount > 0) {
        this.eventBus.emitRemoteDataChanged();
      }
      return result;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      result.errorMsg = error.message;
      this.currentState.state = SyncConnectionState.ERROR;
      this.currentState.lastMessage = '同步失败: ' + result.errorMsg;
      this.emitState();
      return result;
    } finally {
      this.syncing = false;
      this.emitState();
    }
  }

  // ===== 上传图片 =====
  async uploadImages(localUris: string[]): Promise<string[]> {
    if (this.context === null) {
      throw new Error('应用上下文不可用');
    }
    this.currentState.lastMessage = '正在上传图片到云服务器...';
    this.emitState();

    const remoteUrls: string[] = [];
    for (let i = 0; i < localUris.length; i++) {
      const remoteUrl: string = await this.uploadSingleImage(localUris[i], 'photo_' + i + '.jpg');
      remoteUrls.push(remoteUrl);
    }
    this.currentState.lastMessage = '图片上传完成';
    this.emitState();
    return remoteUrls;
  }

  // ===== 释放资源 =====
  async release(): Promise<void> {
    this.pollTask.stop();
    this.eventBus.offSyncRequested(this.syncRequestListener);
    if (this.httpClient !== null) {
      this.httpClient.destroy();
      this.httpClient = null;
    }
    this.initialized = false;
    this.currentState.state = SyncConnectionState.IDLE;
    this.currentState.lastMessage = '云同步服务已停止';
    this.emitState();
  }

  // ============================================================
  // 以下为空实现/保留的方法
  // ============================================================

  startDiscovery(): void {
    console.info('[DistributedService] 云模式无需设备发现');
  }

  stopDiscovery(): void {
    console.info('[DistributedService] 云模式无需设备发现');
  }

  async connectDevice(deviceId: string): Promise<void> {
    console.info('[DistributedService] 云模式请使用 login() 连接云服务器');
    let token: string | undefined = AppStorage.get<string>(DistributedService.AUTH_TOKEN_KEY);
    if (token === undefined || token.length === 0) {
      throw new Error('未登录，请先调用 login()');
    }
  }

  async refreshAvailableDevices(): Promise<SyncDeviceInfo[]> {
    return [];
  }

  // ============================================================
  // 内部方法
  // ============================================================

  private onSyncRequestedInternal(): void {
    let self: DistributedService = this;
    self.syncNow(false).catch((err: Error) => {
      console.error('[DistributedService] 自动同步失败:', err.message);
    });
  }

  private async uploadSingleImage(localUri: string, fileName: string): Promise<string> {
    const file: fs.File = fs.openSync(localUri, fs.OpenMode.READ_ONLY);
    const stat: fs.Stat = fs.statSync(localUri);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    fs.readSync(file.fd, buf);
    fs.closeSync(file);

    const uint8Array: Uint8Array = new Uint8Array(buf);
    let binaryStr: string = '';
    for (let i = 0; i < uint8Array.byteLength; i++) {
      binaryStr += String.fromCharCode(uint8Array[i]);
    }
    const base64: string = btoa(binaryStr);

    let uploadBody: UploadImageBody = {
      fileName: fileName,
      fileData: base64,
      fileType: 'image/jpeg'
    };

    let responseObj: Record<string, Object> = await this.post('/images/upload', JsonSafe.stringify(uploadBody));
    let response: ApiResponse<UploadImageResponse> = this.toApiResponse<UploadImageResponse>(responseObj);
    const uploadData: UploadImageResponse =
      this.requireResponseData<UploadImageResponse>(response, '图片上传失败');
    if (uploadData.remoteUrls.length === 0) {
      throw new Error('图片上传失败: 服务器未返回图片地址');
    }
    return uploadData.remoteUrls[0];
  }

  private async pushLocalData(forceFull: boolean): Promise<SyncUploadResponse> {
    const unsyncedPosts: PostModel[] = await this.postRepository.queryUnsyncedPosts();
    const unsyncedComments: CommentModel[] = await this.commentRepository.queryUnsyncedComments();

    if (!forceFull && unsyncedPosts.length === 0 && unsyncedComments.length === 0) {
      let empty: SyncUploadResponse = { acceptedPostIds: [], acceptedCommentIds: [] };
      return empty;
    }

    let postsToSync: PostModel[] = unsyncedPosts;
    let commentsToSync: CommentModel[] = unsyncedComments;

    if (forceFull) {
      const allPosts: PostModel[] = await this.postRepository.queryAllPosts();
      const allComments: CommentModel[] = await this.commentRepository.queryAllComments();

      let existingIds: Set<string> = new Set<string>();
      for (let i = 0; i < unsyncedPosts.length; i++) {
        existingIds.add(unsyncedPosts[i].postId);
      }
      for (let i = 0; i < allPosts.length; i++) {
        if (!existingIds.has(allPosts[i].postId) && allPosts[i].userId === this.localDeviceId) {
          postsToSync.push(allPosts[i]);
        }
      }

      existingIds = new Set<string>();
      for (let i = 0; i < unsyncedComments.length; i++) {
        existingIds.add(unsyncedComments[i].commentId);
      }
      for (let i = 0; i < allComments.length; i++) {
        if (!existingIds.has(allComments[i].commentId) && allComments[i].userId === this.localDeviceId) {
          commentsToSync.push(allComments[i]);
        }
      }
    }

    const postDataList: SyncPostData[] = [];
    for (let i = 0; i < postsToSync.length; i++) {
      postDataList.push(await this.createPostSyncData(postsToSync[i]));
    }
    const commentDataList: SyncCommentData[] = [];
    for (let i = 0; i < commentsToSync.length; i++) {
      commentDataList.push(SyncCommentData.fromModel(commentsToSync[i]));
    }

    let syncBody: SyncUploadBody = {
      posts: postDataList,
      comments: commentDataList,
      deviceId: this.localDeviceId
    };

    let responseObj: Record<string, Object> = await this.post('/sync/upload', JsonSafe.stringify(syncBody));
    let response: ApiResponse<SyncUploadResponse> = this.toApiResponse<SyncUploadResponse>(responseObj);
    const uploadData: SyncUploadResponse =
      this.requireResponseData<SyncUploadResponse>(response, '同步上传失败');

    for (let i = 0; i < uploadData.acceptedPostIds.length; i++) {
      await this.postRepository.updatePostSyncStatus(uploadData.acceptedPostIds[i], 1);
    }
    for (let i = 0; i < uploadData.acceptedCommentIds.length; i++) {
      await this.commentRepository.updateCommentSyncStatus(uploadData.acceptedCommentIds[i], 1);
    }

    return uploadData;
  }

  private async createPostSyncData(post: PostModel): Promise<SyncPostData> {
    const data: SyncPostData = SyncPostData.fromModel(post);
    const remoteImagePaths: string[] = [];
    for (let i = 0; i < data.imagePaths.length; i++) {
      const imagePath: string = data.imagePaths[i];
      if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        remoteImagePaths.push(imagePath);
      } else if (imagePath.length > 0) {
        const remoteUrl: string = await this.uploadSingleImage(
          imagePath,
          post.postId + '_' + i + '.jpg'
        );
        remoteImagePaths.push(remoteUrl);
      }
    }
    data.imagePaths = remoteImagePaths;
    return data;
  }

  private async pullRemoteData(forceFull: boolean = false): Promise<SyncDownloadResponse> {
    let lastSyncVal: number | undefined = AppStorage.get<number>(DistributedService.LAST_SYNC_KEY);
    const lastSync: number = forceFull ? 0 : (lastSyncVal ?? 0);

    let pullBody: SyncDownloadBody = {
      lastSyncTimestamp: lastSync,
      deviceId: this.localDeviceId
    };

    let responseObj: Record<string, Object> = await this.post('/sync/download', JsonSafe.stringify(pullBody));
    let response: ApiResponse<SyncDownloadResponse> = this.toApiResponse<SyncDownloadResponse>(responseObj);
    const data: SyncDownloadResponse =
      this.requireResponseData<SyncDownloadResponse>(response, '同步拉取失败');

    for (let i = 0; i < data.posts.length; i++) {
      const postData: SyncPostData = this.hydrateSyncPost(data.posts[i]);
      const post: PostModel = postData.toModel(new Map<string, string>());
      await this.postRepository.upsertRemotePost(post);
    }
    for (let i = 0; i < data.comments.length; i++) {
      const commentData: SyncCommentData = this.hydrateSyncComment(data.comments[i]);
      const comment: CommentModel = commentData.toModel();
      await this.commentRepository.upsertRemoteComment(comment);
    }

    if (data.lastSyncTimestamp > lastSync) {
      AppStorage.setOrCreate<number>(DistributedService.LAST_SYNC_KEY, data.lastSyncTimestamp);
    }

    this.currentState.receivedPostCount += data.posts.length;
    this.currentState.receivedCommentCount += data.comments.length;

    this.emitState();
    return data;
  }

  private hydrateSyncPost(source: SyncPostData): SyncPostData {
    const target: SyncPostData = new SyncPostData();
    target.postId = source.postId;
    target.userId = source.userId;
    target.userName = source.userName;
    target.userAvatar = source.userAvatar;
    target.content = source.content;
    target.imagePaths = source.imagePaths;
    target.categoryId = source.categoryId;
    target.categoryName = source.categoryName;
    target.likeCount = source.likeCount;
    target.commentCount = source.commentCount;
    target.createTime = source.createTime;
    target.updateTime = source.updateTime;
    target.deviceId = source.deviceId;
    target.isDeleted = source.isDeleted;
    return target;
  }

  private hydrateSyncComment(source: SyncCommentData): SyncCommentData {
    const target: SyncCommentData = new SyncCommentData();
    target.commentId = source.commentId;
    target.postId = source.postId;
    target.userId = source.userId;
    target.userName = source.userName;
    target.userAvatar = source.userAvatar;
    target.content = source.content;
    target.parentId = source.parentId;
    target.replyToUserId = source.replyToUserId;
    target.replyToUserName = source.replyToUserName;
    target.level = source.level;
    target.likeCount = source.likeCount;
    target.createTime = source.createTime;
    target.deviceId = source.deviceId;
    target.isDeleted = source.isDeleted;
    return target;
  }

  private onPollTick(): void {
    if (this.initialized && !this.syncing) {
      let self: DistributedService = this;
      self.syncNow(false).then((result: SyncResult): void => {
        if (!result.success) {
          console.warn('[DistributedService] 轮询同步失败:', result.errorMsg);
        }
      }).catch((err: Error) => {
        console.warn('[DistributedService] 轮询同步异常:', err.message);
      });
    }
  }

  private getToken(): string {
    let token: string | undefined = AppStorage.get<string>(DistributedService.AUTH_TOKEN_KEY);
    return token ?? '';
  }

  private isAuthTokenError(message: string): boolean {
    const lowerMessage: string = message.toLowerCase();
    return lowerMessage.includes('invalid or expired token') ||
      lowerMessage.includes('invaild or expired token') ||
      lowerMessage.includes('missing authorization token');
  }

  private async performSyncTransfer(forceFull: boolean): Promise<SyncTransferResult> {
    let upload: SyncUploadResponse;
    try {
      upload = await this.pushLocalData(forceFull);
    } catch (err) {
      throw new Error('上传阶段失败: ' + (err as Error).message);
    }

    let download: SyncDownloadResponse;
    try {
      download = await this.pullRemoteData(forceFull);
    } catch (err) {
      throw new Error('下载阶段失败: ' + (err as Error).message);
    }
    const result: SyncTransferResult = {
      upload: upload,
      download: download,
      totalCount: upload.acceptedPostIds.length + upload.acceptedCommentIds.length +
        download.posts.length + download.comments.length
    };
    return result;
  }

  private async recoverAuthentication(): Promise<boolean> {
    if (this.authRecoveryTask !== null) {
      return await this.authRecoveryTask;
    }

    this.authRecoveryTask = this.loginWithSavedCredentials();
    try {
      return await this.authRecoveryTask;
    } finally {
      this.authRecoveryTask = null;
    }
  }

  private async loginWithSavedCredentials(): Promise<boolean> {
    if (this.context === null) {
      return false;
    }

    try {
      const credential: CloudCredential | null = await CloudCredentialStore.get(this.context);
      if (credential === null) {
        console.warn('[DistributedService] 未找到可用于恢复登录的账号凭据');
        return false;
      }

      const loginBody: LoginBody = {
        username: credential.username,
        password: credential.password,
        deviceName: AppStorage.get<string>('deviceName') ?? 'HarmonyOS设备'
      };
      const responseObj: Record<string, Object> =
        await this.post('/auth/login', JsonSafe.stringify(loginBody));
      const response: ApiResponse<LoginResponse> = this.toApiResponse<LoginResponse>(responseObj);
      const loginData: LoginResponse = this.requireResponseData<LoginResponse>(response, '自动重新登录失败');
      this.applyLoginResponse(loginData, '登录已恢复', false);
      return true;
    } catch (err) {
      console.warn('[DistributedService] 自动重新登录失败:', (err as Error).message);
      return false;
    }
  }

  private applyLoginResponse(data: LoginResponse, successMessage: string, syncAfterLogin: boolean = true): void {
    AppStorage.setOrCreate<string>(DistributedService.AUTH_TOKEN_KEY, data.token);
    AppStorage.setOrCreate<string>(DistributedService.USER_ID_KEY, data.userId);

    this.localDeviceId = data.userId;
    this.currentState.lastMessage = successMessage;
    this.currentState.state = SyncConnectionState.CONNECTED;
    this.emitState();

    let self: DistributedService = this;
    if (syncAfterLogin) {
      self.syncNow(true).catch((err: Error) => {
        console.warn('[DistributedService] 首次同步失败:', err.message);
      });
    }
    self.pollTask.start(DistributedService.POLL_INTERVAL, (): void => {
      self.onPollTick();
    });
  }

  // ⭐ POST 请求核心方法
  // ⭐ POST 请求核心方法（含详细错误日志）
  private async post(endpoint: string, body: string): Promise<Record<string, Object>> {
    if (this.httpClient === null) {
      this.httpClient = http.createHttp();
    }

    const url: string = DistributedService.API_BASE + endpoint;

    console.info('[DistributedService] >>> 发起请求: ' + url);

    const requestHeaders: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + this.getToken()
    };

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: requestHeaders,
      extraData: body,
      connectTimeout: 15000,
      readTimeout: 30000
    };

    try {
      const response: http.HttpResponse = await this.httpClient.request(url, options);
      console.info('[DistributedService] <<< 响应状态码: ' + response.responseCode);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('服务器返回状态码: ' + response.responseCode);
      }
      return JSON.parse(response.result as string) as Record<string, Object>;
    } catch (err) {
      const error: BusinessError = err as BusinessError;

      // ⭐ 打印最详细的错误信息
      console.error('========================================');
      console.error('[DistributedService] ❌ 网络请求失败');
      console.error('[DistributedService]    错误码: ' + error.code);
      console.error('[DistributedService]    错误信息: ' + error.message);
      console.error('[DistributedService]    请求URL: ' + url);
      console.error('[DistributedService]    错误名称: ' + error.name);
      console.error('========================================');

      // ⭐ 根据错误码给出中文提示
      const errorCode: number = error.code;
      if (errorCode === 28) {
        throw new Error('连接超时（错误码: 28），请检查服务器是否运行或防火墙是否开放端口');
      } else if (errorCode === 2300007 || error.message.includes('could not connect')) {
        throw new Error('无法连接服务器（错误码: ' + errorCode + '），请确认后端正在运行，且云服务器安全组已开放3000端口');
      } else if (errorCode === 7 || error.message.includes('resolve')) {
        throw new Error('DNS解析失败（错误码: ' + errorCode + '），请检查服务器地址是否正确');
      } else if (errorCode === 111 || error.message.includes('refused')) {
        throw new Error('连接被拒绝（错误码: ' + errorCode + '），服务器端口3000未开放或服务未启动');
      } else if (errorCode === 110 || error.message.includes('timeout')) {
        throw new Error('连接超时（错误码: ' + errorCode + '），服务器无响应');
      } else if (errorCode === 230) {
        throw new Error('HTTPS证书校验失败（错误码: 230），请检查是否误用了https');
      } else {
        throw new Error('网络错误（错误码: ' + errorCode + '）: ' + error.message);
      }
    }
  }

  private toApiResponse<T>(obj: Record<string, Object>): ApiResponse<T> {
    let result: ApiResponse<T> = {
      success: obj['success'] as boolean,
      message: obj['message'] as string,
      data: obj['data'] as T | null
    };
    return result;
  }

  private requireResponseData<T>(response: ApiResponse<T>, fallbackMessage: string): T {
    if (!response.success) {
      const message: string = response.message.length > 0 ? response.message : fallbackMessage;
      throw new Error(message);
    }
    if (response.data === null) {
      throw new Error(fallbackMessage + ': 服务器返回数据为空');
    }
    return response.data;
  }

  private copyState(): DistributedSyncState {
    const state: DistributedSyncState = new DistributedSyncState();
    state.state = this.currentState.state;
    state.devices = this.copyDevices();
    state.lastMessage = this.currentState.lastMessage;
    state.lastSyncTime = this.currentState.lastSyncTime;
    state.transferProgress = this.currentState.transferProgress;
    state.receivedPostCount = this.currentState.receivedPostCount;
    state.receivedCommentCount = this.currentState.receivedCommentCount;
    return state;
  }

  private copyDevices(): SyncDeviceInfo[] {
    const devices: SyncDeviceInfo[] = [];
    this.deviceMap.forEach((source: SyncDeviceInfo): void => {
      const target: SyncDeviceInfo = new SyncDeviceInfo();
      target.deviceId = source.deviceId;
      target.deviceName = source.deviceName;
      target.deviceType = source.deviceType;
      target.networkId = source.networkId;
      target.trusted = source.trusted;
      target.connected = source.connected;
      devices.push(target);
    });
    return devices;
  }

  private emitState(): void {
    const snapshot: DistributedSyncState = this.copyState();
    for (let i = 0; i < this.stateListeners.length; i++) {
      this.stateListeners[i](snapshot);
    }
  }
}

// ⭐ btoa() 实现
function btoa(binaryStr: string): string {
  const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
  let output: string = '';
  const bytes: number[] = [];
  for (let i = 0; i < binaryStr.length; i++) {
    bytes.push(binaryStr.charCodeAt(i));
  }
  let i: number = 0;
  while (i < bytes.length) {
    const b1: number = bytes[i++];
    const hasB2: boolean = i < bytes.length;
    const b2: number = hasB2 ? bytes[i++] : 0;
    const hasB3: boolean = i < bytes.length;
    const b3: number = hasB3 ? bytes[i++] : 0;
    const enc1: number = b1 >> 2;
    const enc2: number = ((b1 & 3) << 4) | (b2 >> 4);
    const enc3: number = ((b2 & 15) << 2) | (b3 >> 6);
    const enc4: number = b3 & 63;
    output += chars.charAt(enc1) + chars.charAt(enc2)
      + (hasB2 ? chars.charAt(enc3) : '=')
      + (hasB3 ? chars.charAt(enc4) : '=');
  }
  return output;
}

export default DistributedService;
