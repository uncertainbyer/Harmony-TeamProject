import { common } from '@kit.AbilityKit';
import { commonType, distributedDataObject } from '@kit.ArkData';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { PostModel } from '../model/PostModel';
import { CommentModel } from '../model/CommentModel';
import { PostRepository } from '../repository/PostRepository';
import { CommentRepository } from '../repository/CommentRepository';
import { UUIDUtil } from '../utils/UUIDUtil';
import { SyncEventBus, SyncRequestListener } from '../distributed/SyncEventBus';
import {
  ASSET_PREFIX,
  CONTROL_SESSION_ID,
  SYNC_PROTOCOL_VERSION,
  SyncAnnouncement,
  SyncCommentData,
  SyncControlState,
  SyncEnvelope,
  SyncPostData,
  SyncTransferState
} from '../distributed/SyncProtocol';

export enum SyncConnectionState {
  IDLE = 0,
  DISCOVERING = 1,
  CONNECTING = 2,
  CONNECTED = 3,
  SYNCING = 4,
  ERROR = 5
}

export class SyncDeviceInfo {
  deviceId: string = '';
  deviceName: string = '';
  deviceType: string = '';
  networkId: string = '';
  trusted: boolean = false;
  connected: boolean = false;
}

export class DistributedSyncState {
  state: SyncConnectionState = SyncConnectionState.IDLE;
  devices: SyncDeviceInfo[] = [];
  lastMessage: string = '';
  lastSyncTime: number = 0;
  transferProgress: number = 0;
  receivedPostCount: number = 0;
  receivedCommentCount: number = 0;
}

export class SyncResult {
  success: boolean = false;
  syncCount: number = 0;
  errorMsg: string = '';
}

export type SyncStateListener = (state: DistributedSyncState) => void;

interface DeviceDiscoveryResult {
  device: distributedDeviceManager.DeviceBasicInfo;
}

interface DeviceStateResult {
  action: distributedDeviceManager.DeviceStateChange;
  device: distributedDeviceManager.DeviceBasicInfo;
}

interface DeviceBindResult {
  deviceId: string;
}

class IncomingBatch {
  announcement: SyncAnnouncement = new SyncAnnouncement();
  dataObject: distributedDataObject.DataObject | null = null;
  assetsReady: boolean = false;
  applied: boolean = false;
}

/**
 * 分布式同步中心。
 *
 * 设备管理器负责发现和PIN绑定；固定控制会话负责发布批次ID；每个批次使用独立
 * DataObject会话同步帖子、评论和图片Asset。接收端完成落库后通过SyncEventBus通知UI刷新。
 */
export class DistributedService {
  private static instance: DistributedService | null = null;
  private context: common.UIAbilityContext | null = null;
  private deviceManager: distributedDeviceManager.DeviceManager | null = null;
  private controlObject: distributedDataObject.DataObject | null = null;
  private postRepository: PostRepository = new PostRepository();
  private commentRepository: CommentRepository = new CommentRepository();
  private eventBus: SyncEventBus = SyncEventBus.getInstance();
  private deviceMap: Map<string, SyncDeviceInfo> = new Map<string, SyncDeviceInfo>();
  private outgoingBatches: Map<string, distributedDataObject.DataObject> =
    new Map<string, distributedDataObject.DataObject>();
  private incomingBatches: Map<string, IncomingBatch> = new Map<string, IncomingBatch>();
  private processedBatchIds: Set<string> = new Set<string>();
  private stateListeners: SyncStateListener[] = [];
  private currentState: DistributedSyncState = new DistributedSyncState();
  private localDeviceId: string = '';
  private initialized: boolean = false;
  private syncing: boolean = false;
  private syncAgain: boolean = false;

  private syncRequestListener: SyncRequestListener = (): void => {
    this.requestAutomaticSync();
  };

  private discoveryListener = (result: DeviceDiscoveryResult): void => {
    this.mergeDevice(result.device, false, false);
    this.currentState.lastMessage = '发现设备：' + result.device.deviceName;
    this.emitState();
  };

