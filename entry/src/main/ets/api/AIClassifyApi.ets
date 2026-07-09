import { AIClassifyService, AIClassifyResult } from '../service/AIClassifyService';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { ApiResult } from './PostApi';
import { ErrorCode } from '../common/Constants';

class AIClassifyApi {
  private static instance: AIClassifyApi | null = null;
  private ai = AIClassifyService.getInstance();

  static getInstance(): AIClassifyApi {
    if (!AIClassifyApi.instance) { AIClassifyApi.instance = new AIClassifyApi(); }
    return AIClassifyApi.instance;
  }

  async preload(ctx: common.UIAbilityContext | null): Promise<void> {
    if (ctx) { await this.ai.preloadModel(ctx); }
  }

  isReady(): boolean { return this.ai.isReady(); }

  async classify(pixelMap: image.PixelMap): Promise<ApiResult<AIClassifyResult>> {
    try {
      const r = await this.ai.classifyImage(pixelMap);
      return { success: r.success, data: r, code: r.success ? ErrorCode.SUCCESS : ErrorCode.SERVER_ERROR, message: r.errorMsg };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async classifyUri(uri: string): Promise<ApiResult<AIClassifyResult>> {
    try {
      const r = await this.ai.classifyImageFromUri(uri);
      return { success: r.success, data: r, code: r.success ? ErrorCode.SUCCESS : ErrorCode.SERVER_ERROR, message: r.errorMsg };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }
}

export { AIClassifyApi };
export const aiClassifyApi = AIClassifyApi.getInstance();