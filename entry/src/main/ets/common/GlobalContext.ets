import { common } from '@kit.AbilityKit';

/**
 * 全局上下文管理类
 * 用于存储和获取全局状态
 */
export class GlobalContext {
  private static instance: GlobalContext | null = null;
  private context: common.UIAbilityContext | null = null;
  private store: Map<string, Object> = new Map<string, Object>();

  /**
   * 私有构造函数（单例模式）
   */
  private constructor() {}

  /**
   * 获取单例实例
   * @returns GlobalContext实例
   */
  static getInstance(): GlobalContext {
    if (GlobalContext.instance === null) {
      GlobalContext.instance = new GlobalContext();
    }
    return GlobalContext.instance;
  }

  /**
   * 设置UIAbility上下文
   * @param context UIAbility上下文
   */
  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 获取UIAbility上下文
   * @returns UIAbility上下文
   */
  getContext(): common.UIAbilityContext {
    if (this.context === null) {
      throw new Error('上下文未初始化，请在Ability初始化时调用setContext');
    }
    return this.context;
  }

  /**
   * 存储全局数据
   * @param key 键名
   * @param value 值
   */
  set(key: string, value: Object): void {
    this.store.set(key, value);
  }

  /**
   * 获取全局数据
   * @param key 键名
   * @returns 值，不存在则返回null
   */
  get(key: string): Object | null {
    const value: Object | undefined = this.store.get(key);
    return value !== undefined ? value : null;
  }

  /**
   * 获取全局数据（指定类型）
   * @param key 键名
   * @returns 值
   */
  getValue<T>(key: string): T | null {
    const value: Object | undefined = this.store.get(key);
    return value !== undefined ? (value as T) : null;
  }

  /**
   * 删除全局数据
   * @param key 键名
   * @returns 是否删除成功
   */
  delete(key: string): boolean {
    return this.store.delete(key);
  }

  /**
   * 检查是否存在指定键
   * @param key 键名
   * @returns 是否存在
   */
  has(key: string): boolean {
    return this.store.has(key);
  }

  /**
   * 清空所有全局数据
   */
  clear(): void {
    this.store.clear();
  }

  /**
   * 获取应用文件目录
   * @returns 文件目录路径
   */
  getFilesDir(): string {
    return this.getContext().filesDir;
  }

  /**
   * 获取应用缓存目录
   * @returns 缓存目录路径
   */
  getCacheDir(): string {
    return this.getContext().cacheDir;
  }

  /**
   * 获取应用临时目录
   * @returns 临时目录路径
   */
  getTempDir(): string {
    return this.getContext().tempDir;
  }
}

export default GlobalContext;