  private deviceStateListener = (result: DeviceStateResult): void => {
    const connected: boolean = result.action === distributedDeviceManager.DeviceStateChange.AVAILABLE;
    const trusted: boolean = result.action !== distributedDeviceManager.DeviceStateChange.UNKNOWN;
    this.mergeDevice(result.device, trusted, connected);
    this.currentState.state = connected ? SyncConnectionState.CONNECTED : SyncConnectionState.IDLE;
    this.currentState.lastMessage = connected ?
      result.device.deviceName + ' 已连接' : result.device.deviceName + ' 已离线';
    this.emitState();
    if (connected) {
      this.syncNow(true).catch((err: Error) => {
        console.error('[DistributedService] 设备上线全量同步失败:', err.message);
      });
    }
  };

  private controlChangeListener = (sessionId: string, fields: string[]): void => {
    if (sessionId === CONTROL_SESSION_ID && fields.indexOf('announcementJson') >= 0) {
      this.processControlAnnouncement();
    }
  };

  private controlStatusListener = (sessionId: string, networkId: string, status: string): void => {
    if (sessionId !== CONTROL_SESSION_ID) {
      return;
    }
    this.updateDeviceConnectionByNetworkId(networkId, status === 'online');
    this.currentState.state = status === 'online' ? SyncConnectionState.CONNECTED : SyncConnectionState.IDLE;
    this.currentState.lastMessage = status === 'online' ? '分布式数据通道已连接' : '分布式数据通道已断开';
    this.emitState();
    if (status === 'online') {
      this.processControlAnnouncement();
      this.syncNow(true).catch((err: Error) => {
        console.error('[DistributedService] 数据通道上线同步失败:', err.message);
      });
    }
  };

  private constructor() {
  }

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
    const dbResult = await DatabaseHelper.getInstance().init(context);
    if (!dbResult.success) {
      throw new Error('数据库初始化失败: ' + dbResult.errorMsg);
    }

    await this.ensureDistributedPermission();
    this.deviceManager = distributedDeviceManager.createDeviceManager(context.applicationInfo.name);
    this.localDeviceId = this.getLocalNetworkIdSafely();
    this.deviceManager.on('discoverSuccess', this.discoveryListener);
    this.deviceManager.on('deviceStateChange', this.deviceStateListener);

    const controlState: SyncControlState = new SyncControlState();
    this.controlObject = distributedDataObject.create(context, controlState);
    this.controlObject.on('change', this.controlChangeListener);
    this.controlObject.on('status', this.controlStatusListener);
    await this.controlObject.setSessionId(CONTROL_SESSION_ID);

    this.eventBus.onSyncRequested(this.syncRequestListener);
    this.initialized = true;
    await this.refreshAvailableDevices();
    this.currentState.lastMessage = '分布式同步服务已就绪';
    this.emitState();

