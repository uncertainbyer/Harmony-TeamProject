/**
 * 应用常量定义类
 * 存储应用中使用的各种常量
 */
export class Constants {
  /** 应用名称 */
  static readonly APP_NAME: string = 'SocialPhoto';

  /** 应用版本 */
  static readonly APP_VERSION: string = '1.0.0';

  /** 数据库名称 */
  static readonly DB_NAME: string = 'SocialPhoto.db';

  /** 数据库版本 */
  static readonly DB_VERSION: number = 1;

  /** 默认分页大小 */
  static readonly PAGE_SIZE: number = 20;

  /** 最大图片上传数量 */
  static readonly MAX_IMAGE_COUNT: number = 9;

  /** 图片最大尺寸（像素） */
  static readonly MAX_IMAGE_SIZE: number = 4096;

  /** 图片压缩质量（0-100） */
  static readonly IMAGE_QUALITY: number = 80;

  /** 网络请求超时时间（毫秒） */
  static readonly NETWORK_TIMEOUT: number = 30000;

  /** 连接超时时间（毫秒） */
  static readonly CONNECT_TIMEOUT: number = 10000;

  /** 读取超时时间（毫秒） */
  static readonly READ_TIMEOUT: number = 60000;

  /** Toast显示时长（毫秒） */
  static readonly TOAST_DURATION: number = 2000;

  /** 动画时长（毫秒） */
  static readonly ANIMATION_DURATION: number = 300;
}

/**
 * 分类相关常量
 */
export class CategoryConstants {
  /** 风景分类ID */
  static readonly SCENERY: string = 'cat_scenery';

  /** 人物分类ID */
  static readonly PERSON: string = 'cat_person';

  /** 美食分类ID */
  static readonly FOOD: string = 'cat_food';

  /** 动物分类ID */
  static readonly ANIMAL: string = 'cat_animal';

  /** 建筑分类ID */
  static readonly BUILDING: string = 'cat_building';

  /** 其他分类ID */
  static readonly OTHER: string = 'cat_other';
}

/**
 * 同步状态常量
 */
export class SyncConstants {
  /** 未同步 */
  static readonly UNSYNCED: number = 0;

  /** 已同步 */
  static readonly SYNCED: number = 1;

  /** 同步中 */
  static readonly SYNCING: number = 2;

  /** 同步失败 */
  static readonly FAILED: number = 3;
}

/**
 * 错误码常量
 */
export class ErrorCode {
  /** 成功 */
  static readonly SUCCESS: number = 0;

  /** 网络错误 */
  static readonly NETWORK_ERROR: number = 1001;

  /** 数据库错误 */
  static readonly DB_ERROR: number = 1002;

  /** 文件错误 */
  static readonly FILE_ERROR: number = 1003;

  /** 参数错误 */
  static readonly PARAM_ERROR: number = 1004;

  /** 权限错误 */
  static readonly PERMISSION_ERROR: number = 1005;

  /** 服务器错误 */
  static readonly SERVER_ERROR: number = 2001;

  /** 数据不存在 */
  static readonly DATA_NOT_FOUND: number = 2002;

  /** 数据已存在 */
  static readonly DATA_EXISTS: number = 2003;
}

/**
 * 存储键常量
 */
export class StorageKey {
  /** 用户ID */
  static readonly USER_ID: string = 'user_id';

  /** 用户昵称 */
  static readonly USER_NAME: string = 'user_name';

  /** 用户头像 */
  static readonly USER_AVATAR: string = 'user_avatar';

  /** 设备ID */
  static readonly DEVICE_ID: string = 'device_id';

  /** 登录状态 */
  static readonly IS_LOGGED_IN: string = 'is_logged_in';

  /** 最后同步时间 */
  static readonly LAST_SYNC_TIME: string = 'last_sync_time';

  /** 主题模式 */
  static readonly THEME_MODE: string = 'theme_mode';

  /** 语言设置 */
  static readonly LANGUAGE: string = 'language';
}

export default Constants;