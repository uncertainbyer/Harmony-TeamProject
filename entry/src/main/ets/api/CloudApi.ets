import { CloudService } from '../service/CloudService';
import { ApiResult } from './PostApi';
import { ErrorCode } from '../common/Constants';

class CloudApi {
  private static instance: CloudApi | null = null;
  private svc: CloudService = new CloudService();

  static getInstance(): CloudApi {
    if (!CloudApi.instance) { CloudApi.instance = new CloudApi(); }
    return CloudApi.instance;
  }

  async uploadPhoto(uri: string, fileName: string): Promise<ApiResult<boolean>> {
    try {
      const ok: boolean = await this.svc.uploadPhoto(uri, fileName);
      let result: ApiResult<boolean> = {
        success: true, data: ok, code: ErrorCode.SUCCESS, message: ''
      };
      return result;
    } catch (e) {
      let result: ApiResult<boolean> = {
        success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message
      };
      return result;
    }
  }

  async getPhotoList(): Promise<ApiResult<string[]>> {
    try {
      const list: string[] = await this.svc.getPhotoList();
      let result: ApiResult<string[]> = {
        success: true, data: list, code: ErrorCode.SUCCESS, message: ''
      };
      return result;
    } catch (e) {
      let result: ApiResult<string[]> = {
        success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message
      };
      return result;
    }
  }
}

export { CloudApi };
export const cloudApi = CloudApi.getInstance();