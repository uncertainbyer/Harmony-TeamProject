import { relationalStore } from "@kit.ArkData";

/**
 * 评论数据模型
 * 用于存储用户对帖子的评论和回复
 */
export class CommentModel {
  /** 评论唯一标识（UUID） */
  commentId: string = '';

  /** 关联的帖子ID */
  postId: string = '';

  /** 评论用户ID */
  userId: string = '';

  /** 评论用户昵称 */
  userName: string = '';

  /** 评论用户头像 */
  userAvatar: string = '';

  /** 评论内容 */
  content: string = '';

  /** 父评论ID（用于回复功能，空表示一级评论） */
  parentId: string = '';

  /** 被回复用户ID */
  replyToUserId: string = '';

  /** 被回复用户昵称 */
  replyToUserName: string = '';

  /** 评论层级：1-一级评论，2-二级回复 */
  level: number = 1;

  /** 点赞数 */
  likeCount: number = 0;

  /** 评论时间戳 */
  createTime: number = 0;

  /** 发布设备ID（用于分布式同步） */
  deviceId: string = '';

  /** 同步状态：0-未同步，1-已同步 */
  syncStatus: number = 0;

  /** 是否已删除（软删除标记） */
  isDeleted: boolean = false;

  /**
   * 构造函数
   */
  constructor(
    commentId: string = '',
    postId: string = '',
    userId: string = '',
    content: string = '',
    parentId: string = ''
  ) {
    this.commentId = commentId;
    this.postId = postId;
    this.userId = userId;
    this.content = content;
    this.parentId = parentId;
    this.level = parentId ? 2 : 1;
    this.createTime = Date.now();
  }

  /**
   * 获取表名
   */
  static getTableName(): string {
    return 'comment_info';
  }

  /**
   * 获取建表SQL语句
   */
  static getCreateTableSql(): string {
    return `CREATE TABLE IF NOT EXISTS comment_info (
    comment_id TEXT PRIMARY KEY NOT NULL,
    post_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    user_name TEXT NOT NULL,
    user_avatar TEXT,
    content TEXT,
    parent_id TEXT,
    reply_to_user_id TEXT,
    reply_to_user_name TEXT,
    level INTEGER DEFAULT 1,
    like_count INTEGER DEFAULT 0,
    create_time INTEGER NOT NULL,
    device_id TEXT,
    sync_status INTEGER DEFAULT 0,
    is_deleted INTEGER DEFAULT 0
  )`;
  }

  /**
   * 获取索引创建SQL语句
   */
  static getCreateIndexSql(): string[] {
    return [
      `CREATE INDEX IF NOT EXISTS idx_comment_post ON ${CommentModel.getTableName()}(post_id)`,
      `CREATE INDEX IF NOT EXISTS idx_comment_user ON ${CommentModel.getTableName()}(user_id)`,
      `CREATE INDEX IF NOT EXISTS idx_comment_parent ON ${CommentModel.getTableName()}(parent_id)`,
      `CREATE INDEX IF NOT EXISTS idx_comment_create_time ON ${CommentModel.getTableName()}(create_time)`
    ];
  }

  /**
   * 获取所有字段名
   */
  static getColumns(): string[] {
    return [
      'comment_id',
      'post_id',
      'user_id',
      'user_name',
      'user_avatar',
      'content',
      'parent_id',
      'reply_to_user_id',
      'reply_to_user_name',
      'level',
      'like_count',
      'create_time',
      'device_id',
      'sync_status',
      'is_deleted'
    ];
  }

  /**
   * 转换为数据库存储格式
   */
  toValuesBucket(): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {};
    bucket['comment_id'] = this.commentId;
    bucket['post_id'] = this.postId;
    bucket['user_id'] = this.userId;
    bucket['user_name'] = this.userName;
    bucket['user_avatar'] = this.userAvatar;
    bucket['content'] = this.content;
    bucket['parent_id'] = this.parentId;
    bucket['reply_to_user_id'] = this.replyToUserId;
    bucket['reply_to_user_name'] = this.replyToUserName;
    bucket['level'] = this.level;
    bucket['like_count'] = this.likeCount;
    bucket['create_time'] = this.createTime;
    bucket['device_id'] = this.deviceId;
    bucket['sync_status'] = this.syncStatus;
    bucket['is_deleted'] = this.isDeleted ? 1 : 0;
    return bucket;
  }

  /**
   * 判断是否为一级评论
   */
  isTopLevel(): boolean {
    return this.level === 1 && !this.parentId;
  }

  /**
   * 判断是否为回复
   */
  isReply(): boolean {
    return this.level === 2 && !!this.parentId;
  }
}

/**
 * 值类型定义（用于数据库操作）
 */
type ValueType = string | number | boolean | Uint8Array | null;