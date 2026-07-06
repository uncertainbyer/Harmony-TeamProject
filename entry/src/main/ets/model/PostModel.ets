import { relationalStore } from "@kit.ArkData";

/**
 * 帖子数据模型
 * 用于存储用户发布的图片和文字动态
 */
export class PostModel {
  /** 帖子唯一标识（UUID） */
  postId: string = '';

  /** 发布用户ID */
  userId: string = '';

  /** 用户昵称 */
  userName: string = '';

  /** 用户头像路径 */
  userAvatar: string = '';

  /** 帖子文字内容 */
  content: string = '';

  /** 图片路径列表（JSON字符串格式） */
  imagePaths: string = '';

  /** 图片数量 */
  imageCount: number = 0;

  /** AI分类ID */
  categoryId: string = '';

  /** 分类名称 */
  categoryName: string = '';

  /** 点赞数 */
  likeCount: number = 0;

  /** 评论数 */
  commentCount: number = 0;

  /** 发布时间戳 */
  createTime: number = 0;

  /** 更新时间戳 */
  updateTime: number = 0;

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
    postId: string = '',
    userId: string = '',
    content: string = '',
    imagePaths: string = '',
    categoryId: string = ''
  ) {
    this.postId = postId;
    this.userId = userId;
    this.content = content;
    this.imagePaths = imagePaths;
    this.categoryId = categoryId;
    this.createTime = Date.now();
    this.updateTime = Date.now();
  }

  /**
   * 获取表名
   */
  static getTableName(): string {
    return 'post_info';
  }

  /**
   * 获取建表SQL语句
   */
  static getCreateTableSql(): string {
    return `CREATE TABLE IF NOT EXISTS post_info (
    post_id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL,
    user_name TEXT NOT NULL,
    user_avatar TEXT,
    content TEXT,
    image_paths TEXT,
    image_count INTEGER DEFAULT 0,
    category_id TEXT,
    category_name TEXT,
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    create_time INTEGER NOT NULL,
    update_time INTEGER NOT NULL,
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
      `CREATE INDEX IF NOT EXISTS idx_post_user ON ${PostModel.getTableName()}(user_id)`,
      `CREATE INDEX IF NOT EXISTS idx_post_category ON ${PostModel.getTableName()}(category_id)`,
      `CREATE INDEX IF NOT EXISTS idx_post_create_time ON ${PostModel.getTableName()}(create_time)`,
      `CREATE INDEX IF NOT EXISTS idx_post_sync ON ${PostModel.getTableName()}(sync_status)`
    ];
  }

  /**
   * 获取所有字段名
   */
  static getColumns(): string[] {
    return [
      'post_id',
      'user_id',
      'user_name',
      'user_avatar',
      'content',
      'image_paths',
      'image_count',
      'category_id',
      'category_name',
      'like_count',
      'comment_count',
      'create_time',
      'update_time',
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
    bucket['post_id'] = this.postId;
    bucket['user_id'] = this.userId;
    bucket['user_name'] = this.userName;
    bucket['user_avatar'] = this.userAvatar;
    bucket['content'] = this.content;
    bucket['image_paths'] = this.imagePaths;
    bucket['image_count'] = this.imageCount;
    bucket['category_id'] = this.categoryId;
    bucket['category_name'] = this.categoryName;
    bucket['like_count'] = this.likeCount;
    bucket['comment_count'] = this.commentCount;
    bucket['create_time'] = this.createTime;
    bucket['update_time'] = this.updateTime;
    bucket['device_id'] = this.deviceId;
    bucket['sync_status'] = this.syncStatus;
    bucket['is_deleted'] = this.isDeleted ? 1 : 0;
    return bucket;
  }

  /**
   * 解析图片路径JSON为数组
   */
  getImagePathArray(): string[] {
    if (!this.imagePaths) {
      return [];
    }
    try {
      return JSON.parse(this.imagePaths) as string[];
    } catch (e) {
      console.error('解析图片路径失败:', e);
      return [];
    }
  }

  /**
   * 设置图片路径数组
   */
  setImagePathArray(paths: string[]): void {
    this.imagePaths = JSON.stringify(paths);
    this.imageCount = paths.length;
  }
}

/**
 * 值类型定义（用于数据库操作）
 */
type ValueType = string | number | boolean | Uint8Array | null;