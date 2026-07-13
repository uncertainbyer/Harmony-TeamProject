// api/PostApi.ts
import { PostService } from '../service/PostService';
import { PostModel } from '../model/PostModel';
import { AIClassifyResult } from '../service/AIClassifyService';
import { Constants, ErrorCode } from '../common/Constants';

export interface ApiResult<T> {
  success: boolean;
  data: T | null;
  code: number;
  message: string;
}

class PostApi {
  private static instance: PostApi | null = null;
  private svc: PostService = new PostService();

  static getInstance(): PostApi {
    if (!PostApi.instance) {
      PostApi.instance = new PostApi();
    }
    return PostApi.instance;
  }

  // ============ 发布 ============

  async publish(
    userId: string, userName: string, userAvatar: string,
    content: string, imagePaths: string[],
    categoryId: string, categoryName: string, deviceId: string
  ): Promise<ApiResult<PostModel>> {
    try {
      const post = await this.svc.publishPost(userId, userName, userAvatar, content, imagePaths, categoryId, categoryName, deviceId);
      return { success: true, data: post, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async publishWithAI(
    userId: string, userName: string, userAvatar: string,
    content: string, imagePaths: string[], deviceId: string,
    categoryId?: string, categoryName?: string
  ): Promise<ApiResult<PostModel>> {
    try {
      const post = await this.svc.publishPostWithAIClassify(
        userId, userName, userAvatar, content, imagePaths, deviceId,
        categoryId, categoryName
      );
      return { success: true, data: post, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  // ============ 查询 ============

  async getList(page: number, pageSize: number = Constants.PAGE_SIZE): Promise<ApiResult<PostModel[]>> {
    try {
      const list = await this.svc.getPostList(page, pageSize);
      return { success: true, data: list, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async getByCategory(categoryId: string, page: number, pageSize: number = Constants.PAGE_SIZE): Promise<ApiResult<PostModel[]>> {
    try {
      const list = await this.svc.getPostsByCategory(categoryId, page, pageSize);
      return { success: true, data: list, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async getByUser(userId: string, page: number, pageSize: number = Constants.PAGE_SIZE): Promise<ApiResult<PostModel[]>> {
    try {
      const list = await this.svc.getUserPosts(userId, page, pageSize);
      return { success: true, data: list, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async getDetail(postId: string): Promise<ApiResult<PostModel>> {
    try {
      const post = await this.svc.getPostDetail(postId);
      if (post) {
      }
      return post
        ? { success: true, data: post, code: ErrorCode.SUCCESS, message: '' }
        : { success: false, data: null, code: ErrorCode.DATA_NOT_FOUND, message: '帖子不存在' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async getCount(): Promise<number> {
    try { return await this.svc.getPostCount(); } catch { return 0; }
  }

  async getCountByCategory(categoryId: string): Promise<number> {
    try { return await this.svc.getPostCountByCategory(categoryId); } catch { return 0; }
  }

  // ============ 交互 ============

  async like(postId: string): Promise<ApiResult<number>> {
    try {
      const n = await this.svc.likePost(postId);  // ★ 不再传 userId
      return { success: true, data: n, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async unlike(postId: string): Promise<ApiResult<number>> {
    try {
      const n = await this.svc.unlikePost(postId);  // ★ 不再传 userId
      return { success: true, data: n, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async updateContent(postId: string, content: string): Promise<ApiResult<boolean>> {
    try {
      const ok = await this.svc.updatePostContent(postId, content);
      return { success: true, data: ok, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async delete(postId: string): Promise<ApiResult<boolean>> {
    try {
      const ok = await this.svc.deletePost(postId);
      return { success: true, data: ok, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async reclassify(postId: string): Promise<ApiResult<AIClassifyResult | null>> {
    try {
      const r = await this.svc.reclassifyPost(postId);
      return { success: true, data: r, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }
}

export { PostApi };
export const postApi = PostApi.getInstance();