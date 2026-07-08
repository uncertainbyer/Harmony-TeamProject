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
  ERROR = 4
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
  data: T;
}

interface LoginBody {
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
  private static readonly API_BASE: string = 'http://39.105.115.19:3000/api';
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
  private syncAgain: boolean = false;
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

    AppStorage.set<string>('deviceName', context.abilityInfo.name);

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
  async login(username: string, password: string): Promise<boolean> {
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
      if (!response.success) {
        throw new Error(response.message);
      }

      AppStorage.set<string>(DistributedService.AUTH_TOKEN_KEY, response.data.token);
      AppStorage.set<string>(DistributedService.USER_ID_KEY, response.data.userId);

      this.localDeviceId = response.data.userId;
      this.currentState.lastMessage = '登录成功';
      this.currentState.state = SyncConnectionState.CONNECTED;
      this.emitState();

      let self: DistributedService = this;
      self.syncNow(true).catch((err: Error) => {
        console.warn('[DistributedService] 首次同步失败:', err.message);
      });
      self.pollTask.start(DistributedService.POLL_INTERVAL, (): void => {
        self.onPollTick();
      });
      return true;
    } catch (err) {
      this.currentState.state = SyncConnectionState.ERROR;
      const error: BusinessError = err as BusinessError;
      this.currentState.lastMessage = '登录失败: ' + error.message;
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
    const result: SyncResult = new SyncResult();
    if (!this.initialized) {
      result.errorMsg = '分布式同步服务未初始化';
      return result;
    }

    // ⭐ 修复：改为判断 localDeviceId 是否来自登录
    //    登录后 localDeviceId = 服务器返回的 userId（不以 "local_" 开头）
    //    未登录时 localDeviceId = "local_xxx"
    if (this.localDeviceId.startsWith('local_')) {
      result.errorMsg = '未登录';
      return result;
    }

    if (this.syncing) {
      this.syncAgain = true;
      result.success = true;
      return result;
    }

    this.syncing = true;
    this.currentState.state = SyncConnectionState.SYNCING;
    this.currentState.lastMessage = forceFull ? '正在进行全量同步' : '正在同步最新变化';
    this.currentState.transferProgress = 0;
    this.emitState();

    try {
      const pushResult: SyncUploadResponse = await this.pushLocalData(forceFull);
      let totalCount: number = pushResult.acceptedPostIds.length + pushResult.acceptedCommentIds.length;

      const pullResult: SyncDownloadResponse = await this.pullRemoteData();
      totalCount += pullResult.posts.length + pullResult.comments.length;

      result.success = true;
      result.syncCount = totalCount;
      this.currentState.state = SyncConnectionState.CONNECTED;
      this.currentState.lastSyncTime = Date.now();
      this.currentState.lastMessage = '已发送 ' + pushResult.acceptedPostIds.length + ' 条帖子、'
        + pushResult.acceptedCommentIds.length + ' 条评论';
      this.currentState.transferProgress = 100;
      this.emitState();

      if (totalCount > 0) {
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
      if (this.syncAgain) {
        this.syncAgain = false;
        this.syncNow(false).catch((err: Error) => {
          console.error('[DistributedService] 合并同步失败:', err.message);
        });
      }
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
    if (!response.success) {
      throw new Error('图片上传失败: ' + response.message);
    }
    return response.data.remoteUrls[0];
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
        if (!existingIds.has(allPosts[i].postId)) {
          postsToSync.push(allPosts[i]);
        }
      }

      existingIds = new Set<string>();
      for (let i = 0; i < unsyncedComments.length; i++) {
        existingIds.add(unsyncedComments[i].commentId);
      }
      for (let i = 0; i < allComments.length; i++) {
        if (!existingIds.has(allComments[i].commentId)) {
          commentsToSync.push(allComments[i]);
        }
      }
    }

    const postDataList: SyncPostData[] = [];
    for (let i = 0; i < postsToSync.length; i++) {
      postDataList.push(SyncPostData.fromModel(postsToSync[i]));
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

    for (let i = 0; i < response.data.acceptedPostIds.length; i++) {
      await this.postRepository.updatePostSyncStatus(response.data.acceptedPostIds[i], 1);
    }
    for (let i = 0; i < response.data.acceptedCommentIds.length; i++) {
      await this.commentRepository.updateCommentSyncStatus(response.data.acceptedCommentIds[i], 1);
    }

    return response.data;
  }

  private async pullRemoteData(): Promise<SyncDownloadResponse> {
    let lastSyncVal: number | undefined = AppStorage.get<number>(DistributedService.LAST_SYNC_KEY);
    const lastSync: number = lastSyncVal ?? 0;

    let pullBody: SyncDownloadBody = {
      lastSyncTimestamp: lastSync,
      deviceId: this.localDeviceId
    };

    let responseObj: Record<string, Object> = await this.post('/sync/download', JsonSafe.stringify(pullBody));
    let response: ApiResponse<SyncDownloadResponse> = this.toApiResponse<SyncDownloadResponse>(responseObj);
    const data: SyncDownloadResponse = response.data;

    for (let i = 0; i < data.posts.length; i++) {
      const postData: SyncPostData = data.posts[i];
      const post: PostModel = postData.toModel(new Map<string, string>());
      await this.postRepository.upsertRemotePost(post);
    }
    for (let i = 0; i < data.comments.length; i++) {
      const commentData: SyncCommentData = data.comments[i];
      const comment: CommentModel = commentData.toModel();
      await this.commentRepository.upsertRemoteComment(comment);
    }

    if (data.lastSyncTimestamp > lastSync) {
      AppStorage.set<number>(DistributedService.LAST_SYNC_KEY, data.lastSyncTimestamp);
    }

    this.currentState.receivedPostCount += data.posts.length;
    this.currentState.receivedCommentCount += data.comments.length;

    this.emitState();
    return data;
  }

  private onPollTick(): void {
    if (this.initialized && !this.syncing) {
      let self: DistributedService = this;
      self.pullRemoteData().catch((err: Error) => {
        console.warn('[DistributedService] 轮询拉取失败:', err.message);
      });
    }
  }

  private getToken(): string {
    let token: string | undefined = AppStorage.get<string>(DistributedService.AUTH_TOKEN_KEY);
    return token ?? '';
  }

  // ⭐ POST 请求核心方法
  // ⭐ POST 请求核心方法（含详细错误日志）
  private async post(endpoint: string, body: string): Promise<Record<string, Object>> {
    if (this.httpClient === null) {
      throw new Error('HTTP客户端未初始化，请先调用 init()');
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
      if (response.responseCode !== 200) {
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
      data: obj['data'] as T
    };
    return result;
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
    const b2: number = i < bytes.length ? bytes[i++] : 0;
    const b3: number = i < bytes.length ? bytes[i++] : 0;
    const enc1: number = b1 >> 2;
    const enc2: number = ((b1 & 3) << 4) | (b2 >> 4);
    const enc3: number = ((b2 & 15) << 2) | (b3 >> 6);
    const enc4: number = b3 & 63;
    output += chars.charAt(enc1) + chars.charAt(enc2)
      + (i >= bytes.length + 1 ? '=' : chars.charAt(enc3))
      + (i >= bytes.length ? '=' : chars.charAt(enc4));
  }
  return output;
}

export default DistributedService;