    try {
      this.startDiscovery();
    } catch (err) {
      console.warn('[DistributedService] 自动发现未启动:', this.errorMessage(err));
    }
  }

  isReady(): boolean {
    return this.initialized;
  }

  getLocalDeviceId(): string {
    return this.localDeviceId;
  }

  onStateChanged(listener: SyncStateListener): void {
    if (this.stateListeners.indexOf(listener) < 0) {
      this.stateListeners.push(listener);
    }
    listener(this.copyState());
  }

  offStateChanged(listener: SyncStateListener): void {
    const index: number = this.stateListeners.indexOf(listener);
    if (index >= 0) {
      this.stateListeners.splice(index, 1);
    }
  }

  getState(): DistributedSyncState {
    return this.copyState();
  }

  startDiscovery(): void {
    if (this.deviceManager === null) {
      throw new Error('设备管理器尚未初始化');
    }
    const discoverParam: Record<string, Object> = {
      'discoverTargetType': 1
    };
    this.deviceManager.startDiscovering(discoverParam);
    this.currentState.state = SyncConnectionState.DISCOVERING;
    this.currentState.lastMessage = '正在搜索附近设备（同一局域网）';
    this.emitState();
  }

  stopDiscovery(): void {
    if (this.deviceManager === null) {
      return;
    }
    this.deviceManager.stopDiscovering();
    if (this.currentState.state === SyncConnectionState.DISCOVERING) {
      this.currentState.state = SyncConnectionState.IDLE;
    }
    this.currentState.lastMessage = '已停止搜索设备';
    this.emitState();
  }

  async refreshAvailableDevices(): Promise<SyncDeviceInfo[]> {
    if (this.deviceManager === null) {
      return [];
    }
    const devices: distributedDeviceManager.DeviceBasicInfo[] =
      await this.deviceManager.getAvailableDeviceList();
    for (let i: number = 0; i < devices.length; i++) {
      this.mergeDevice(devices[i], true, true);
    }
    this.emitState();
    return this.copyDevices();
  }

  async connectDevice(deviceId: string): Promise<void> {
    if (this.deviceManager === null) {
      throw new Error('设备管理器尚未初始化');
    }
    const known: SyncDeviceInfo | undefined = this.deviceMap.get(deviceId);
    if (known !== undefined && known.trusted && known.connected) {
      await this.syncNow(true);
      return;
    }

    this.currentState.state = SyncConnectionState.CONNECTING;
    this.currentState.lastMessage = '正在请求设备授权连接';
    this.emitState();
    const bindParams: Record<string, Object> = {
      'bindType': 1,
      'targetPkgName': 'com.example.photo',
      'appName': 'SocialPhoto',
      'appOperation': '同步图文和评论',
      'customDescription': '连接后两台设备将共享帖子、图片和评论'
    };

    await new Promise<void>((resolve, reject) => {
      if (this.deviceManager === null) {
        reject(new Error('设备管理器不可用'));
        return;
      }
      this.deviceManager.bindTarget(
        deviceId,
        bindParams,
        (err: BusinessError, result: DeviceBindResult): void => {
          if (err) {
            reject(new Error('设备连接失败: ' + err.message));
            return;
          }
          const device: SyncDeviceInfo | undefined = this.deviceMap.get(result.deviceId);
          if (device !== undefined) {
            device.trusted = true;
            device.connected = true;
          }
          resolve();
        }
      );
    });

    await this.refreshAvailableDevices();
    this.currentState.state = SyncConnectionState.CONNECTED;
    this.currentState.lastMessage = '设备连接成功，开始全量同步';
    this.emitState();
    await this.syncNow(true);
  }

  /**
   * 发送同步批次。forceFull=true用于新设备连接后的首次全量共享，否则只发送未同步变更。
   */
  async syncNow(forceFull: boolean = false): Promise<SyncResult> {
    const result: SyncResult = new SyncResult();
    if (!this.initialized || this.context === null || this.controlObject === null) {
      result.errorMsg = '分布式同步服务未初始化';
      return result;
    }
    if (this.syncing) {
      this.syncAgain = true;
      result.success = true;
      return result;
    }

    this.syncing = true;
    this.currentState.state = SyncConnectionState.SYNCING;
    this.currentState.lastMessage = forceFull ? '正在进行全量数据共享' : '正在同步最新变化';
    this.currentState.transferProgress = 0;
    this.emitState();

    try {
      const posts: PostModel[] = await this.collectPosts(forceFull);
      const comments: CommentModel[] = await this.collectComments(forceFull);
      if (posts.length === 0 && comments.length === 0) {
        result.success = true;
        this.currentState.state = SyncConnectionState.CONNECTED;
        this.currentState.lastMessage = '所有数据均已同步';
        return result;
      }

      const batchId: string = 'social_batch_' + UUIDUtil.generateTimestamp();
      const envelope: SyncEnvelope = new SyncEnvelope();
      envelope.batchId = batchId;
      envelope.sourceDeviceId = this.localDeviceId;
      envelope.sentAt = Date.now();

      const assetUris: string[] = [];
      for (let i: number = 0; i < posts.length; i++) {
        const postData: SyncPostData = SyncPostData.fromModel(posts[i]);
        postData.imagePaths = await this.stagePostImages(postData, batchId, assetUris);
        envelope.posts.push(postData);
      }
      for (let i: number = 0; i < comments.length; i++) {
        envelope.comments.push(SyncCommentData.fromModel(comments[i]));
      }

      const transferState: SyncTransferState = new SyncTransferState();
      transferState.envelopeJson = JSON.stringify(envelope);
      const transferObject: distributedDataObject.DataObject =
        distributedDataObject.create(this.context, transferState);
      if (assetUris.length > 0) {
        await transferObject.setAssets('images', assetUris);
      }
      transferObject.on('progressChanged', (sessionId: string, progress: number): void => {
        if (sessionId === batchId) {
          this.currentState.transferProgress = progress;
          this.currentState.lastMessage = progress < 0 ? '图片传输异常' : '图片同步进度 ' + progress + '%';
          this.emitState();
        }
      });
      await transferObject.setSessionId(batchId);
      this.outgoingBatches.set(batchId, transferObject);

      const announcement: SyncAnnouncement = new SyncAnnouncement();
      announcement.batchId = batchId;
      announcement.sourceDeviceId = this.localDeviceId;
      announcement.expectedAssetCount = assetUris.length;
      announcement.sentAt = envelope.sentAt;
      this.controlObject['announcementJson'] = JSON.stringify(announcement);

      await this.markPostsSynced(posts);
      await this.markCommentsSynced(comments);
      result.success = true;
      result.syncCount = posts.length + comments.length;
      this.currentState.state = SyncConnectionState.CONNECTED;
      this.currentState.lastSyncTime = Date.now();
      this.currentState.lastMessage = '已发送 ' + posts.length + ' 条帖子、' + comments.length + ' 条评论';
      if (assetUris.length === 0) {
        this.currentState.transferProgress = 100;
      }
      return result;
    } catch (err) {
      result.errorMsg = this.errorMessage(err);
      this.currentState.state = SyncConnectionState.ERROR;
      this.currentState.lastMessage = '同步失败：' + result.errorMsg;
      console.error('[DistributedService] 同步失败:', result.errorMsg);
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

  async release(): Promise<void> {
    this.eventBus.offSyncRequested(this.syncRequestListener);
    if (this.controlObject !== null) {
      this.controlObject.off('change', this.controlChangeListener);
      this.controlObject.off('status', this.controlStatusListener);
      await this.controlObject.setSessionId('');
      this.controlObject = null;
    }
    if (this.deviceManager !== null) {
      try {
        this.deviceManager.stopDiscovering();
      } catch (err) {
        console.warn('[DistributedService] 停止发现失败:', this.errorMessage(err));
      }
      this.deviceManager.off('discoverSuccess', this.discoveryListener);
      this.deviceManager.off('deviceStateChange', this.deviceStateListener);
      distributedDeviceManager.releaseDeviceManager(this.deviceManager);
      this.deviceManager = null;
    }
    this.initialized = false;
  }

  private requestAutomaticSync(): void {
    this.syncNow(false).catch((err: Error) => {
      console.error('[DistributedService] 自动同步失败:', err.message);
    });
  }

  private async ensureDistributedPermission(): Promise<void> {
    if (this.context === null) {
      throw new Error('应用上下文不可用');
    }
    const permission: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC';
    const atManager = abilityAccessCtrl.createAtManager();
    const tokenId: number = this.context.applicationInfo.accessTokenId;
    const status = await atManager.checkAccessToken(tokenId, permission);
    if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      return;
    }
    const permissions: Permissions[] = [permission];
    const result = await atManager.requestPermissionsFromUser(this.context, permissions);
    if (result.authResults.length === 0 || result.authResults[0] !== 0) {
      throw new Error('用户未授予分布式数据同步权限');
    }
  }

  private async collectPosts(forceFull: boolean): Promise<PostModel[]> {
    const result: PostModel[] = await this.postRepository.queryUnsyncedPosts();
    if (!forceFull) {
      return result;
    }
    const allPosts: PostModel[] = await this.postRepository.queryAllPosts();
    const idSet: Set<string> = new Set<string>();
    for (let i: number = 0; i < result.length; i++) {
      idSet.add(result[i].postId);
    }
    for (let i: number = 0; i < allPosts.length; i++) {
      if (!idSet.has(allPosts[i].postId)) {
        result.push(allPosts[i]);
      }
    }
    return result;
  }

  private async collectComments(forceFull: boolean): Promise<CommentModel[]> {
    const result: CommentModel[] = await this.commentRepository.queryUnsyncedComments();
    if (!forceFull) {
      return result;
    }
    const allComments: CommentModel[] = await this.commentRepository.queryAllComments();
    const idSet: Set<string> = new Set<string>();
    for (let i: number = 0; i < result.length; i++) {
      idSet.add(result[i].commentId);
    }
    for (let i: number = 0; i < allComments.length; i++) {
      if (!idSet.has(allComments[i].commentId)) {
        result.push(allComments[i]);
      }
    }
    return result;
  }

  private async stagePostImages(
    post: SyncPostData,
    batchId: string,
    assetUris: string[]
  ): Promise<string[]> {
    const result: string[] = [];
    if (this.context === null) {
      return post.imagePaths;
    }
    for (let i: number = 0; i < post.imagePaths.length; i++) {
      const source: string = post.imagePaths[i];
      if (source.startsWith('http://') || source.startsWith('https://')) {
        result.push(source);
        continue;
      }
      const extension: string = this.extractExtension(source);
      const safePostId: string = post.postId.replace(/-/g, '');
      const assetName: string = batchId + '_' + safePostId + '_' + i + extension;
      const targetPath: string = this.context.distributedFilesDir + '/' + assetName;
      await fs.copyFile(source, targetPath);
      assetUris.push(this.toFileUri(targetPath));
      result.push(ASSET_PREFIX + assetName);
    }
    return result;
  }

  private processControlAnnouncement(): void {
    if (this.controlObject === null || this.context === null) {
      return;
    }
    const value: Object | null | undefined = this.controlObject['announcementJson'];
    if (typeof value !== 'string' || value.length === 0) {
      return;
    }
    try {
      const announcement: SyncAnnouncement = JSON.parse(value) as SyncAnnouncement;
      if (announcement.protocolVersion !== SYNC_PROTOCOL_VERSION ||
        announcement.sourceDeviceId === this.localDeviceId ||
        this.processedBatchIds.has(announcement.batchId) ||
        this.incomingBatches.has(announcement.batchId)) {
        return;
      }
      const transferState: SyncTransferState = new SyncTransferState();
      const transferObject: distributedDataObject.DataObject =
        distributedDataObject.create(this.context, transferState);
      const incoming: IncomingBatch = new IncomingBatch();
      incoming.announcement = announcement;
      incoming.dataObject = transferObject;
      incoming.assetsReady = announcement.expectedAssetCount === 0;
      this.incomingBatches.set(announcement.batchId, incoming);

      transferObject.on('change', (sessionId: string, fields: string[]): void => {
        if (sessionId === announcement.batchId &&
          (fields.indexOf('envelopeJson') >= 0 || fields.indexOf('images') >= 0)) {
          this.tryApplyIncomingBatch(announcement.batchId);
        }
      });
      transferObject.on('progressChanged', (sessionId: string, progress: number): void => {
        if (sessionId === announcement.batchId) {
          this.currentState.transferProgress = progress;
          this.currentState.lastMessage = progress < 0 ? '接收图片失败' : '正在接收图片 ' + progress + '%';
          this.emitState();
          if (progress === 100) {
            incoming.assetsReady = true;
            this.tryApplyIncomingBatch(announcement.batchId);
          }
        }
      });
      transferObject.setSessionId(announcement.batchId).then(() => {
        this.tryApplyIncomingBatch(announcement.batchId);
      }).catch((err: BusinessError) => {
        this.currentState.state = SyncConnectionState.ERROR;
        this.currentState.lastMessage = '加入同步批次失败：' + err.message;
        this.emitState();
      });
    } catch (err) {
      console.error('[DistributedService] 解析同步公告失败:', this.errorMessage(err));
    }
  }

  private tryApplyIncomingBatch(batchId: string): void {
    const incoming: IncomingBatch | undefined = this.incomingBatches.get(batchId);
    if (incoming === undefined || incoming.applied || incoming.dataObject === null) {
      return;
    }
    const envelopeValue: Object | null | undefined = incoming.dataObject['envelopeJson'];
    const imageValue: Object | null | undefined = incoming.dataObject['images'];
    if (typeof envelopeValue !== 'string' || envelopeValue.length === 0) {
      return;
    }
    const assets: commonType.Assets = imageValue as commonType.Assets;
    if (!incoming.assetsReady || (incoming.announcement.expectedAssetCount > 0 &&
      (assets === null || assets === undefined || assets.length < incoming.announcement.expectedAssetCount))) {
      return;
    }
    incoming.applied = true;
    this.applyIncomingEnvelope(envelopeValue, assets).then(() => {
      this.processedBatchIds.add(batchId);
      this.currentState.state = SyncConnectionState.CONNECTED;
      this.currentState.lastSyncTime = Date.now();
      this.currentState.transferProgress = 100;
      this.currentState.lastMessage = '已接收远端数据，页面已刷新';
      this.eventBus.emitRemoteDataChanged();
      this.emitState();
    }).catch((err: Error) => {
      incoming.applied = false;
      this.currentState.state = SyncConnectionState.ERROR;
      this.currentState.lastMessage = '远端数据落库失败：' + err.message;
      this.emitState();
    });
  }

  private async applyIncomingEnvelope(envelopeJson: string, assets: commonType.Assets): Promise<void> {
    const envelope: SyncEnvelope = JSON.parse(envelopeJson) as SyncEnvelope;
    if (envelope.protocolVersion !== SYNC_PROTOCOL_VERSION || envelope.sourceDeviceId === this.localDeviceId) {
      return;
    }
    const assetPathMap: Map<string, string> = new Map<string, string>();
    if (assets !== null && assets !== undefined) {
      for (let i: number = 0; i < assets.length; i++) {
        const asset: commonType.Asset = assets[i];
        const localPath: string = asset.uri.length > 0 ? asset.uri : asset.path;
        assetPathMap.set(asset.name, localPath);
      }
    }

    let receivedPosts: number = 0;
    let receivedComments: number = 0;
    for (let i: number = 0; i < envelope.posts.length; i++) {
      const postData: SyncPostData = envelope.posts[i] as SyncPostData;
      const post: PostModel = this.postDataToModel(postData, assetPathMap);
      if (await this.postRepository.upsertRemotePost(post)) {
        receivedPosts++;
      }
    }
    for (let i: number = 0; i < envelope.comments.length; i++) {
      const commentData: SyncCommentData = envelope.comments[i] as SyncCommentData;
      const comment: CommentModel = this.commentDataToModel(commentData);
      if (await this.commentRepository.upsertRemoteComment(comment)) {
        receivedComments++;
      }
    }
    this.currentState.receivedPostCount += receivedPosts;
    this.currentState.receivedCommentCount += receivedComments;
  }

  private postDataToModel(data: SyncPostData, assetPathMap: Map<string, string>): PostModel {
    const typed: SyncPostData = new SyncPostData();
    typed.postId = data.postId;
    typed.userId = data.userId;
    typed.userName = data.userName;
    typed.userAvatar = data.userAvatar;
    typed.content = data.content;
    typed.imagePaths = data.imagePaths;
    typed.categoryId = data.categoryId;
    typed.categoryName = data.categoryName;
    typed.likeCount = data.likeCount;
    typed.commentCount = data.commentCount;
    typed.createTime = data.createTime;
    typed.updateTime = data.updateTime;
    typed.deviceId = data.deviceId;
    typed.isDeleted = data.isDeleted;
    return typed.toModel(assetPathMap);
  }

  private commentDataToModel(data: SyncCommentData): CommentModel {
    const typed: SyncCommentData = new SyncCommentData();
    typed.commentId = data.commentId;
    typed.postId = data.postId;
    typed.userId = data.userId;
    typed.userName = data.userName;
    typed.userAvatar = data.userAvatar;
    typed.content = data.content;
    typed.parentId = data.parentId;
    typed.replyToUserId = data.replyToUserId;
    typed.replyToUserName = data.replyToUserName;
    typed.level = data.level;
    typed.likeCount = data.likeCount;
    typed.createTime = data.createTime;
    typed.deviceId = data.deviceId;
    typed.isDeleted = data.isDeleted;
    return typed.toModel();
  }

  private async markPostsSynced(posts: PostModel[]): Promise<void> {
    for (let i: number = 0; i < posts.length; i++) {
      await this.postRepository.updatePostSyncStatus(posts[i].postId, 1);
    }
  }

  private async markCommentsSynced(comments: CommentModel[]): Promise<void> {
    for (let i: number = 0; i < comments.length; i++) {
      await this.commentRepository.updateCommentSyncStatus(comments[i].commentId, 1);
    }
  }

  private mergeDevice(
    device: distributedDeviceManager.DeviceBasicInfo,
    trusted: boolean,
    connected: boolean
  ): void {
    let item: SyncDeviceInfo | undefined = this.deviceMap.get(device.deviceId);
    if (item === undefined) {
      item = new SyncDeviceInfo();
      item.deviceId = device.deviceId;
      this.deviceMap.set(device.deviceId, item);
    }
    item.deviceName = device.deviceName;
    item.deviceType = device.deviceType;
    item.networkId = device.networkId === undefined ? '' : device.networkId;
    item.trusted = item.trusted || trusted;
    item.connected = connected || item.connected;
  }

  private updateDeviceConnectionByNetworkId(networkId: string, connected: boolean): void {
    this.deviceMap.forEach((device: SyncDeviceInfo): void => {
      if (device.networkId === networkId) {
        device.connected = connected;
      }
    });
  }

  private getLocalNetworkIdSafely(): string {
    if (this.deviceManager === null) {
      return 'local_' + UUIDUtil.generateShort();
    }
    try {
      return this.deviceManager.getLocalDeviceNetworkId();
    } catch (err) {
      console.warn('[DistributedService] 获取本机网络ID失败:', this.errorMessage(err));
      return 'local_' + UUIDUtil.generateShort();
    }
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

  private emitState(): void {
    const snapshot: DistributedSyncState = this.copyState();
    const listeners: SyncStateListener[] = this.stateListeners.slice();
    for (let i: number = 0; i < listeners.length; i++) {
      listeners[i](snapshot);
    }
  }

  private extractExtension(path: string): string {
    const cleanPath: string = path.split('?')[0];
    const slashIndex: number = Math.max(cleanPath.lastIndexOf('/'), cleanPath.lastIndexOf('\\'));
    const dotIndex: number = cleanPath.lastIndexOf('.');
    if (dotIndex > slashIndex && cleanPath.length - dotIndex <= 6) {
      return cleanPath.substring(dotIndex).toLowerCase();
    }
    return '.jpg';
  }

  private toFileUri(path: string): string {
    return path.startsWith('file://') ? path : 'file://' + path;
  }

  private errorMessage(err: Object): string {
    const error: Error = err as Error;
    return error.message === undefined ? JSON.stringify(err) : error.message;
  }
}

export default DistributedService;
