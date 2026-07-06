import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { CommentModel } from '../model/CommentModel';

/**
 * 评论数据访问层
 * 负责评论数据的增删改查操作
 */
export class CommentRepository {
  private rdbManager: RdbManager = RdbManager.getInstance();

  /**
   * 插入新评论
   * @param comment 评论对象
   * @returns 插入的行ID
   */
  async insertComment(comment: CommentModel): Promise<number> {
    try {
      const rowId: number = await this.rdbManager.insert(
        CommentModel.getTableName(),
        comment.toValuesBucket()
      );
      return rowId;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 插入评论失败:', errorMsg);
      throw new Error('插入评论失败: ' + errorMsg);
    }
  }

  /**
   * 批量插入评论
   * @param comments 评论列表
   */
  async batchInsertComments(comments: CommentModel[]): Promise<void> {
    try {
      const valuesList: relationalStore.ValuesBucket[] = [];
      for (let i: number = 0; i < comments.length; i++) {
        valuesList.push(comments[i].toValuesBucket());
      }
      await this.rdbManager.batchInsert(CommentModel.getTableName(), valuesList);
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 批量插入评论失败:', errorMsg);
      throw new Error('批量插入评论失败: ' + errorMsg);
    }
  }

  /**
   * 根据ID查询评论
   * @param commentId 评论ID
   * @returns 评论对象，不存在则返回null
   */
  async queryCommentById(commentId: string): Promise<CommentModel | null> {
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('comment_id', commentId);
      predicates.equalTo('is_deleted', 0);

      const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
      const comment: CommentModel | null = this.parseResultSetToComment(resultSet);
      resultSet.close();
      return comment;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 查询评论失败:', errorMsg);
      throw new Error('查询评论失败: ' + errorMsg);
    }
  }

  /**
   * 查询帖子的所有一级评论
   * @param postId 帖子ID
   * @param limit 限制数量
   * @param offset 偏移量
   * @returns 评论列表
   */
  async queryTopLevelComments(
    postId: string,
    limit?: number,
    offset?: number
  ): Promise<CommentModel[]> {
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('post_id', postId);
      predicates.equalTo('level', 1);
      predicates.equalTo('is_deleted', 0);
      predicates.orderByDesc('create_time');

      if (limit !== undefined && offset !== undefined) {
        predicates.limitAs(limit);
        predicates.offsetAs(offset);
      } else if (limit !== undefined) {
        predicates.limitAs(limit);
      }

      const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
      const comments: CommentModel[] = this.parseResultSetToComments(resultSet);
      resultSet.close();
      return comments;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 查询一级评论失败:', errorMsg);
      throw new Error('查询一级评论失败: ' + errorMsg);
    }
  }

  /**
   * 查询评论的所有回复
   * @param parentId 父评论ID
   * @returns 回复列表
   */
  async queryReplies(parentId: string): Promise<CommentModel[]> {
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('parent_id', parentId);
      predicates.equalTo('level', 2);
      predicates.equalTo('is_deleted', 0);
      predicates.orderByAsc('create_time');

      const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
      const comments: CommentModel[] = this.parseResultSetToComments(resultSet);
      resultSet.close();
      return comments;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 查询回复失败:', errorMsg);
      throw new Error('查询回复失败: ' + errorMsg);
    }
  }

  /**
   * 查询帖子的所有评论（包含回复）
   * @param postId 帖子ID
   * @returns 评论列表
   */
  async queryAllCommentsByPost(postId: string): Promise<CommentModel[]> {
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('post_id', postId);
      predicates.equalTo('is_deleted', 0);
      predicates.orderByAsc('create_time');

      const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
      const comments: CommentModel[] = this.parseResultSetToComments(resultSet);
      resultSet.close();
      return comments;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 查询帖子所有评论失败:', errorMsg);
      throw new Error('查询帖子所有评论失败: ' + errorMsg);
    }
  }

  /**
   * 根据用户ID查询评论
   * @param userId 用户ID
   * @param limit 限制数量
   * @param offset 偏移量
   * @returns 评论列表
   */
  async queryCommentsByUser(
    userId: string,
    limit?: number,
    offset?: number
  ): Promise<CommentModel[]> {
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
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
      const comments: CommentModel[] = this.parseResultSetToComments(resultSet);
      resultSet.close();
      return comments;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 查询用户评论失败:', errorMsg);
      throw new Error('查询用户评论失败: ' + errorMsg);
    }
  }

  /**
   * 更新评论
   * @param comment 评论对象
   * @returns 更新的行数
   */
  async updateComment(comment: CommentModel): Promise<number> {
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('comment_id', comment.commentId);

      const rowCount: number = await this.rdbManager.update(
        CommentModel.getTableName(),
        comment.toValuesBucket(),
        predicates
      );
      return rowCount;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 更新评论失败:', errorMsg);
      throw new Error('更新评论失败: ' + errorMsg);
    }
  }

  /**
   * 更新评论点赞数
   * @param commentId 评论ID
   * @param likeCount 新的点赞数
   * @returns 更新的行数
   */
  async updateCommentLikeCount(commentId: string, likeCount: number): Promise<number> {
    try {
      const values: relationalStore.ValuesBucket = {};
      values['like_count'] = likeCount;

      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('comment_id', commentId);

      const rowCount: number = await this.rdbManager.update(
        CommentModel.getTableName(),
        values,
        predicates
      );
      return rowCount;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 更新评论点赞数失败:', errorMsg);
      throw new Error('更新评论点赞数失败: ' + errorMsg);
    }
  }

  /**
   * 软删除评论
   * @param commentId 评论ID
   * @returns 删除的行数
   */
  async deleteComment(commentId: string): Promise<number> {
    try {
      const values: relationalStore.ValuesBucket = {};
      values['is_deleted'] = 1;

      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('comment_id', commentId);

      const rowCount: number = await this.rdbManager.update(
        CommentModel.getTableName(),
        values,
        predicates
      );
      return rowCount;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 删除评论失败:', errorMsg);
      throw new Error('删除评论失败: ' + errorMsg);
    }
  }

  /**
   * 查询未同步的评论
   * @returns 未同步的评论列表
   */
  async queryUnsyncedComments(): Promise<CommentModel[]> {
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('sync_status', 0);
      predicates.equalTo('is_deleted', 0);

      const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
      const comments: CommentModel[] = this.parseResultSetToComments(resultSet);
      resultSet.close();
      return comments;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 查询未同步评论失败:', errorMsg);
      throw new Error('查询未同步评论失败: ' + errorMsg);
    }
  }

  /**
   * 更新评论同步状态
   * @param commentId 评论ID
   * @param syncStatus 同步状态
   * @returns 更新的行数
   */
  async updateCommentSyncStatus(commentId: string, syncStatus: number): Promise<number> {
    try {
      const values: relationalStore.ValuesBucket = {};
      values['sync_status'] = syncStatus;

      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('comment_id', commentId);

      const rowCount: number = await this.rdbManager.update(
        CommentModel.getTableName(),
        values,
        predicates
      );
      return rowCount;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 更新同步状态失败:', errorMsg);
      throw new Error('更新同步状态失败: ' + errorMsg);
    }
  }

  /**
   * 统计帖子的评论数
   * @param postId 帖子ID
   * @returns 评论数量
   */
  async countCommentsByPost(postId: string): Promise<number> {
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('post_id', postId);
      predicates.equalTo('is_deleted', 0);

      const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
      const count: number = resultSet.rowCount;
      resultSet.close();
      return count;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 统计评论数失败:', errorMsg);
      throw new Error('统计评论数失败: ' + errorMsg);
    }
  }

  /**
   * 统计评论的回复数
   * @param parentId 父评论ID
   * @returns 回复数量
   */
  async countReplies(parentId: string): Promise<number> {
    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CommentModel.getTableName()
      );
      predicates.equalTo('parent_id', parentId);
      predicates.equalTo('level', 2);
      predicates.equalTo('is_deleted', 0);

      const resultSet: relationalStore.ResultSet = await this.rdbManager.query(predicates);
      const count: number = resultSet.rowCount;
      resultSet.close();
      return count;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[CommentRepository] 统计回复数失败:', errorMsg);
      throw new Error('统计回复数失败: ' + errorMsg);
    }
  }

  /**
   * 解析结果集为单个评论对象
   * @param resultSet 结果集
   * @returns 评论对象
   */
  /**
   * @throws
   */
  private parseResultSetToComment(resultSet: relationalStore.ResultSet): CommentModel | null {
    if (resultSet.rowCount === 0 || !resultSet.goToFirstRow()) {
      return null;
    }

    const comment: CommentModel = new CommentModel();
    comment.commentId = resultSet.getString(resultSet.getColumnIndex('comment_id'));
    comment.postId = resultSet.getString(resultSet.getColumnIndex('post_id'));
    comment.userId = resultSet.getString(resultSet.getColumnIndex('user_id'));
    comment.userName = resultSet.getString(resultSet.getColumnIndex('user_name'));
    comment.userAvatar = resultSet.getString(resultSet.getColumnIndex('user_avatar'));
    comment.content = resultSet.getString(resultSet.getColumnIndex('content'));
    comment.parentId = resultSet.getString(resultSet.getColumnIndex('parent_id'));
    comment.replyToUserId = resultSet.getString(resultSet.getColumnIndex('reply_to_user_id'));
    comment.replyToUserName = resultSet.getString(resultSet.getColumnIndex('reply_to_user_name'));
    comment.level = resultSet.getLong(resultSet.getColumnIndex('level'));
    comment.likeCount = resultSet.getLong(resultSet.getColumnIndex('like_count'));
    comment.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
    comment.deviceId = resultSet.getString(resultSet.getColumnIndex('device_id'));
    comment.syncStatus = resultSet.getLong(resultSet.getColumnIndex('sync_status'));
    comment.isDeleted = resultSet.getLong(resultSet.getColumnIndex('is_deleted')) === 1;

    return comment;
  }

  /**
   * 解析结果集为评论列表
   * @param resultSet 结果集
   * @returns 评论列表
   */
  /**
   * @throws
   */
  private parseResultSetToComments(resultSet: relationalStore.ResultSet): CommentModel[] {
    const comments: CommentModel[] = [];

    if (resultSet.rowCount === 0) {
      return comments;
    }

    resultSet.goToFirstRow();
    do {
      const comment: CommentModel = new CommentModel();
      comment.commentId = resultSet.getString(resultSet.getColumnIndex('comment_id'));
      comment.postId = resultSet.getString(resultSet.getColumnIndex('post_id'));
      comment.userId = resultSet.getString(resultSet.getColumnIndex('user_id'));
      comment.userName = resultSet.getString(resultSet.getColumnIndex('user_name'));
      comment.userAvatar = resultSet.getString(resultSet.getColumnIndex('user_avatar'));
      comment.content = resultSet.getString(resultSet.getColumnIndex('content'));
      comment.parentId = resultSet.getString(resultSet.getColumnIndex('parent_id'));
      comment.replyToUserId = resultSet.getString(resultSet.getColumnIndex('reply_to_user_id'));
      comment.replyToUserName = resultSet.getString(resultSet.getColumnIndex('reply_to_user_name'));
      comment.level = resultSet.getLong(resultSet.getColumnIndex('level'));
      comment.likeCount = resultSet.getLong(resultSet.getColumnIndex('like_count'));
      comment.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
      comment.deviceId = resultSet.getString(resultSet.getColumnIndex('device_id'));
      comment.syncStatus = resultSet.getLong(resultSet.getColumnIndex('sync_status'));
      comment.isDeleted = resultSet.getLong(resultSet.getColumnIndex('is_deleted')) === 1;

      comments.push(comment);
    } while (resultSet.goToNextRow());

    return comments;
  }
}

export default CommentRepository;