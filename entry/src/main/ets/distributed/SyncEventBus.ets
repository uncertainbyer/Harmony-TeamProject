/**
 * 分布式同步事件总线。
 * 业务层只发出“本地数据已变化”的信号，避免与分布式模块相互依赖。
 */
export type SyncRequestListener = () => void;
export type RemoteDataListener = () => void;

export class SyncEventBus {
  private static instance: SyncEventBus | null = null;
  private syncRequestListeners: SyncRequestListener[] = [];
  private remoteDataListeners: RemoteDataListener[] = [];

  private constructor() {
  }

  static getInstance(): SyncEventBus {
    if (SyncEventBus.instance === null) {
      SyncEventBus.instance = new SyncEventBus();
    }
    return SyncEventBus.instance;
  }

  onSyncRequested(listener: SyncRequestListener): void {
    if (this.syncRequestListeners.indexOf(listener) < 0) {
      this.syncRequestListeners.push(listener);
    }
  }

  offSyncRequested(listener: SyncRequestListener): void {
    const index: number = this.syncRequestListeners.indexOf(listener);
    if (index >= 0) {
      this.syncRequestListeners.splice(index, 1);
    }
  }

  requestSync(): void {
    const listeners: SyncRequestListener[] = this.syncRequestListeners.slice();
    for (let i: number = 0; i < listeners.length; i++) {
      listeners[i]();
    }
  }

  onRemoteDataChanged(listener: RemoteDataListener): void {
    if (this.remoteDataListeners.indexOf(listener) < 0) {
      this.remoteDataListeners.push(listener);
    }
  }

  offRemoteDataChanged(listener: RemoteDataListener): void {
    const index: number = this.remoteDataListeners.indexOf(listener);
    if (index >= 0) {
      this.remoteDataListeners.splice(index, 1);
    }
  }

  emitRemoteDataChanged(): void {
    const listeners: RemoteDataListener[] = this.remoteDataListeners.slice();
    for (let i: number = 0; i < listeners.length; i++) {
      listeners[i]();
    }
  }
}

export default SyncEventBus;
