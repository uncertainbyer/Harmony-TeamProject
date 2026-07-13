// service/PostService.ts
import { PostModel } from '../model/PostModel';
import { PostRepository } from '../repository/PostRepository';
import { CommentRepository } from '../repository/CommentRepository';
import { SyncEventBus } from '../distributed/SyncEventBus';
import { AIClassifyService, AIClassifyResult } from './AIClassifyService';

/**
 * 帖子业务层 —— 本地数据库 + 点赞同步
 */
export class PostService {
  private postRepository: PostRepository = new PostRepository();
  private commentRepository: CommentRepository = new CommentRepository();
  private syncEventBus: SyncEventBus = SyncEventBus.getInstance();

  async publishPost(
    userId: string, userName: string, userAvatar: string,
    content: string, imagePaths: string[],
    categoryId: string, categoryName: string, deviceId: string
  ): Promise<PostModel> {
    try {
      const post: PostModel = new PostModel();
      post.postId = this.generateUUID();
      post.userId = userId;
      post.userName = userName;
      post.userAvatar = userAvatar;
      post.content = content;
      post.setImagePathArray(imagePaths);
      post.categoryId = categoryId;
      post.categoryName = categoryName;
      post.deviceId = deviceId;
      post.createTime = Date.now();
      post.updateTime = Date.now();

      console.info('[PostService] 准备发布帖子:');
      console.info('[PostService]   postId: ' + post.postId);
      console.info('[PostService]   userId: ' + post.userId);
      console.info('[PostService]   imagePaths: ' + post.imagePaths);
      console.info('[PostService]   imageCount: ' + post.imageCount);
      console.info('[PostService]   likeCount: ' + post.likeCount);
      console.info('[PostService]   commentCount: ' + post.commentCount);

      await this.postRepository.insertPost(post);
      this.syncEventBus.requestSync();
      console.info('[PostService] 发布帖子成功:', post.postId);
      return post;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 发布帖子失败:', errorMsg);
      console.error('[PostService] 错误详情:', JSON.stringify(err));
      throw new Error('发布帖子失败: ' + errorMsg);
    }
  }

  async getPostDetail(postId: string): Promise<PostModel | null> {
    return await this.postRepository.queryPostById(postId);
  }

  async getPostList(page: number, pageSize: number): Promise<PostModel[]> {
    const offset: number = (page - 1) * pageSize;
    return await this.postRepository.queryAllPosts(pageSize, offset);
  }

  async getPostsByCategory(categoryId: string, page: number, pageSize: number): Promise<PostModel[]> {
    const offset: number = (page - 1) * pageSize;
    return await this.postRepository.queryPostsByCategory(categoryId, pageSize, offset);
  }

  async getUserPosts(userId: string, page: number, pageSize: number): Promise<PostModel[]> {
    const offset: number = (page - 1) * pageSize;
    return await this.postRepository.queryPostsByUser(userId, pageSize, offset);
  }

  async updatePostContent(postId: string, content: string): Promise<boolean> {
    const post: PostModel | null = await this.postRepository.queryPostById(postId);
    if (post === null) throw new Error('帖子不存在');
    post.content = content;
    const rowCount: number = await this.postRepository.updatePost(post);
    if (rowCount > 0) this.syncEventBus.requestSync();
    return rowCount > 0;
  }

  async updatePostCategory(postId: string, categoryId: string, categoryName: string): Promise<boolean> {
    const rowCount: number = await this.postRepository.updatePostCategory(postId, categoryId, categoryName);
    if (rowCount > 0) this.syncEventBus.requestSync();
    return rowCount > 0;
  }

  // service/PostService.ts — 只替换 likePost 和 unlikePost

  async likePost(postId: string): Promise<number> {
    const post: PostModel | null = await this.postRepository.queryPostById(postId);
    if (post === null) throw new Error('帖子不存在');

    const newLikeCount: number = post.likeCount + 1;
    await this.postRepository.updatePostLikeCount(postId, newLikeCount);
    this.syncEventBus.requestSync();
    return newLikeCount;
  }

  async unlikePost(postId: string): Promise<number> {
    const post: PostModel | null = await this.postRepository.queryPostById(postId);
    if (post === null) throw new Error('帖子不存在');

    const newLikeCount: number = Math.max(0, post.likeCount - 1);
    await this.postRepository.updatePostLikeCount(postId, newLikeCount);
    this.syncEventBus.requestSync();
    return newLikeCount;
  }

  async deletePost(postId: string): Promise<boolean> {
      const rowCount: number = await this.postRepository.deletePost(postId, false);
    if (rowCount > 0) this.syncEventBus.requestSync();
    return rowCount > 0;
  }

  async getPostCount(): Promise<number> {
    return await this.postRepository.countPosts();
  }

  async getPostCountByCategory(categoryId: string): Promise<number> {
    return await this.postRepository.countPostsByCategory(categoryId);
  }

  async updatePostCommentCount(postId: string): Promise<void> {
    const count: number = await this.commentRepository.countCommentsByPost(postId);
    await this.postRepository.updatePostCommentCount(postId, count);
    this.syncEventBus.requestSync();
  }

  async getUnsyncedPosts(): Promise<PostModel[]> {
    return await this.postRepository.queryUnsyncedPosts();
  }

  async markPostSynced(postId: string): Promise<void> {
    await this.postRepository.updatePostSyncStatus(postId, 1);
  }

  async publishPostWithAIClassify(
    userId: string, userName: string, userAvatar: string,
    content: string, imagePaths: string[], deviceId: string,
    categoryId?: string, categoryName?: string
  ): Promise<PostModel> {
    const finalCategoryId: string = categoryId || 'cat_other';
    const finalCategoryName: string = categoryName || '其他';

    const post: PostModel = await this.publishPost(
      userId, userName, userAvatar, content, imagePaths,
      finalCategoryId, finalCategoryName, deviceId
    );

    if (imagePaths.length > 0 && categoryId === undefined) {
      try {
        const classifyResult: AIClassifyResult =
          await AIClassifyService.getInstance().classifyImageFromUri(imagePaths[0]);
        if (classifyResult.success) {
          await this.updatePostCategory(post.postId, classifyResult.categoryId, classifyResult.categoryName);
          post.categoryId = classifyResult.categoryId;
          post.categoryName = classifyResult.categoryName;
        }
      } catch (err) {
        console.warn('[PostService] AI 分类异常:', (err as Error).message);
      }
    }
    return post;
  }

  async reclassifyPost(postId: string): Promise<AIClassifyResult | null> {
    const post: PostModel | null = await this.postRepository.queryPostById(postId);
    if (post === null) return null;

    const images: string[] = post.getImagePathArray();
    if (images.length === 0) return null;

    const classifyResult: AIClassifyResult =
      await AIClassifyService.getInstance().classifyImageFromUri(images[0]);

    if (classifyResult.success) {
      await this.updatePostCategory(postId, classifyResult.categoryId, classifyResult.categoryName);
    }
    return classifyResult;
  }

  private generateUUID(): string {
    const chars: string = '0123456789abcdef';
    let uuid: string = '';
    for (let i: number = 0; i < 36; i++) {
      if (i === 8 || i === 13 || i === 18 || i === 23) uuid += '-';
      else uuid += chars.charAt(Math.floor(Math.random() * 16));
    }
    return uuid;
  }
}

export default PostService;