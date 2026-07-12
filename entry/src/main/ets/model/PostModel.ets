// model/PostModel.ts
import { relationalStore } from "@kit.ArkData";

export class PostModel {
  postId: string = '';
  userId: string = '';
  userName: string = '';
  userAvatar: string = '';
  content: string = '';
  imagePaths: string = '';
  imageCount: number = 0;
  categoryId: string = '';
  categoryName: string = '';
  likeCount: number = 0;
  commentCount: number = 0;
  isLiked: boolean = false;
  createTime: number = 0;
  updateTime: number = 0;
  deviceId: string = '';
  syncStatus: number = 0;
  isDeleted: boolean = false;

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

  static getTableName(): string {
    return 'post_info';
  }

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

  static getCreateIndexSql(): string[] {
    return [
      `CREATE INDEX IF NOT EXISTS idx_post_user ON ${PostModel.getTableName()}(user_id)`,
      `CREATE INDEX IF NOT EXISTS idx_post_category ON ${PostModel.getTableName()}(category_id)`,
      `CREATE INDEX IF NOT EXISTS idx_post_create_time ON ${PostModel.getTableName()}(create_time)`,
      `CREATE INDEX IF NOT EXISTS idx_post_sync ON ${PostModel.getTableName()}(sync_status)`
    ];
  }

  static getColumns(): string[] {
    return [
      'post_id', 'user_id', 'user_name', 'user_avatar', 'content',
      'image_paths', 'image_count', 'category_id', 'category_name',
      'like_count', 'comment_count',
      'create_time', 'update_time', 'device_id', 'sync_status', 'is_deleted'
    ];
  }

  toValuesBucket(): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {};
    bucket['post_id'] = this.postId;
    bucket['user_id'] = this.userId;
    bucket['user_name'] = this.userName;
    bucket['user_avatar'] = this.userAvatar;
    bucket['content'] = this.content;
    let pathsVal: string = this.imagePaths as string;
    if (typeof pathsVal !== 'string') {
      try { pathsVal = JSON.stringify(pathsVal); } catch (_) { pathsVal = '[]'; }
    }
    bucket['image_paths'] = pathsVal;
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

  getImagePathArray(): string[] {
    if (!this.imagePaths) return [];
    try {
      return JSON.parse(this.imagePaths) as string[];
    } catch (e) {
      return [];
    }
  }

  setImagePathArray(paths: string[]): void {
    this.imagePaths = JSON.stringify(paths);
    this.imageCount = paths.length;
  }
}