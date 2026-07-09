import { CommentService } from '../service/CommentService';
import { CommentModel } from '../model/CommentModel';
import { ErrorCode } from '../common/Constants';
import { ApiResult } from './PostApi';

class CommentApi {
  private static instance: CommentApi | null = null;
  private svc: CommentService = new CommentService();

  static getInstance(): CommentApi {
    if (!CommentApi.instance) { CommentApi.instance = new CommentApi(); }
    return CommentApi.instance;
  }

  // ============ 发表 ============

  async publish(
    postId: string, userId: string, userName: string,
    userAvatar: string, content: string, deviceId: string
  ): Promise<ApiResult<CommentModel>> {
    try {
      const c = await this.svc.publishComment(postId, userId, userName, userAvatar, content, deviceId);
      return { success: true, data: c, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async reply(
    postId: string, parentId: string, userId: string, userName: string,
    userAvatar: string, content: string,
    replyToUserId: string, replyToUserName: string, deviceId: string
  ): Promise<ApiResult<CommentModel>> {
    try {
      const c = await this.svc.replyComment(postId, parentId, userId, userName, userAvatar, content, replyToUserId, replyToUserName, deviceId);
      return { success: true, data: c, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  // ============ 查询 ============

  async getList(postId: string, page: number, pageSize: number): Promise<ApiResult<CommentModel[]>> {
    try {
      const list = await this.svc.getCommentList(postId, page, pageSize);
      return { success: true, data: list, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async getReplies(parentId: string): Promise<ApiResult<CommentModel[]>> {
    try {
      const list = await this.svc.getReplyList(parentId);
      return { success: true, data: list, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async getAllByPost(postId: string): Promise<ApiResult<CommentModel[]>> {
    try {
      const list = await this.svc.getAllComments(postId);
      return { success: true, data: list, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async getByUser(userId: string, page: number, pageSize: number): Promise<ApiResult<CommentModel[]>> {
    try {
      const list = await this.svc.getUserComments(userId, page, pageSize);
      return { success: true, data: list, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async getDetail(commentId: string): Promise<ApiResult<CommentModel | null>> {
    try {
      const c = await this.svc.getCommentDetail(commentId);
      return { success: true, data: c, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  // ============ 交互 ============

  async like(commentId: string): Promise<ApiResult<number>> {
    try {
      const n = await this.svc.likeComment(commentId);
      return { success: true, data: n, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async unlike(commentId: string): Promise<ApiResult<number>> {
    try {
      const n = await this.svc.unlikeComment(commentId);
      return { success: true, data: n, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async updateContent(commentId: string, content: string): Promise<ApiResult<boolean>> {
    try {
      const ok = await this.svc.updateCommentContent(commentId, content);
      return { success: true, data: ok, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async delete(commentId: string, postId: string): Promise<ApiResult<boolean>> {
    try {
      const ok = await this.svc.deleteComment(commentId, postId);
      return { success: true, data: ok, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  async getCount(postId: string): Promise<number> {
    try { return await this.svc.getCommentCount(postId); } catch { return 0; }
  }

  async getReplyCount(parentId: string): Promise<number> {
    try { return await this.svc.getReplyCount(parentId); } catch { return 0; }
  }
}

export { CommentApi };
export const commentApi = CommentApi.getInstance();