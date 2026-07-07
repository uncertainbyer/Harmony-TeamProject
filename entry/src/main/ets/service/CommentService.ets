import { CommentModel } from '../model/CommentModel';
import { CommentRepository } from '../repository/CommentRepository';
import { PostService } from './PostService';
import { SyncEventBus } from '../distributed/SyncEventBus';

/**
 * 评论业务层
 * 负责评论相关的业务逻辑处理
 */
export class CommentService {
  private commentRepository: CommentRepository = new CommentRepository();
  private postService: PostService = new PostService();
  private syncEventBus: SyncEventBus = SyncEventBus.getInstance();

  /**
   * 发表一级评论
   * @param postId 帖子ID
   * @param userId 用户ID
   * @param userName 用户昵称
   * @param userAvatar 用户头像
   * @param content 评论内容
   * @param deviceId 设备ID
   * @returns 新评论对象
   */
  async publishComment(
    postId: string,
    userId: string,
    userName: string,
    userAvatar: string,
    content: string,
    deviceId: string
  ): Promise<CommentModel> {
    try {
      const comment: CommentModel = new CommentModel();
      comment.commentId = this.generateUUID();
      comment.postId = postId;
      comment.userId = userId;
      comment.userName = userName;
      comment.userAvatar = userAvatar;
      comment.content = content;
      comment.level = 1;
      comment.parentId = '';
      comment.deviceId = deviceId;
      comment.createTime = Date.now();

      await this.commentRepository.insertComment(comment);
      await this.postService.updatePostCommentCount(postId);
      this.syncEventBus.requestSync();
      console.info('[CommentService] 发表评论成功:', comment.commentId);
      return comment;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 发表评论失败:', errorMsg);
      throw new Error('发表评论失败: ' + errorMsg);
    }
  }

  /**
   * 回复评论
   * @param postId 帖子ID
   * @param parentId 父评论ID
   * @param userId 回复用户ID
   * @param userName 回复用户昵称
   * @param userAvatar 回复用户头像
   * @param content 回复内容
   * @param replyToUserId 被回复用户ID
   * @param replyToUserName 被回复用户昵称
   * @param deviceId 设备ID
   * @returns 新回复对象
   */
  async replyComment(
    postId: string,
    parentId: string,
    userId: string,
    userName: string,
    userAvatar: string,
    content: string,
    replyToUserId: string,
    replyToUserName: string,
    deviceId: string
  ): Promise<CommentModel> {
    try {
      const comment: CommentModel = new CommentModel();
      comment.commentId = this.generateUUID();
      comment.postId = postId;
      comment.userId = userId;
      comment.userName = userName;
      comment.userAvatar = userAvatar;
      comment.content = content;
      comment.level = 2;
      comment.parentId = parentId;
      comment.replyToUserId = replyToUserId;
      comment.replyToUserName = replyToUserName;
      comment.deviceId = deviceId;
      comment.createTime = Date.now();

      await this.commentRepository.insertComment(comment);
      await this.postService.updatePostCommentCount(postId);
      this.syncEventBus.requestSync();
      console.info('[CommentService] 回复评论成功:', comment.commentId);
      return comment;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 回复评论失败:', errorMsg);
      throw new Error('回复评论失败: ' + errorMsg);
    }
  }

  /**
   * 获取帖子的评论列表（一级评论）
   * @param postId 帖子ID
   * @param page 页码
   * @param pageSize 每页数量
   * @returns 评论列表
   */
  async getCommentList(
    postId: string,
    page: number,
    pageSize: number
  ): Promise<CommentModel[]> {
    try {
      const offset: number = (page - 1) * pageSize;
      const comments: CommentModel[] = await this.commentRepository.queryTopLevelComments(
        postId,
        pageSize,
        offset
      );
      return comments;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 获取评论列表失败:', errorMsg);
      throw new Error('获取评论列表失败: ' + errorMsg);
    }
  }

  /**
   * 获取评论的回复列表
   * @param parentId 父评论ID
   * @returns 回复列表
   */
  async getReplyList(parentId: string): Promise<CommentModel[]> {
    try {
      const replies: CommentModel[] = await this.commentRepository.queryReplies(parentId);
      return replies;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 获取回复列表失败:', errorMsg);
      throw new Error('获取回复列表失败: ' + errorMsg);
    }
  }

  /**
   * 获取帖子的所有评论（包含回复）
   * @param postId 帖子ID
   * @returns 所有评论和回复
   */
  async getAllComments(postId: string): Promise<CommentModel[]> {
    try {
      const comments: CommentModel[] = await this.commentRepository.queryAllCommentsByPost(postId);
      return comments;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 获取所有评论失败:', errorMsg);
      throw new Error('获取所有评论失败: ' + errorMsg);
    }
  }

  /**
   * 获取用户的评论历史
   * @param userId 用户ID
   * @param page 页码
   * @param pageSize 每页数量
   * @returns 评论列表
   */
  async getUserComments(
    userId: string,
    page: number,
    pageSize: number
  ): Promise<CommentModel[]> {
    try {
      const offset: number = (page - 1) * pageSize;
      const comments: CommentModel[] = await this.commentRepository.queryCommentsByUser(
        userId,
        pageSize,
        offset
      );
      return comments;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 获取用户评论失败:', errorMsg);
      throw new Error('获取用户评论失败: ' + errorMsg);
    }
  }

