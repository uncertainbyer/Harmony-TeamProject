import { PostModel } from '../model/PostModel';
import { CommentModel } from '../model/CommentModel';
import { PostService } from './PostService';
import { CommentService } from './CommentService';

/**
 * 同步状态枚举
 */
export enum SyncStatus {
  /** 未同步 */
  UNSYNCED = 0,
  /** 已同步 */
  SYNCED = 1,
  /** 同步中 */
  SYNCING = 2,
  /** 同步失败 */
  FAILED = 3
}

/**
 * 同步结果接口
 */
export interface SyncResult {
  /** 是否成功 */
  success: boolean;

  /** 同步的数据数量 */
  syncCount: number;

  /** 错误信息 */
  errorMsg: string;
}

/**
 * 同步进度接口
 */
export interface SyncProgress {
  /** 当前同步项索引 */
  currentIndex: number;

  /** 总数量 */
  totalCount: number;

  /** 当前同步项ID */
  currentId: string;

  /** 同步类型 */
  syncType: string;
}

/**
 * 分布式同步业务层
 * 负责多设备间的数据同步功能
 * 注：主要功能由成员B实现，此文件提供数据支持接口
 */
interface GeneratedTypeLiteralInterface_1 {
  unsyncedPostCount: number;
  unsyncedCommentCount: number;
}

interface GeneratedTypeLiteralInterface_2 {
  posts: PostModel[];
  comments: CommentModel[];
}

export class DistributedService {
  private postService: PostService = new PostService();
  private commentService: CommentService = new CommentService();

  /**
   * 获取未同步的帖子数据
   * @returns 未同步的帖子列表
   */
  async getUnsyncedPosts(): Promise<PostModel[]> {
    try {
      const posts: PostModel[] = await this.postService.getUnsyncedPosts();
      console.info('[DistributedService] 获取未同步帖子数量:', posts.length);
      return posts;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DistributedService] 获取未同步帖子失败:', errorMsg);
      throw new Error('获取未同步帖子失败: ' + errorMsg);
    }
  }

  /**
   * 获取未同步的评论数据
   * @returns 未同步的评论列表
   */
  async getUnsyncedComments(): Promise<CommentModel[]> {
    try {
      const comments: CommentModel[] = await this.commentService.getUnsyncedComments();
      console.info('[DistributedService] 获取未同步评论数量:', comments.length);
      return comments;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DistributedService] 获取未同步评论失败:', errorMsg);
      throw new Error('获取未同步评论失败: ' + errorMsg);
    }
  }

  /**
   * 标记帖子已同步
   * @param postId 帖子ID
   */
  async markPostSynced(postId: string): Promise<void> {
    try {
      await this.postService.markPostSynced(postId);
      console.info('[DistributedService] 帖子已标记同步:', postId);
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DistributedService] 标记帖子同步失败:', errorMsg);
    }
  }

  /**
   * 标记评论已同步
   * @param commentId 评论ID
   */
  async markCommentSynced(commentId: string): Promise<void> {
    try {
      await this.commentService.markCommentSynced(commentId);
      console.info('[DistributedService] 评论已标记同步:', commentId);
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DistributedService] 标记评论同步失败:', errorMsg);
    }
  }

  /**
   * 批量标记帖子已同步
   * @param postIds 帖子ID列表
   */
  async batchMarkPostsSynced(postIds: string[]): Promise<void> {
    try {
      for (let i: number = 0; i < postIds.length; i++) {
        await this.postService.markPostSynced(postIds[i]);
      }
      console.info('[DistributedService] 批量标记帖子同步完成:', postIds.length);
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DistributedService] 批量标记帖子同步失败:', errorMsg);
    }
  }

  /**
   * 批量标记评论已同步
   * @param commentIds 评论ID列表
   */
  async batchMarkCommentsSynced(commentIds: string[]): Promise<void> {
    try {
      for (let i: number = 0; i < commentIds.length; i++) {
        await this.commentService.markCommentSynced(commentIds[i]);
      }
      console.info('[DistributedService] 批量标记评论同步完成:', commentIds.length);
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DistributedService] 批量标记评论同步失败:', errorMsg);
    }
  }

  /**
   * 获取同步统计信息
   * @returns 统计信息
   */
  async getSyncStatistics(): Promise<GeneratedTypeLiteralInterface_1> {
    try {
      const posts: PostModel[] = await this.postService.getUnsyncedPosts();
      const comments: CommentModel[] = await this.commentService.getUnsyncedComments();

      return {
        unsyncedPostCount: posts.length,
        unsyncedCommentCount: comments.length
      };
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DistributedService] 获取同步统计失败:', errorMsg);
      throw new Error('获取同步统计失败: ' + errorMsg);
    }
  }

  /**
   * 准备同步数据（获取所有待同步数据）
   * @returns 待同步的帖子和评论数据
   */
  async prepareSyncData(): Promise<GeneratedTypeLiteralInterface_2> {
    try {
      const posts: PostModel[] = await this.postService.getUnsyncedPosts();
      const comments: CommentModel[] = await this.commentService.getUnsyncedComments();

      console.info('[DistributedService] 准备同步数据完成，帖子:', posts.length, '评论:', comments.length);

      return {
        posts: posts,
        comments: comments
      };
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DistributedService] 准备同步数据失败:', errorMsg);
      throw new Error('准备同步数据失败: ' + errorMsg);
    }
  }

  /**
   * 完成同步确认（标记所有数据已同步）
   * @param postIds 已同步的帖子ID列表
   * @param commentIds 已同步的评论ID列表
   */
  async confirmSyncComplete(postIds: string[], commentIds: string[]): Promise<SyncResult> {
    try {
      await this.batchMarkPostsSynced(postIds);
      await this.batchMarkCommentsSynced(commentIds);

      const syncCount: number = postIds.length + commentIds.length;
      const result: SyncResult = {
        success: true,
        syncCount: syncCount,
        errorMsg: ''
      };

      console.info('[DistributedService] 同步确认完成，共同步:', syncCount, '条数据');
      return result;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DistributedService] 同步确认失败:', errorMsg);
      const result: SyncResult = {
        success: false,
        syncCount: 0,
        errorMsg: errorMsg
      };
      return result;
    }
  }

  /**
   * 检查是否有待同步数据
   * @returns 是否有待同步数据
   */
  async hasUnsyncedData(): Promise<boolean> {
    try {
      const stats = await this.getSyncStatistics();
      return stats.unsyncedPostCount > 0 || stats.unsyncedCommentCount > 0;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DistributedService] 检查待同步数据失败:', errorMsg);
      return false;
    }
  }
}

export default DistributedService;