/**
 * DownloadService.ets
 * 下载业务层：支持网络图片下载、保存到相册（含动态权限请求）
 */

import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';

/**
 * 下载进度回调接口
 */
export interface DownloadProgress {
  downloadedSize: number;
  totalSize: number;
  progress: number;
}

/**
 * 下载结果接口
 */
export interface DownloadResult {
  success: boolean;
  localPath: string;
  errorMsg: string;
}

/**
 * 下载业务服务类
 */
export class DownloadService {
  private context: common.UIAbilityContext | null = null;

  /**
   * 初始化上下文（必须在页面/Ability中调用）
   * @param context UIAbilityContext
   */
  init(context: common.UIAbilityContext): void {
    this.context = context;
  }

  // ==================== 权限相关 ====================

  /**
   * 检查并请求相册读写权限（user_grant）
   * 如果已授权则静默返回，否则弹窗请求
   * @throws 如果用户拒绝权限则抛出错误
   */
  private async checkAndRequestPermissions(): Promise<void> {
    if (this.context === null) {
      throw new Error('DownloadService 未初始化，请先调用 init()');
    }

    const permissions: Array<Permissions> = [
      'ohos.permission.READ_IMAGEVIDEO',
      'ohos.permission.WRITE_IMAGEVIDEO'
    ];

    const atManager = abilityAccessCtrl.createAtManager();
    const tokenId = this.context.applicationInfo.accessTokenId;

    // 检查所有权限是否已授予
    let allGranted = true;
    for (const perm of permissions) {
      try {
        const status = await atManager.checkAccessToken(tokenId, perm);
        if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          allGranted = false;
          break;
        }
      } catch {
        allGranted = false;
        break;
      }
    }

    if (allGranted) {
      return; // 已授权，直接返回
    }

    // 发起权限请求（会弹窗）
    const result = await atManager.requestPermissionsFromUser(this.context, permissions);
    const granted = result.authResults.every((res: number) => res === 0);
    if (!granted) {
      throw new Error('用户拒绝了相册读写权限');
    }
  }

  // ==================== 图片下载与保存 ====================

  /**
   * 下载网络图片并保存到相册
   * @param imageUrl 图片URL
   * @param onProgress 进度回调（可选）
   * @returns 下载结果
   */
  async downloadImageToGallery(
    imageUrl: string,
    onProgress?: (progress: DownloadProgress) => void
  ): Promise<DownloadResult> {
    try {
      if (this.context === null) {
        throw new Error('DownloadService 未初始化');
      }

      // 1️⃣ 请求权限（自动弹窗）
      await this.checkAndRequestPermissions();

      // 2️⃣ 下载图片数据
      const imageData: ArrayBuffer = await this.downloadImageData(imageUrl, onProgress);

      // 3️⃣ 保存到相册
      const uri: string = await this.saveToGallery(imageData);

      return {
        success: true,
        localPath: uri,
        errorMsg: ''
      };
    } catch (err) {
      const errorMsg = (err as Error).message;
      console.error('[DownloadService] 下载失败:', errorMsg);
      return {
        success: false,
        localPath: '',
        errorMsg
      };
    }
  }

  /**
   * 下载图片数据（流式）
   */
  private async downloadImageData(
    imageUrl: string,
    onProgress?: (progress: DownloadProgress) => void
  ): Promise<ArrayBuffer> {
    return new Promise<ArrayBuffer>((resolve, reject) => {
      const httpRequest = http.createHttp();
      const chunks: ArrayBuffer[] = [];
      let totalSize = 0;
      let isResolved = false;

      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        chunks.push(data);
        totalSize += data.byteLength;
        if (onProgress) {
          onProgress({
            downloadedSize: totalSize,
            totalSize: totalSize,
            progress: 0 // 服务器未返回总大小，此处仅示意
          });
        }
      });

      httpRequest.on('dataEnd', () => {
        if (isResolved) return;
        isResolved = true;
        const totalBuffer = this.mergeArrayBuffers(chunks, totalSize);
        httpRequest.destroy();
        resolve(totalBuffer);
      });

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 60000,
        readTimeout: 60000
      };

      httpRequest.requestInStream(imageUrl, options)
        .then((code: number) => {
          if (code !== 200) {
            if (!isResolved) {
              isResolved = true;
              httpRequest.destroy();
              reject(new Error(`HTTP错误: ${code}`));
            }
          }
        })
        .catch((err: Error) => {
          if (!isResolved) {
            isResolved = true;
            httpRequest.destroy();
            reject(new Error(`请求失败: ${err.message}`));
          }
        });
    });
  }

  /**
   * 合并ArrayBuffer数组
   */
  private mergeArrayBuffers(buffers: ArrayBuffer[], totalSize: number): ArrayBuffer {
    const result = new ArrayBuffer(totalSize);
    const resultView = new Uint8Array(result);
    let offset = 0;
    for (const buf of buffers) {
      const view = new Uint8Array(buf);
      resultView.set(view, offset);
      offset += view.length;
    }
    return result;
  }

  /**
   * 保存图片到相册（内部方法，调用前需确保权限已授权）
   */
  /**
   * @throws
   */
  private async saveToGallery(imageData: ArrayBuffer): Promise<string> {
    if (this.context === null) {
      throw new Error('上下文未初始化');
    }

    const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
    const uri = await phAccessHelper.createAsset(
      photoAccessHelper.PhotoType.IMAGE,
      'jpg'
    );

    const file = fs.openSync(uri, fs.OpenMode.READ_WRITE);
    fs.writeSync(file.fd, imageData);
    fs.closeSync(file);

    return uri;
  }

  // ==================== 其他工具方法 ====================

  /**
   * 下载图片到应用沙箱（无需相册权限）
   */
  /**
   * @throws
   */
  async downloadToSandbox(
    imageUrl: string,
    fileName: string,
    onProgress?: (progress: DownloadProgress) => void
  ): Promise<string> {
    if (this.context === null) {
      throw new Error('DownloadService 未初始化');
    }

    const imageData = await this.downloadImageData(imageUrl, onProgress);
    const localPath = this.context.filesDir + '/' + fileName;
    const file = fs.openSync(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    fs.writeSync(file.fd, imageData);
    fs.closeSync(file);
    return localPath;
  }

  /**
   * 批量下载图片到相册
   */
  async batchDownloadImages(
    imageUrls: string[],
    onProgress?: (index: number, progress: DownloadProgress) => void,
    onComplete?: (index: number, result: DownloadResult) => void
  ): Promise<string[]> {
    const successUris: string[] = [];
    for (let i = 0; i < imageUrls.length; i++) {
      const url = imageUrls[i];
      const cb = onProgress ? (p: DownloadProgress) => onProgress(i, p) : undefined;
      const result = await this.downloadImageToGallery(url, cb);
      if (onComplete) onComplete(i, result);
      if (result.success) successUris.push(result.localPath);
    }
    console.info(`批量下载完成，成功 ${successUris.length}/${imageUrls.length}`);
    return successUris;
  }

  /**
   * 检查是否为网络图片URL
   */
  isNetworkImage(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /**
   * 从URL提取文件名（添加时间戳防重）
   */
  extractFileName(url: string): string {
    const parts = url.split('/');
    const lastPart = parts[parts.length - 1] || 'image.jpg';
    return `${Date.now()}_${lastPart}`;
  }
}

export default DownloadService;