  /**
   * 获取评论详情
   * @param commentId 评论ID
   * @returns 评论对象
   */
  async getCommentDetail(commentId: string): Promise<CommentModel | null> {
    try {
      const comment: CommentModel | null = await this.commentRepository.queryCommentById(commentId);
      return comment;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 获取评论详情失败:', errorMsg);
      throw new Error('获取评论详情失败: ' + errorMsg);
    }
  }

  /**
   * 更新评论内容
   * @param commentId 评论ID
   * @param content 新内容
   * @returns 是否成功
   */
  async updateCommentContent(commentId: string, content: string): Promise<boolean> {
    try {
      const comment: CommentModel | null = await this.commentRepository.queryCommentById(commentId);
      if (comment === null) {
        throw new Error('评论不存在');
      }

      comment.content = content;
      const rowCount: number = await this.commentRepository.updateComment(comment);
      if (rowCount > 0) {
        this.syncEventBus.requestSync();
      }
      return rowCount > 0;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 更新评论失败:', errorMsg);
      throw new Error('更新评论失败: ' + errorMsg);
    }
  }

  /**
   * 点赞评论
   * @param commentId 评论ID
   * @returns 新的点赞数
   */
  async likeComment(commentId: string): Promise<number> {
    try {
      const comment: CommentModel | null = await this.commentRepository.queryCommentById(commentId);
      if (comment === null) {
        throw new Error('评论不存在');
      }

      const newLikeCount: number = comment.likeCount + 1;
      await this.commentRepository.updateCommentLikeCount(commentId, newLikeCount);
      this.syncEventBus.requestSync();
      return newLikeCount;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 点赞评论失败:', errorMsg);
      throw new Error('点赞评论失败: ' + errorMsg);
    }
  }

  /**
   * 取消点赞评论
   * @param commentId 评论ID
   * @returns 新的点赞数
   */
  async unlikeComment(commentId: string): Promise<number> {
    try {
      const comment: CommentModel | null = await this.commentRepository.queryCommentById(commentId);
      if (comment === null) {
        throw new Error('评论不存在');
      }

      const newLikeCount: number = Math.max(0, comment.likeCount - 1);
      await this.commentRepository.updateCommentLikeCount(commentId, newLikeCount);
      this.syncEventBus.requestSync();
      return newLikeCount;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 取消点赞失败:', errorMsg);
      throw new Error('取消点赞失败: ' + errorMsg);
    }
  }

  /**
   * 删除评论
   * @param commentId 评论ID
   * @param postId 帖子ID（用于更新帖子评论数）
   * @returns 是否成功
   */
  async deleteComment(commentId: string, postId: string): Promise<boolean> {
    try {
      const rowCount: number = await this.commentRepository.deleteComment(commentId);
      if (rowCount > 0) {
        await this.postService.updatePostCommentCount(postId);
        this.syncEventBus.requestSync();
        console.info('[CommentService] 删除评论成功:', commentId);
      }
      return rowCount > 0;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 删除评论失败:', errorMsg);
      throw new Error('删除评论失败: ' + errorMsg);
    }
  }

  /**
   * 获取帖子的评论数
   * @param postId 帖子ID
   * @returns 评论数量
   */
  async getCommentCount(postId: string): Promise<number> {
    try {
      const count: number = await this.commentRepository.countCommentsByPost(postId);
      return count;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 获取评论数失败:', errorMsg);
      throw new Error('获取评论数失败: ' + errorMsg);
    }
  }

  /**
   * 获取评论的回复数
   * @param parentId 父评论ID
   * @returns 回复数量
   */
  async getReplyCount(parentId: string): Promise<number> {
    try {
      const count: number = await this.commentRepository.countReplies(parentId);
      return count;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 获取回复数失败:', errorMsg);
      throw new Error('获取回复数失败: ' + errorMsg);
    }
  }

  /**
   * 获取未同步的评论（分布式同步用）
   * @returns 未同步的评论列表
   */
  async getUnsyncedComments(): Promise<CommentModel[]> {
    try {
      const comments: CommentModel[] = await this.commentRepository.queryUnsyncedComments();
      return comments;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 获取未同步评论失败:', errorMsg);
      throw new Error('获取未同步评论失败: ' + errorMsg);
    }
  }

  /**
   * 标记评论已同步
   * @param commentId 评论ID
   */
  async markCommentSynced(commentId: string): Promise<void> {
    try {
      await this.commentRepository.updateCommentSyncStatus(commentId, 1);
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentService] 标记同步失败:', errorMsg);
    }
  }

  /**
   * 生成UUID
   * @returns UUID字符串
   */
  private generateUUID(): string {
    const chars: string = '0123456789abcdef';
    let uuid: string = '';

    for (let i: number = 0; i < 36; i++) {
      if (i === 8 || i === 13 || i === 18 || i === 23) {
        uuid += '-';
      } else {
        const randomIndex: number = Math.floor(Math.random() * 16);
        uuid += chars.charAt(randomIndex);
      }
    }

    return uuid;
  }
}

export default CommentService;
