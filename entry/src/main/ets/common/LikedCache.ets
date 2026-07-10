// entry/src/main/ets/common/LikedCache.ets
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREF_NAME: string = 'liked_cache';
const KEY_IDS: string = 'liked_post_ids';

export class LikedCache {

  private static async getPrefs(): Promise<preferences.Preferences> {
    const maybeCtx: common.Context | undefined = AppStorage.get<common.Context>('uiAbilityContext');
    if (maybeCtx === undefined) {
      throw new Error('uiAbilityContext not found');
    }
    return await preferences.getPreferences(maybeCtx, PREF_NAME);
  }

  static async getLikedIds(): Promise<string[]> {
    try {
      const prefs: preferences.Preferences = await LikedCache.getPrefs();
      const value: string = await prefs.get(KEY_IDS, '') as string;
      if (value.length === 0) {
        return [];
      }
      const result: string[] = [];
      const parts: string[] = value.split(',');
      for (let i = 0; i < parts.length; i++) {
        if (parts[i].length > 0) {
          result.push(parts[i]);
        }
      }
      return result;
    } catch (err) {
      console.error('[LikedCache] 读取失败:', (err as Error).message);
      return [];
    }
  }

  static async addLikedId(postId: string): Promise<void> {
    try {
      const ids: string[] = await LikedCache.getLikedIds();
      let found: boolean = false;
      for (let i = 0; i < ids.length; i++) {
        if (ids[i] === postId) {
          found = true;
          break;
        }
      }
      if (!found) {
        ids.push(postId);
        await LikedCache.saveIds(ids);
      }
    } catch (err) {
      console.error('[LikedCache] 添加失败:', (err as Error).message);
    }
  }

  static async removeLikedId(postId: string): Promise<void> {
    try {
      const ids: string[] = await LikedCache.getLikedIds();
      const newIds: string[] = [];
      for (let i = 0; i < ids.length; i++) {
        if (ids[i] !== postId) {
          newIds.push(ids[i]);
        }
      }
      await LikedCache.saveIds(newIds);
    } catch (err) {
      console.error('[LikedCache] 删除失败:', (err as Error).message);
    }
  }

  static async clearAll(): Promise<void> {
    try {
      const prefs: preferences.Preferences = await LikedCache.getPrefs();
      await prefs.put(KEY_IDS, '');
      await prefs.flush();
    } catch (err) {
      console.error('[LikedCache] 清除失败:', (err as Error).message);
    }
  }

  private static async saveIds(ids: string[]): Promise<void> {
    let text: string = '';
    for (let i = 0; i < ids.length; i++) {
      if (i > 0) text += ',';
      text += ids[i];
    }
    const prefs: preferences.Preferences = await LikedCache.getPrefs();
    await prefs.put(KEY_IDS, text);
    await prefs.flush();
  }
}