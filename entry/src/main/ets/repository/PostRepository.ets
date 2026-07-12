import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { PostModel } from '../model/PostModel';

/**
 * 帖子数据访问层
 * 负责帖子数据的增删改查操作
 */
export class PostRepository {
  private rdbManager: RdbManager = RdbManager.getInstance();

  /**
   * 插入新帖子
   * @param post 帖子对象
   * @returns 插入的行ID
   */
  async insertPost(post: PostModel): Promise<number> {
    console.info("===== Post =====");
    console.info(JSON.stringify(post));

    console.info("imagePaths = " + post.imagePaths);
    console.info("typeof imagePaths = " + typeof post.imagePaths);

    const bucket = post.toValuesBucket();
    console.info(JSON.stringify(bucket));
    console.info("typeof bucket.image_paths = " + typeof bucket["image_paths"]);

    const rowId = await this.rdbManager.insert(
      PostModel.getTableName(),
      bucket
    );

    return rowId;
  }

  /**
   * 批量插入帖子
   * @param posts 帖子列表
   */
  async batchInsertPosts(posts: PostModel[]): Promise<void> {
    const valuesList: relationalStore.ValuesBucket[] = [];
    for (let i: number = 0; i < posts.length; i++) {
      valuesList.push(posts[i].toValuesBucket());
    }
    await this.rdbManager.batchInsert(PostModel.getTableName(), valuesList);
  }

  /**
   * 根据ID查询帖子
   * @param postId 帖子ID
   * @returns 帖子对象，不存在则返回null
   */
  /**
   * @throws
   */
  async queryPostById(postId: string): Promise<PostModel | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('post_id', postId);
    predicates.equalTo('is_deleted', 0);

