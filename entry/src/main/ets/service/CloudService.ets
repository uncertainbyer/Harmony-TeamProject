import http from '@ohos.net.http';
import { BusinessError } from '@kit.BasicServicesKit';

// 响应结果接口
export interface UploadResult {
  success: boolean;
}

export interface PhotoListResult {
  photos: string[];
}

export class CloudService {
  private static readonly BASE_URL: string = 'http://39.105.115.19:3000/api';
  private httpRequest: http.HttpRequest | null = null;

  // 通用请求封装
  async request<T>(endpoint: string, method: http.RequestMethod, data?: object): Promise<T> {
    if (!this.httpRequest) {
      this.httpRequest = http.createHttp();
    }
    const url: string = `${CloudService.BASE_URL}${endpoint}`;

    let extraHeader: Record<string, string> = {
      'Content-Type': 'application/json'
    };

    const options: http.HttpRequestOptions = {
      method: method,
      header: extraHeader,
      connectTimeout: 30000,
      readTimeout: 60000,
    };

    if (data) {
      options.extraData = JSON.stringify(data);
    }

    try {
      const response: http.HttpResponse = await this.httpRequest.request(url, options);
      return JSON.parse(response.result as string) as T;
    } catch (e) {
      console.error('请求失败:', (e as BusinessError).message);
      // ✅ 修复：将任意类型转换为 Error 再抛出
      throw new Error((e as BusinessError).message ?? '网络请求失败');
    }
  }

  // 上传照片
  async uploadPhoto(uri: string, fileName: string): Promise<boolean> {
    let body: Record<string, string> = {
      'uri': uri,
      'fileName': fileName
    };
    const result: UploadResult = await this.request<UploadResult>(
      '/photos/upload',
      http.RequestMethod.POST,
      body
    );
    return result.success;
  }

  // 获取照片列表
  async getPhotoList(): Promise<string[]> {
    const result: PhotoListResult = await this.request<PhotoListResult>(
      '/photos/list',
      http.RequestMethod.GET
    );
    return result.photos;
  }

  // 销毁资源
  destroy(): void {
    if (this.httpRequest) {
      this.httpRequest.destroy();
      this.httpRequest = null;
    }
  }
}