import { PostModel } from '../model/PostModel';
import { CategoryModel } from '../model/CategoryModel';
import { PostRepository } from '../repository/PostRepository';
import { CommentRepository } from '../repository/CommentRepository';
import { SyncEventBus } from '../distributed/SyncEventBus';
import { AIClassifyService, AIClassifyResult } from './AIClassifyService';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';

/**
 * 帖子业务层
 * 负责帖子相关的业务逻辑处理
 */
export class PostService {
  private postRepository: PostRepository = new PostRepository();
  private commentRepository: CommentRepository = new CommentRepository();
  private syncEventBus: SyncEventBus = SyncEventBus.getInstance();

  /**
   * 发布新帖子
   * @param userId 用户ID
   * @param userName 用户昵称
   * @param userAvatar 用户头像
   * @param content 文字内容
   * @param imagePaths 图片路径数组
   * @param categoryId 分类ID
   * @param categoryName 分类名称
   * @param deviceId 设备ID
   * @returns 新帖子对象
   */
  async publishPost(
    userId: string,
    userName: string,
    userAvatar: string,
    content: string,
    imagePaths: string[],
    categoryId: string,
    categoryName: string,
    deviceId: string
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

      await this.postRepository.insertPost(post);
      this.syncEventBus.requestSync();
      console.info('[PostService] 发布帖子成功:', post.postId);
      return post;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 发布帖子失败:', errorMsg);
      throw new Error('发布帖子失败: ' + errorMsg);
    }
  }

  /**
   * 获取帖子详情
   * @param postId 帖子ID
   * @returns 帖子对象
   */
  async getPostDetail(postId: string): Promise<PostModel | null> {
    try {
      const post: PostModel | null = await this.postRepository.queryPostById(postId);
      return post;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 获取帖子详情失败:', errorMsg);
      throw new Error('获取帖子详情失败: ' + errorMsg);
    }
  }

  /**
   * 获取帖子列表（分页）
   * @param page 页码（从1开始）
   * @param pageSize 每页数量
   * @returns 帖子列表
   */
  async getPostList(page: number, pageSize: number): Promise<PostModel[]> {
    try {
      const offset: number = (page - 1) * pageSize;
      const posts: PostModel[] = await this.postRepository.queryAllPosts(pageSize, offset);
      return posts;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 获取帖子列表失败:', errorMsg);
      throw new Error('获取帖子列表失败: ' + errorMsg);
    }
  }

  /**
   * 根据分类获取帖子
   * @param categoryId 分类ID
   * @param page 页码
   * @param pageSize 每页数量
   * @returns 帖子列表
   */
  async getPostsByCategory(
    categoryId: string,
    page: number,
    pageSize: number
  ): Promise<PostModel[]> {
    try {
      const offset: number = (page - 1) * pageSize;
      const posts: PostModel[] = await this.postRepository.queryPostsByCategory(
        categoryId,
        pageSize,
        offset
      );
      return posts;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 获取分类帖子失败:', errorMsg);
      throw new Error('获取分类帖子失败: ' + errorMsg);
    }
  }

  /**
   * 获取用户发布的帖子
   * @param userId 用户ID
   * @param page 页码
   * @param pageSize 每页数量
   * @returns 帖子列表
   */
  async getUserPosts(userId: string, page: number, pageSize: number): Promise<PostModel[]> {
    try {
      const offset: number = (page - 1) * pageSize;
      const posts: PostModel[] = await this.postRepository.queryPostsByUser(userId, pageSize, offset);
      return posts;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 获取用户帖子失败:', errorMsg);
      throw new Error('获取用户帖子失败: ' + errorMsg);
    }
  }

  /**
   * 更新帖子内容
   * @param postId 帖子ID
   * @param content 新内容
   * @returns 是否成功
   */
  async updatePostContent(postId: string, content: string): Promise<boolean> {
    try {
      const post: PostModel | null = await this.postRepository.queryPostById(postId);
      if (post === null) {
        throw new Error('帖子不存在');
      }

      post.content = content;
      const rowCount: number = await this.postRepository.updatePost(post);
      if (rowCount > 0) {
        this.syncEventBus.requestSync();
      }
      return rowCount > 0;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 更新帖子内容失败:', errorMsg);
      throw new Error('更新帖子内容失败: ' + errorMsg);
    }
  }

  /**
   * 更新帖子分类（AI分类后调用）
   * @param postId 帖子ID
   * @param categoryId 分类ID
   * @param categoryName 分类名称
   * @returns 是否成功
   */
  async updatePostCategory(
    postId: string,
    categoryId: string,
    categoryName: string
  ): Promise<boolean> {
    try {
      const rowCount: number = await this.postRepository.updatePostCategory(
        postId,
        categoryId,
        categoryName
      );
      if (rowCount > 0) {
        this.syncEventBus.requestSync();
      }
      return rowCount > 0;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 更新帖子分类失败:', errorMsg);
      throw new Error('更新帖子分类失败: ' + errorMsg);
    }
  }

  /**
   * 点赞帖子
   * @param postId 帖子ID
   * @returns 新的点赞数
   */
  async likePost(postId: string): Promise<number> {
    try {
      const post: PostModel | null = await this.postRepository.queryPostById(postId);
      if (post === null) {
        throw new Error('帖子不存在');
      }

      const newLikeCount: number = post.likeCount + 1;
      await this.postRepository.updatePostLikeCount(postId, newLikeCount);
      this.syncEventBus.requestSync();
      return newLikeCount;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 点赞失败:', errorMsg);
      throw new Error('点赞失败: ' + errorMsg);
    }
  }

  /**
   * 取消点赞
   * @param postId 帖子ID
   * @returns 新的点赞数
   */
  async unlikePost(postId: string): Promise<number> {
    try {
      const post: PostModel | null = await this.postRepository.queryPostById(postId);
      if (post === null) {
        throw new Error('帖子不存在');
      }

      const newLikeCount: number = Math.max(0, post.likeCount - 1);
      await this.postRepository.updatePostLikeCount(postId, newLikeCount);
      this.syncEventBus.requestSync();
      return newLikeCount;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 取消点赞失败:', errorMsg);
      throw new Error('取消点赞失败: ' + errorMsg);
    }
  }

  /**
   * 删除帖子
   * @param postId 帖子ID
   * @returns 是否成功
   */
  async deletePost(postId: string): Promise<boolean> {
    try {
      const rowCount: number = await this.postRepository.deletePost(postId);
      if (rowCount > 0) {
        this.syncEventBus.requestSync();
      }
      console.info('[PostService] 删除帖子成功:', postId);
      return rowCount > 0;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 删除帖子失败:', errorMsg);
      throw new Error('删除帖子失败: ' + errorMsg);
    }
  }

  /**
   * 获取帖子总数
   * @returns 帖子总数
   */
  async getPostCount(): Promise<number> {
    try {
      const count: number = await this.postRepository.countPosts();
      return count;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 获取帖子总数失败:', errorMsg);
      throw new Error('获取帖子总数失败: ' + errorMsg);
    }
  }

  /**
   * 获取某分类的帖子数
   * @param categoryId 分类ID
   * @returns 帖子数量
   */
  async getPostCountByCategory(categoryId: string): Promise<number> {
    try {
      const count: number = await this.postRepository.countPostsByCategory(categoryId);
      return count;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 获取分类帖子数失败:', errorMsg);
      throw new Error('获取分类帖子数失败: ' + errorMsg);
    }
  }

  /**
   * 更新帖子评论数（内部调用）
   * @param postId 帖子ID
   */
  async updatePostCommentCount(postId: string): Promise<void> {
    try {
      const count: number = await this.commentRepository.countCommentsByPost(postId);
      await this.postRepository.updatePostCommentCount(postId, count);
      this.syncEventBus.requestSync();
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 更新评论数失败:', errorMsg);
    }
  }

  /**
   * 获取未同步的帖子（分布式同步用）
   * @returns 未同步的帖子列表
   */
  async getUnsyncedPosts(): Promise<PostModel[]> {
    try {
      const posts: PostModel[] = await this.postRepository.queryUnsyncedPosts();
      return posts;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 获取未同步帖子失败:', errorMsg);
      throw new Error('获取未同步帖子失败: ' + errorMsg);
    }
  }

  /**
   * 标记帖子已同步
   * @param postId 帖子ID
   */
  async markPostSynced(postId: string): Promise<void> {
    try {
      await this.postRepository.updatePostSyncStatus(postId, 1);
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 标记同步失败:', errorMsg);
    }
  }

  /**
   * 发布带 AI 自动分类的帖子
   *
   * 先发布帖子，然后对第一张图片进行 AI 识别，自动更新分类。
   * 若 AI 推理失败，帖子保持默认分类（"其他"）。
   *
   * @param userId 用户ID
   * @param userName 用户昵称
   * @param userAvatar 用户头像
   * @param content 文字内容
   * @param imagePaths 图片路径数组
   * @param deviceId 设备ID
   * @returns 新帖子对象（含 AI 分类结果）
   */
  async publishPostWithAIClassify(
    userId: string,
    userName: string,
    userAvatar: string,
    content: string,
    imagePaths: string[],
    deviceId: string
  ): Promise<PostModel> {
    // 先以默认分类发布
    const post: PostModel = await this.publishPost(
      userId,
      userName,
      userAvatar,
      content,
      imagePaths,
      'cat_other',
      '其他',
      deviceId
    );

    // 如果有图片，运行 AI 分类
    if (imagePaths.length > 0) {
      try {
        const classifyResult: AIClassifyResult =
          await AIClassifyService.getInstance().classifyImageFromUri(imagePaths[0]);

        if (classifyResult.success) {
          await this.updatePostCategory(
            post.postId,
            classifyResult.categoryId,
            classifyResult.categoryName
          );
          post.categoryId = classifyResult.categoryId;
          post.categoryName = classifyResult.categoryName;
          console.info('[PostService] AI 分类完成: ' +
            classifyResult.categoryName + ' (' + classifyResult.confidence + '%)');
        } else {
          console.warn('[PostService] AI 分类失败，使用默认分类: ' + classifyResult.errorMsg);
        }
      } catch (err) {
        const errorMsg: string = (err as Error).message;
        console.warn('[PostService] AI 分类异常，使用默认分类: ' + errorMsg);
      }
    }

    return post;
  }

  /**
   * 对已有帖子重新进行 AI 分类
   *
   * @param postId 帖子ID
   * @returns 分类结果，若帖子不存在或无图片则返回 null
   */
  async reclassifyPost(postId: string): Promise<AIClassifyResult | null> {
    try {
      const post: PostModel | null = await this.postRepository.queryPostById(postId);
      if (post === null) {
        console.error('[PostService] 帖子不存在: ' + postId);
        return null;
      }

      const images: string[] = post.getImagePathArray();
      if (images.length === 0) {
        console.warn('[PostService] 帖子无图片，无法分类: ' + postId);
        return null;
      }

      const classifyResult: AIClassifyResult =
        await AIClassifyService.getInstance().classifyImageFromUri(images[0]);

      if (classifyResult.success) {
        await this.updatePostCategory(
          postId,
          classifyResult.categoryId,
          classifyResult.categoryName
        );
        console.info('[PostService] 重新分类完成: ' +
          classifyResult.categoryName + ' (' + classifyResult.confidence + '%)');
      }

      return classifyResult;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[PostService] 重新分类失败: ' + errorMsg);
      return null;
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

export default PostService;