    const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
    const post: PostModel | null = this.parseResultSetToPost(resultSet);
    resultSet.close();
    return post;
  }

  /** 查询帖子（包含软删除数据，供分布式冲突处理使用）。 */
  async queryPostByIdIncludingDeleted(postId: string): Promise<PostModel | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('post_id', postId);
    const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
    const post: PostModel | null = this.parseResultSetToPost(resultSet);
    resultSet.close();
    return post;
  }

  /**
   * 合并远端帖子。相同ID采用更新时间较新的版本，未同步的本地新版本不会被旧数据覆盖。
   */
  async upsertRemotePost(post: PostModel): Promise<boolean> {
    const local: PostModel | null = await this.queryPostByIdIncludingDeleted(post.postId);
    post.syncStatus = 1;
    if (local === null) {
      await this.insertPost(post);
      return true;
    }
    if (local.updateTime > post.updateTime) {
      return false;
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('post_id', post.postId);
    await this.rdbManager.update(PostModel.getTableName(), post.toValuesBucket(), predicates);
    return true;
  }

  /**
   * 查询所有帖子（按时间倒序）
   * @param limit 限制数量
   * @param offset 偏移量
   * @returns 帖子列表
   */
  /**
   * @throws
   */
  async queryAllPosts(limit?: number, offset?: number): Promise<PostModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('is_deleted', 0);
    predicates.orderByDesc('create_time');

    if (limit !== undefined && offset !== undefined) {
      predicates.limitAs(limit);
      predicates.offsetAs(offset);
    } else if (limit !== undefined) {
      predicates.limitAs(limit);
    }

    const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
    const posts: PostModel[] = this.parseResultSetToPosts(resultSet);
    resultSet.close();
    return posts;
  }

  /**
   * 根据分类ID查询帖子
   * @param categoryId 分类ID
   * @param limit 限制数量
   * @param offset 偏移量
   * @returns 帖子列表
   */
  /**
   * @throws
   */
  async queryPostsByCategory(
    categoryId: string,
    limit?: number,
    offset?: number
  ): Promise<PostModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('category_id', categoryId);
    predicates.equalTo('is_deleted', 0);
    predicates.orderByDesc('create_time');

    if (limit !== undefined && offset !== undefined) {
      predicates.limitAs(limit);
      predicates.offsetAs(offset);
    } else if (limit !== undefined) {
      predicates.limitAs(limit);
    }

    const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
    const posts: PostModel[] = this.parseResultSetToPosts(resultSet);
    resultSet.close();
    return posts;
  }

  /**
   * 根据用户ID查询帖子
   * @param userId 用户ID
   * @param limit 限制数量
   * @param offset 偏移量
   * @returns 帖子列表
   */
  /**
   * @throws
   */
  async queryPostsByUser(userId: string, limit?: number, offset?: number): Promise<PostModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('user_id', userId);
    predicates.equalTo('is_deleted', 0);
    predicates.orderByDesc('create_time');

    if (limit !== undefined && offset !== undefined) {
      predicates.limitAs(limit);
      predicates.offsetAs(offset);
    } else if (limit !== undefined) {
      predicates.limitAs(limit);
    }

    const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
    const posts: PostModel[] = this.parseResultSetToPosts(resultSet);
    resultSet.close();
    return posts;
  }

  /**
   * 更新帖子
   * @param post 帖子对象
   * @returns 更新的行数
   */
  async updatePost(post: PostModel): Promise<number> {
    post.updateTime = Date.now();
    post.syncStatus = 0;
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('post_id', post.postId);

    const rowCount: number = await this.rdbManager.update(
      PostModel.getTableName(),
      post.toValuesBucket(),
      predicates
    );
    return rowCount;
  }

  /**
   * 更新帖子点赞数
   * @param postId 帖子ID
   * @param likeCount 新的点赞数
   * @returns 更新的行数
   */
  async updatePostLikeCount(postId: string, likeCount: number): Promise<number> {
    const values: relationalStore.ValuesBucket = {};
    values['like_count'] = likeCount;
    values['update_time'] = Date.now();
    values['sync_status'] = 0;

    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('post_id', postId);

    const rowCount: number = await this.rdbManager.update(
      PostModel.getTableName(),
      values,
      predicates
    );
    return rowCount;
  }

  /**
   * 更新帖子评论数
   * @param postId 帖子ID
   * @param commentCount 新的评论数
   * @returns 更新的行数
   */
  async updatePostCommentCount(postId: string, commentCount: number): Promise<number> {
    const values: relationalStore.ValuesBucket = {};
    values['comment_count'] = commentCount;
    values['update_time'] = Date.now();
    values['sync_status'] = 0;

    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('post_id', postId);

    const rowCount: number = await this.rdbManager.update(
      PostModel.getTableName(),
      values,
      predicates
    );
    return rowCount;
  }

  /**
   * 更新帖子分类
   * @param postId 帖子ID
   * @param categoryId 分类ID
   * @param categoryName 分类名称
   * @returns 更新的行数
   */
  async updatePostCategory(
    postId: string,
    categoryId: string,
    categoryName: string
  ): Promise<number> {
    const values: relationalStore.ValuesBucket = {};
    values['category_id'] = categoryId;
    values['category_name'] = categoryName;
    values['update_time'] = Date.now();
    values['sync_status'] = 0;

    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('post_id', postId);

    const rowCount: number = await this.rdbManager.update(
      PostModel.getTableName(),
      values,
      predicates
    );
    return rowCount;
  }

  /**
   * 软删除帖子
   * @param postId 帖子ID
   * @returns 删除的行数
   */
  async deletePost(postId: string): Promise<number> {
    const values: relationalStore.ValuesBucket = {};
    values['is_deleted'] = 1;
    values['update_time'] = Date.now();
    values['sync_status'] = 0;

    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('post_id', postId);

    const rowCount: number = await this.rdbManager.update(
      PostModel.getTableName(),
      values,
      predicates
    );
    return rowCount;
  }

  /**
   * 查询未同步的帖子
   * @returns 未同步的帖子列表
   */
  /**
   * @throws
   */
  async queryUnsyncedPosts(): Promise<PostModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('sync_status', 0);
    predicates.equalTo('is_deleted', 0);

    const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
    const posts: PostModel[] = this.parseResultSetToPosts(resultSet);
    resultSet.close();
    return posts;
  }

  async updateUserPostsUserName(userId: string, newName: string): Promise<number> {
    const values: relationalStore.ValuesBucket = {};
    values['user_name'] = newName;
    values['sync_status'] = 0;
    values['update_time'] = Date.now();

    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('user_id', userId);

    const rowCount: number = await this.rdbManager.update(
      PostModel.getTableName(),
      values,
      predicates
    );
    return rowCount;
  }

  /**
   * 更新帖子同步状态
   * @param postId 帖子ID
   * @param syncStatus 同步状态
   * @returns 更新的行数
   */
  async updatePostSyncStatus(postId: string, syncStatus: number): Promise<number> {
    const values: relationalStore.ValuesBucket = {};
    values['sync_status'] = syncStatus;
    values['update_time'] = Date.now();

    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('post_id', postId);

    const rowCount: number = await this.rdbManager.update(
      PostModel.getTableName(),
      values,
      predicates
    );
    return rowCount;
  }

  /**
   * 统计帖子总数
   * @returns 帖子总数
   */
  /**
   * @throws
   */
  async countPosts(): Promise<number> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('is_deleted', 0);

    const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
    const count: number = resultSet.rowCount;
    resultSet.close();
    return count;
  }

  /**
   * 统计某分类下的帖子数
   * @param categoryId 分类ID
   * @returns 帖子数量
   */
  /**
   * @throws
   */
  async countPostsByCategory(categoryId: string): Promise<number> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
      PostModel.getTableName()
    );
    predicates.equalTo('category_id', categoryId);
    predicates.equalTo('is_deleted', 0);

    const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
    const count: number = resultSet.rowCount;
    resultSet.close();
    return count;
  }

  /**
   * 解析结果集为单个帖子对象
   * @param resultSet 结果集
   * @returns 帖子对象
   */
  /**
   * @throws
   */
  private parseResultSetToPost(resultSet: relationalStore.ResultSet): PostModel | null {
    if (resultSet.rowCount === 0 || !resultSet.goToFirstRow()) {
      return null;
    }

    const post: PostModel = new PostModel();
    post.postId = resultSet.getString(resultSet.getColumnIndex('post_id'));
    post.userId = resultSet.getString(resultSet.getColumnIndex('user_id'));
    post.userName = resultSet.getString(resultSet.getColumnIndex('user_name'));
    post.userAvatar = resultSet.getString(resultSet.getColumnIndex('user_avatar'));
    post.content = resultSet.getString(resultSet.getColumnIndex('content'));
    post.imagePaths = resultSet.getString(resultSet.getColumnIndex('image_paths'));
    post.imageCount = resultSet.getLong(resultSet.getColumnIndex('image_count'));
    post.categoryId = resultSet.getString(resultSet.getColumnIndex('category_id'));
    post.categoryName = resultSet.getString(resultSet.getColumnIndex('category_name'));
    post.likeCount = resultSet.getLong(resultSet.getColumnIndex('like_count'));
    post.commentCount = resultSet.getLong(resultSet.getColumnIndex('comment_count'));
    post.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
    post.updateTime = resultSet.getLong(resultSet.getColumnIndex('update_time'));
    post.deviceId = resultSet.getString(resultSet.getColumnIndex('device_id'));
    post.syncStatus = resultSet.getLong(resultSet.getColumnIndex('sync_status'));
    post.isDeleted = resultSet.getLong(resultSet.getColumnIndex('is_deleted')) === 1;

    return post;
  }

  /**
   * 解析结果集为帖子列表
   * @param resultSet 结果集
   * @returns 帖子列表
   */
  /**
   * @throws
   */
  private parseResultSetToPosts(resultSet: relationalStore.ResultSet): PostModel[] {
    const posts: PostModel[] = [];

    if (resultSet.rowCount === 0) {
      return posts;
    }

    resultSet.goToFirstRow();
    do {
      const post: PostModel = new PostModel();
      post.postId = resultSet.getString(resultSet.getColumnIndex('post_id'));
      post.userId = resultSet.getString(resultSet.getColumnIndex('user_id'));
      post.userName = resultSet.getString(resultSet.getColumnIndex('user_name'));
      post.userAvatar = resultSet.getString(resultSet.getColumnIndex('user_avatar'));
      post.content = resultSet.getString(resultSet.getColumnIndex('content'));
      post.imagePaths = resultSet.getString(resultSet.getColumnIndex('image_paths'));
      post.imageCount = resultSet.getLong(resultSet.getColumnIndex('image_count'));
      post.categoryId = resultSet.getString(resultSet.getColumnIndex('category_id'));
      post.categoryName = resultSet.getString(resultSet.getColumnIndex('category_name'));
      post.likeCount = resultSet.getLong(resultSet.getColumnIndex('like_count'));
      post.commentCount = resultSet.getLong(resultSet.getColumnIndex('comment_count'));
      post.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
      post.updateTime = resultSet.getLong(resultSet.getColumnIndex('update_time'));
      post.deviceId = resultSet.getString(resultSet.getColumnIndex('device_id'));
      post.syncStatus = resultSet.getLong(resultSet.getColumnIndex('sync_status'));
      post.isDeleted = resultSet.getLong(resultSet.getColumnIndex('is_deleted')) === 1;

      posts.push(post);
    } while (resultSet.goToNextRow());

    return posts;
  }
}

export default PostRepository;
