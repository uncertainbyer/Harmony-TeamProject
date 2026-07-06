import { relationalStore } from '@kit.ArkData';

/**
 * 分类数据模型
 * 用于存储AI模型对图片的自动分类信息
 */
export class CategoryModel {
  /** 分类唯一标识（UUID） */
  categoryId: string = '';

  /** 分类名称 */
  categoryName: string = '';

  /** 分类图标（可选，用于UI展示） */
  icon: string = '';

  /** 分类描述 */
  description: string = '';

  /** 分类颜色（用于UI标识，如 #FF5722） */
  color: string = '';

  /** 该分类下的图片数量 */
  imageCount: number = 0;

  /** 该分类下的帖子数量 */
  postCount: number = 0;

  /** 分类排序权重（数值越小越靠前） */
  sortWeight: number = 0;

  /** 分类来源：0-系统预设，1-AI生成 */
  source: number = 1;

  /** 置信度阈值（AI分类时的最小置信度） */
  confidenceThreshold: number = 0.8;

  /** 创建时间戳 */
  createTime: number = 0;

  /** 更新时间戳 */
  updateTime: number = 0;

  /** 是否启用 */
  isEnabled: boolean = true;

  /**
   * 构造函数
   */
  constructor(
    categoryId: string = '',
    categoryName: string = '',
    description: string = ''
  ) {
    this.categoryId = categoryId;
    this.categoryName = categoryName;
    this.description = description;
    this.createTime = Date.now();
    this.updateTime = Date.now();
  }

  /**
   * 获取表名
   */
  static getTableName(): string {
    return 'category_info';
  }

  /**
   * 获取建表SQL语句
   */
  static getCreateTableSql(): string {
    return `CREATE TABLE IF NOT EXISTS category_info (
    category_id TEXT PRIMARY KEY NOT NULL,
    category_name TEXT NOT NULL,
    icon TEXT,
    description TEXT,
    color TEXT,
    image_count INTEGER DEFAULT 0,
    post_count INTEGER DEFAULT 0,
    sort_weight INTEGER DEFAULT 0,
    source INTEGER DEFAULT 1,
    confidence_threshold REAL DEFAULT 0.8,
    create_time INTEGER NOT NULL,
    update_time INTEGER NOT NULL,
    is_enabled INTEGER DEFAULT 1
  )`;
  }

  /**
   * 获取索引创建SQL语句
   */
  static getCreateIndexSql(): string[] {
    const indexes: string[] = [];
    indexes.push('CREATE INDEX IF NOT EXISTS idx_category_name ON category_info(category_name)');
    indexes.push('CREATE INDEX IF NOT EXISTS idx_category_sort ON category_info(sort_weight)');
    indexes.push('CREATE INDEX IF NOT EXISTS idx_category_source ON category_info(source)');
    return indexes;
  }

  /**
   * 获取所有字段名
   */
  static getColumns(): string[] {
    const columns: string[] = [
      'category_id',
      'category_name',
      'icon',
      'description',
      'color',
      'image_count',
      'post_count',
      'sort_weight',
      'source',
      'confidence_threshold',
      'create_time',
      'update_time',
      'is_enabled'
    ];
    return columns;
  }

  /**
   * 转换为数据库存储格式
   */
  toValuesBucket(): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {};
    bucket['category_id'] = this.categoryId;
    bucket['category_name'] = this.categoryName;
    bucket['icon'] = this.icon;
    bucket['description'] = this.description;
    bucket['color'] = this.color;
    bucket['image_count'] = this.imageCount;
    bucket['post_count'] = this.postCount;
    bucket['sort_weight'] = this.sortWeight;
    bucket['source'] = this.source;
    bucket['confidence_threshold'] = this.confidenceThreshold;
    bucket['create_time'] = this.createTime;
    bucket['update_time'] = this.updateTime;
    bucket['is_enabled'] = this.isEnabled ? 1 : 0;
    return bucket;
  }

  /**
   * 获取系统预设分类列表
   */
  static getDefaultCategories(): CategoryModel[] {
    const now: number = Date.now();
    const categories: CategoryModel[] = [];

    const scenery: CategoryModel = new CategoryModel('cat_scenery', '风景', '');
    scenery.icon = '🌲';
    scenery.color = '#4CAF50';
    scenery.sortWeight = 1;
    scenery.source = 0;
    scenery.createTime = now;
    scenery.updateTime = now;
    categories.push(scenery);

    const person: CategoryModel = new CategoryModel('cat_person', '人物', '');
    person.icon = '👤';
    person.color = '#2196F3';
    person.sortWeight = 2;
    person.source = 0;
    person.createTime = now;
    person.updateTime = now;
    categories.push(person);

    const food: CategoryModel = new CategoryModel('cat_food', '美食', '');
    food.icon = '🍽️';
    food.color = '#FF9800';
    food.sortWeight = 3;
    food.source = 0;
    food.createTime = now;
    food.updateTime = now;
    categories.push(food);

    const animal: CategoryModel = new CategoryModel('cat_animal', '动物', '');
    animal.icon = '🐾';
    animal.color = '#9C27B0';
    animal.sortWeight = 4;
    animal.source = 0;
    animal.createTime = now;
    animal.updateTime = now;
    categories.push(animal);

    const building: CategoryModel = new CategoryModel('cat_building', '建筑', '');
    building.icon = '🏛️';
    building.color = '#607D8B';
    building.sortWeight = 5;
    building.source = 0;
    building.createTime = now;
    building.updateTime = now;
    categories.push(building);

    const other: CategoryModel = new CategoryModel('cat_other', '其他', '');
    other.icon = '📁';
    other.color = '#9E9E9E';
    other.sortWeight = 99;
    other.source = 0;
    other.createTime = now;
    other.updateTime = now;
    categories.push(other);

    return categories;
  }
}