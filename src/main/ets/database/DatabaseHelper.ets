import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { RdbManager } from '../repository/RdbManager';
import { GlobalContext } from '../common/GlobalContext';

/**
 * 数据库初始化结果
 */
export interface DbInitResult {
  /** 是否成功 */
  success: boolean;

  /** 错误信息 */
  errorMsg: string;
}

/**
 * 数据库辅助类
 * 提供数据库初始化和常用操作封装
 */
interface GeneratedTypeLiteralInterface_1 {
  postCount: number;
  commentCount: number;
  categoryCount: number;
  dbSize: number;
}

export class DatabaseHelper {
  private static instance: DatabaseHelper | null = null;
  private rdbManager: RdbManager = RdbManager.getInstance();
  private isInitialized: boolean = false;

  /**
   * 私有构造函数（单例模式）
   */
  private constructor() {
  }

  /**
   * 获取单例实例
   * @returns DatabaseHelper实例
   */
  static getInstance(): DatabaseHelper {
    if (DatabaseHelper.instance === null) {
      DatabaseHelper.instance = new DatabaseHelper();
    }
    return DatabaseHelper.instance;
  }

  /**
   * 初始化数据库
   * @param context 应用上下文
   * @returns 初始化结果
   */
  async init(context: common.UIAbilityContext): Promise<DbInitResult> {
    if (this.isInitialized) {
      const result: DbInitResult = {
        success: true,
        errorMsg: '数据库已初始化'
      };
      return result;
    }

    try {
      // 保存上下文到全局
      GlobalContext.getInstance().setContext(context);

      // 初始化RdbManager
      await this.rdbManager.init(context);

      this.isInitialized = true;

      const result: DbInitResult = {
        success: true,
        errorMsg: ''
      };
      console.info('[DatabaseHelper] 数据库初始化成功');
      return result;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DatabaseHelper] 数据库初始化失败:', errorMsg);
      const result: DbInitResult = {
        success: false,
        errorMsg: errorMsg
      };
      return result;
    }
  }

  /**
   * 检查数据库是否已初始化
   * @returns 是否已初始化
   */
  isReady(): boolean {
    return this.isInitialized;
  }

  /**
   * 获取RdbManager实例
   * @returns RdbManager实例
   */
  getRdbManager(): RdbManager {
    if (!this.isInitialized) {
      throw new Error('数据库未初始化，请先调用init方法');
    }
    return this.rdbManager;
  }

  /**
   * 获取RdbStore实例
   * @returns RdbStore实例
   */
  getRdbStore(): relationalStore.RdbStore {
    if (!this.isInitialized) {
      throw new Error('数据库未初始化，请先调用init方法');
    }
    return this.rdbManager.getRdbStore();
  }

  /**
   * 执行事务操作
   * @param operation 事务操作函数
   * @returns 操作结果
   */
  async executeTransaction<T>(operation: () => Promise<T>): Promise<T> {
    if (!this.isInitialized) {
      throw new Error('数据库未初始化');
    }

    try {
      this.rdbManager.beginTransaction();
      const result: T = await operation();
      this.rdbManager.commit();
      return result;
    } catch (err) {
      this.rdbManager.rollBack();
      const errorMsg: string = (err as Error).message;
      console.error('[DatabaseHelper] 事务执行失败:', errorMsg);
      throw new Error('事务执行失败: ' + errorMsg);
    }
  }

  /**
   * 清空所有数据（危险操作）
   */
  async clearAllData(): Promise<void> {
    if (!this.isInitialized) {
      throw new Error('数据库未初始化');
    }

    try {
      const store: relationalStore.RdbStore = this.rdbManager.getRdbStore();

      // 删除所有数据
      await store.executeSql('DELETE FROM post_info');
      await store.executeSql('DELETE FROM comment_info');
      await store.executeSql('DELETE FROM category_info');

      console.info('[DatabaseHelper] 所有数据已清空');
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DatabaseHelper] 清空数据失败:', errorMsg);
      throw new Error('清空数据失败: ' + errorMsg);
    }
  }

  /**
   * 获取数据库大小（估算）
   * @returns 数据库大小（字节）
   */
  async getDatabaseSize(): Promise<number> {
    if (!this.isInitialized) {
      throw new Error('数据库未初始化');
    }

    try {
      const store: relationalStore.RdbStore = this.rdbManager.getRdbStore();

      // 统计各表数据量
      const postCount: number = await this.getTableCount(store, 'post_info');
      const commentCount: number = await this.getTableCount(store, 'comment_info');
      const categoryCount: number = await this.getTableCount(store, 'category_info');

      // 估算大小（每条记录约1KB）
      const estimatedSize: number = (postCount + commentCount + categoryCount) * 1024;

      return estimatedSize;
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DatabaseHelper] 获取数据库大小失败:', errorMsg);
      return 0;
    }
  }

  /**
   * 获取表数据量
   * @param store RdbStore实例
   * @param tableName 表名
   * @returns 数据量
   */
  /**
   * @throws
   */
  private async getTableCount(store: relationalStore.RdbStore, tableName: string): Promise<number> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(tableName);
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    const count: number = resultSet.rowCount;
    resultSet.close();
    return count;
  }

  /**
   * 获取数据库统计信息
   * @returns 统计信息
   */
  async getStatistics(): Promise<GeneratedTypeLiteralInterface_1> {
    if (!this.isInitialized) {
      throw new Error('数据库未初始化');
    }

    try {
      const store: relationalStore.RdbStore = this.rdbManager.getRdbStore();

      const postCount: number = await this.getTableCount(store, 'post_info');
      const commentCount: number = await this.getTableCount(store, 'comment_info');
      const categoryCount: number = await this.getTableCount(store, 'category_info');
      const dbSize: number = await this.getDatabaseSize();

      return {
        postCount: postCount,
        commentCount: commentCount,
        categoryCount: categoryCount,
        dbSize: dbSize
      };
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      console.error('[DatabaseHelper] 获取统计信息失败:', errorMsg);
      throw new Error('获取统计信息失败: ' + errorMsg);
    }
  }
}

export default DatabaseHelper;