// entry/src/main/ets/common/SessionManager.ets
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { distributedApi } from '../api/DistributedApi';

const PREF_NAME: string = 'session_pref';
const KEY_USERNAME: string = 'username';
const KEY_PASSWORD: string = 'password';

export class SavedCredential {
  username: string = '';
  password: string = '';
}

export class SessionManager {

  private static async getPrefs(): Promise<preferences.Preferences> {
    const maybeCtx: common.Context | undefined = AppStorage.get<common.Context>('uiAbilityContext');
    if (maybeCtx === undefined) {
      throw new Error('uiAbilityContext not found');
    }
    return await preferences.getPreferences(maybeCtx, PREF_NAME);
  }

  static async saveCredentials(username: string, password: string): Promise<void> {
    try {
      const prefs: preferences.Preferences = await SessionManager.getPrefs();
      await prefs.put(KEY_USERNAME, username);
      await prefs.put(KEY_PASSWORD, password);
      await prefs.flush();
      console.info('[SessionManager] 登录信息已保存');
    } catch (err) {
      console.error('[SessionManager] 保存失败:', (err as Error).message);
    }
  }

  static async getSavedCredentials(): Promise<SavedCredential | null> {
    try {
      const prefs: preferences.Preferences = await SessionManager.getPrefs();
      const username: string = await prefs.get(KEY_USERNAME, '') as string;
      const password: string = await prefs.get(KEY_PASSWORD, '') as string;
      if (username.length > 0 && password.length > 0) {
        const cred: SavedCredential = new SavedCredential();
        cred.username = username;
        cred.password = password;
        return cred;
      }
      return null;
    } catch (err) {
      console.error('[SessionManager] 读取失败:', (err as Error).message);
      return null;
    }
  }

  static async clearCredentials(): Promise<void> {
    try {
      const prefs: preferences.Preferences = await SessionManager.getPrefs();
      await prefs.delete(KEY_USERNAME);
      await prefs.delete(KEY_PASSWORD);
      await prefs.flush();
      console.info('[SessionManager] 登录信息已清除');
    } catch (err) {
      console.error('[SessionManager] 清除失败:', (err as Error).message);
    }
  }

  static async autoLogin(): Promise<boolean> {
    try {
      const creds: SavedCredential | null = await SessionManager.getSavedCredentials();
      if (creds === null) return false;
      const result = await distributedApi.login(creds.username, creds.password);
      if (result.success) {
        console.info('[SessionManager] 自动登录成功');
        return true;
      }
      console.warn('[SessionManager] 自动登录失败:', result.message);
      return false;
    } catch (err) {
      console.error('[SessionManager] 自动登录异常:', (err as Error).message);
      return false;
    }
  }
}