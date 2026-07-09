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

  static getInstance(): DistributedApi {
    if (!DistributedApi.instance) { DistributedApi.instance = new DistributedApi(); }
    return DistributedApi.instance;
  }

  async init(ctx: common.UIAbilityContext): Promise<void> { await this.d.init(ctx); }
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

  async login(username: string, password: string): Promise<ApiResult<boolean>> {
    try {
      const ok = await this.d.login(username, password);
      return { success: ok, data: ok, code: ok ? ErrorCode.SUCCESS : ErrorCode.SERVER_ERROR, message: ok ? '' : '登录失败' };
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
    return await this.d.syncNow(forceFull);
  }

  async uploadImages(uris: string[]): Promise<string[]> {
    return await this.d.uploadImages(uris);
  }

  async release(): Promise<void> { await this.d.release(); }
}

export { DistributedApi, SyncConnectionState, DistributedSyncState, SyncDeviceInfo, SyncResult };
export const distributedApi = DistributedApi.getInstance();