import { DownloadService, DownloadResult, DownloadProgress } from '../service/DownloadService';
import { common } from '@kit.AbilityKit';
import { ApiResult } from './PostApi';
import { ErrorCode } from '../common/Constants';

class DownloadApi {
  private static instance: DownloadApi | null = null;
  private svc: DownloadService = new DownloadService();

  static getInstance(): DownloadApi {
    if (!DownloadApi.instance) { DownloadApi.instance = new DownloadApi(); }
    return DownloadApi.instance;
  }

  init(ctx: common.UIAbilityContext): void { this.svc.init(ctx); }

  async toGallery(url: string, cb?: (p: DownloadProgress) => void): Promise<ApiResult<DownloadResult>> {
    try {
      const r = await this.svc.downloadImageToGallery(url, cb);
      return { success: r.success, data: r, code: r.success ? ErrorCode.SUCCESS : ErrorCode.FILE_ERROR, message: r.errorMsg };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async toSandbox(url: string, fileName: string, cb?: (p: DownloadProgress) => void): Promise<ApiResult<string>> {
    try {
      const path = await this.svc.downloadToSandbox(url, fileName, cb);
      return { success: true, data: path, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async batch(
    urls: string[],
    onProgress?: (i: number, p: DownloadProgress) => void,
    onComplete?: (i: number, r: DownloadResult) => void
  ): Promise<string[]> {
    return await this.svc.batchDownloadImages(urls, onProgress, onComplete);
  }

  isNetwork(url: string): boolean { return this.svc.isNetworkImage(url); }
  extractName(url: string): string { return this.svc.extractFileName(url); }
}

export { DownloadApi, DownloadResult, DownloadProgress };
export const downloadApi = DownloadApi.getInstance();