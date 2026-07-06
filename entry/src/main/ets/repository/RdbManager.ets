import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PostModel } from '../model/PostModel';
import { CommentModel } from '../model/CommentModel';
import { CategoryModel } from '../model/CategoryModel';

/**
 * 数据库配置常量
 */
const DB_NAME: string = 'SocialPhoto.db';

/**
 * 关系型数据库管理器
 * 负责数据库初始化、表创建和基础操作封装
 */
export class RdbManager {
  private static instance: RdbManager | null = null;
  private rdbStore: relationalStore.RdbStore | null = null;

  /**
   * 私有构造函数（单例模式）
   */
  private constructor() {}

  /**
   * 获取单例实例
   */
  static getInstance(): RdbManager {
    if (RdbManager.instance === null) {
      RdbManager.instance = new RdbManager();
    }
    return RdbManager.instance;
  }

  /**
   * 初始化数据库
   * @param context 应用上下文
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, config);
      await this.createTables();
      await this.initDefaultCategories();
      console.info('[RdbManager] 数据库初始化成功');
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[RdbManager] 数据库初始化失败:', errorMsg);
      throw new Error('数据库初始化失败: ' + errorMsg);
    }
  }

  /**
   * 创建所有数据表
   */
  private async createTables(): Promise<void> {
    if (this.rdbStore === null) {
      throw new Error('数据库未初始化');
    }

    try {
      // 创建帖子表
      await this.rdbStore.executeSql(PostModel.getCreateTableSql());
      const postIndexes: string[] = PostModel.getCreateIndexSql();
      for (let i: number = 0; i < postIndexes.length; i++) {
        await this.rdbStore.executeSql(postIndexes[i]);
      }

      // 创建评论表
      await this.rdbStore.executeSql(CommentModel.getCreateTableSql());
      const commentIndexes: string[] = CommentModel.getCreateIndexSql();
      for (let i: number = 0; i < commentIndexes.length; i++) {
        await this.rdbStore.executeSql(commentIndexes[i]);
      }

      // 创建分类表
      await this.rdbStore.executeSql(CategoryModel.getCreateTableSql());
      const categoryIndexes: string[] = CategoryModel.getCreateIndexSql();
      for (let i: number = 0; i < categoryIndexes.length; i++) {
        await this.rdbStore.executeSql(categoryIndexes[i]);
      }

      console.info('[RdbManager] 数据表创建成功');
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[RdbManager] 数据表创建失败:', errorMsg);
      throw new Error('数据表创建失败: ' + errorMsg);
    }
  }

  /**
   * 初始化默认分类数据
   */
  private async initDefaultCategories(): Promise<void> {
    if (this.rdbStore === null) {
      return;
    }

    try {
      // 检查是否已有分类数据
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(
        CategoryModel.getTableName()
      );
      const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
      const count: number = resultSet.rowCount;
      resultSet.close();

      if (count === 0) {
        // 插入默认分类
        const defaultCategories: CategoryModel[] = CategoryModel.getDefaultCategories();
        for (let i: number = 0; i < defaultCategories.length; i++) {
          const category: CategoryModel = defaultCategories[i];
          await this.rdbStore.insert(CategoryModel.getTableName(), category.toValuesBucket());
        }
        console.info('[RdbManager] 默认分类初始化成功');
      }
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[RdbManager] 默认分类初始化失败:', errorMsg);
    }
  }

  /**
   * 获取RdbStore实例
   */
  getRdbStore(): relationalStore.RdbStore {
    if (this.rdbStore === null) {
      throw new Error('数据库未初始化，请先调用init方法');
    }
    return this.rdbStore;
  }

  /**
   * 插入数据
   * @param tableName 表名
   * @param values 数据值
   * @returns 插入的行ID
   */
  async insert(tableName: string, values: relationalStore.ValuesBucket): Promise<number> {
    const store: relationalStore.RdbStore = this.getRdbStore();
    try {
      const rowId: number = await store.insert(tableName, values);
      return rowId;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error(`[RdbManager] 插入数据失败: ${tableName}`, errorMsg);
      throw new Error('插入数据失败: ' + errorMsg);
    }
  }

  /**
   * 批量插入数据（使用事务）
   * @param tableName 表名
   * @param valuesList 数据列表
   */
  async batchInsert(tableName: string, valuesList: relationalStore.ValuesBucket[]): Promise<void> {
    const store: relationalStore.RdbStore = this.getRdbStore();
    try {
      store.beginTransaction();
      for (let i: number = 0; i < valuesList.length; i++) {
        await store.insert(tableName, valuesList[i]);
      }
      store.commit();
      console.info(`[RdbManager] 批量插入成功: ${tableName}, 数量: ${valuesList.length}`);
    } catch (err) {
      store.rollBack();
      const errorMsg: string = (err as Error).message;
      console.error(`[RdbManager] 批量插入失败: ${tableName}`, errorMsg);
      throw new Error('批量插入失败: ' + errorMsg);
    }
  }

  /**
   * 更新数据
   * @param tableName 表名
   * @param values 更新值
   * @param predicates 条件谓词
   * @returns 更新的行数
   */
  async update(
    tableName: string,
    values: relationalStore.ValuesBucket,
    predicates: relationalStore.RdbPredicates
  ): Promise<number> {
    const store: relationalStore.RdbStore = this.getRdbStore();
    try {
      const rowCount: number = await store.update(values, predicates);
      return rowCount;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error(`[RdbManager] 更新数据失败: ${tableName}`, errorMsg);
      throw new Error('更新数据失败: ' + errorMsg);
    }
  }

  /**
   * 删除数据
   * @param tableName 表名
   * @param predicates 条件谓词
   * @returns 删除的行数
   */
  async deleteData(tableName: string, predicates: relationalStore.RdbPredicates): Promise<number> {
    const store: relationalStore.RdbStore = this.getRdbStore();
    try {
      const rowCount: number = await store.delete(predicates);
      return rowCount;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error(`[RdbManager] 删除数据失败: ${tableName}`, errorMsg);
      throw new Error('删除数据失败: ' + errorMsg);
    }
  }

  /**
   * 查询数据
   * @param predicates 条件谓词
   * @param columns 查询列（可选）
   * @returns 结果集
   */
  async query(
    predicates: relationalStore.RdbPredicates,
    columns?: string[]
  ): Promise<relationalStore.ResultSet> {
    const store: relationalStore.RdbStore = this.getRdbStore();
    try {
      const resultSet: relationalStore.ResultSet = await store.query(predicates, columns);
      return resultSet;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[RdbManager] 查询数据失败:', errorMsg);
      throw new Error('查询数据失败: ' + errorMsg);
    }
  }

  /**
   * 执行原生SQL语句
   * @param sql SQL语句
   */
  async executeSql(sql: string): Promise<void> {
    const store: relationalStore.RdbStore = this.getRdbStore();
    try {
      await store.executeSql(sql);
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[RdbManager] 执行SQL失败:', sql, errorMsg);
      throw new Error('执行SQL失败: ' + errorMsg);
    }
  }

  /**
   * 开始事务
   */
  /**
   * @throws
   */
  beginTransaction(): void {
    const store: relationalStore.RdbStore = this.getRdbStore();
    store.beginTransaction();
  }

  /**
   * 提交事务
   */
  /**
   * @throws
   */
  commit(): void {
    const store: relationalStore.RdbStore = this.getRdbStore();
    store.commit();
  }

  /**
   * 回滚事务
   */
  /**
   * @throws
   */
  rollBack(): void {
    const store: relationalStore.RdbStore = this.getRdbStore();
    store.rollBack();
  }
}

export default RdbManager;