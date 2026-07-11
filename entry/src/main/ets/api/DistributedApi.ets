import {
  DistributedService,
  DistributedSyncState,
  SyncConnectionState,
  SyncDeviceInfo,
  SyncResult,
  SyncStateListener,
} from '../service/DistributedService';
import { common } from '@kit.AbilityKit';
import { ApiResult } from './PostApi';
import { ErrorCode } from '../common/Constants';

class DistributedApi {
  private static instance: DistributedApi | null = null;
  private d = DistributedService.getInstance();
  private initTask: Promise<void> | null = null;

  static getInstance(): DistributedApi {
    if (!DistributedApi.instance) { DistributedApi.instance = new DistributedApi(); }
    return DistributedApi.instance;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> {
    AppStorage.setOrCreate<object>('uiAbilityContext', ctx);
    await this.runInit(ctx);
  }
  isReady(): boolean { return this.d.isReady(); }
  get localDeviceId(): string { return this.d.getLocalDeviceId(); }

  get state(): DistributedSyncState { return this.d.getState(); }
  onChanged(cb: SyncStateListener): void { this.d.onStateChanged(cb); }
  offChanged(cb: SyncStateListener): void { this.d.offStateChanged(cb); }

  startDiscovery(): void { this.d.startDiscovery(); }
  stopDiscovery(): void { this.d.stopDiscovery(); }

  async refreshDevices(): Promise<SyncDeviceInfo[]> {
    return await this.d.refreshAvailableDevices();
  }

  async connect(deviceId: string): Promise<void> {
    await this.d.connectDevice(deviceId);
  }

  async login(username: string, password: string, syncAfterLogin: boolean = true): Promise<ApiResult<boolean>> {
    try {
      await this.ensureReady();
      const ok = await this.d.login(username, password, syncAfterLogin);
      return {
        success: ok,
        data: ok,
        code: ok ? ErrorCode.SUCCESS : ErrorCode.SERVER_ERROR,
        message: ok ? '' : this.getServiceMessage('登录失败', '登录失败: ')
      };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async register(username: string, password: string): Promise<ApiResult<boolean>> {
    try {
      await this.ensureReady();
      const ok = await this.d.register(username, password);
      return {
        success: ok,
        data: ok,
        code: ok ? ErrorCode.SUCCESS : ErrorCode.SERVER_ERROR,
        message: ok ? '' : this.getServiceMessage('注册失败', '注册失败: ')
      };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async logout(): Promise<ApiResult<void>> {
    try {
      await this.d.logout();
      return { success: true, data: null, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async sync(forceFull: boolean): Promise<SyncResult> {
    await this.ensureReady();
    return await this.d.syncNow(forceFull);
  }

  async uploadImages(uris: string[]): Promise<string[]> {
    await this.ensureReady();
    return await this.d.uploadImages(uris);
  }

  async release(): Promise<void> { await this.d.release(); }

  private async ensureReady(): Promise<void> {
    if (this.d.isReady()) {
      return;
    }
    const context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
    if (context === undefined) {
      throw new Error('同步服务尚未初始化，请稍后再试');
    }
    await this.runInit(context);
  }

  private async runInit(ctx: common.UIAbilityContext): Promise<void> {
    if (this.d.isReady()) {
      return;
    }
    if (this.initTask !== null) {
      await this.initTask;
      return;
    }
    this.initTask = this.d.init(ctx);
    try {
      await this.initTask;
    } finally {
      this.initTask = null;
    }
  }

  private getServiceMessage(fallback: string, prefix: string): string {
    const message: string = this.d.getState().lastMessage;
    if (message.length === 0) {
      return fallback;
    }
    if (message.startsWith(prefix)) {
      return message.substring(prefix.length);
    }
    return message;
  }
}

export { DistributedApi, SyncConnectionState, DistributedSyncState, SyncDeviceInfo, SyncResult };
export const distributedApi = DistributedApi.getInstance();
