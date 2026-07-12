// common/LikedCache.ts
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'PhotoLikedCache';

class LikedCacheImpl {
  private currentUser: string = '';
  private memoryCache: string[] = [];

  setCurrentUser(username: string): void {
    if (this.currentUser !== username) {
      console.info('[LikedCache] 切换用户: "' + this.currentUser + '" -> "' + username + '"');
      this.currentUser = username;
      this.memoryCache = [];
    }
  }

  getCurrentUser(): string {
    return this.currentUser;
  }

  private getStore(): preferences.Preferences {
    const context: common.Context =
      AppStorage.get<common.Context>('globalAbilityContext') as common.Context;
    const options: preferences.Options = { name: STORE_NAME };
    return preferences.getPreferencesSync(context, options);
  }

  private getKey(): string {
    return 'liked_' + (this.currentUser || 'NO_USER');
  }

  /** 启动时从 Preferences 读取缓存的点赞列表 */
  async loadFromStorage(): Promise<string[]> {
    if (this.memoryCache.length > 0) {
      return this.memoryCache;
    }
    if (!this.currentUser || this.currentUser.length === 0) {
      return [];
    }
    try {
      const store = this.getStore();
      const key = this.getKey();
      if (store.hasSync(key)) {
        const jsonStr: string = store.getSync(key, '[]') as string;
        const parsed: string[] = JSON.parse(jsonStr) as string[];
        this.memoryCache = parsed;
        return parsed;
      }
    } catch (e) {
      console.warn('[LikedCache] loadFromStorage error:', (e as Error).message);
    }
    return [];
  }

  /** 从 PostLikedInfo 数组提取当前用户已点赞的 postId */
  extractFromFeed(likeData: PostLikedInfo[]): void {
    const ids: string[] = [];
    for (let i = 0; i < likeData.length; i++) {
      if (likeData[i].isLiked) {
        ids.push(likeData[i].postId);
      }
    }
    this.memoryCache = ids;
    this.persistToStorage();
  }

  /** 获取缓存的点赞列表 */
  getLikedIds(): string[] {
    return this.memoryCache;
  }

  /** 添加到内存缓存（点赞后调用） */
  addToMemory(postId: string): void {
    for (let i = 0; i < this.memoryCache.length; i++) {
      if (this.memoryCache[i] === postId) return;
    }
    this.memoryCache.push(postId);
    this.persistToStorage();
  }

  /** 从内存缓存移除（取消点赞后调用） */
  removeFromMemory(postId: string): void {
    const newIds: string[] = [];
    for (let i = 0; i < this.memoryCache.length; i++) {
      if (this.memoryCache[i] !== postId) {
        newIds.push(this.memoryCache[i]);
      }
    }
    this.memoryCache = newIds;
    this.persistToStorage();
  }

  /** 持久化到 Preferences */
  private persistToStorage(): void {
    try {
      const store = this.getStore();
      store.putSync(this.getKey(), JSON.stringify(this.memoryCache));
      store.flush();
    } catch (e) {
      console.warn('[LikedCache] persistToStorage error:', (e as Error).message);
    }
  }

  /** 清除内存缓存（退出登录时调用） */
  clearMemory(): void {
    this.memoryCache = [];
  }
}

/** feed 数据中的点赞信息（用于 extractFromFeed） */
export interface PostLikedInfo {
  postId: string;
  isLiked: boolean;
}

export const LikedCache = new LikedCacheImpl();