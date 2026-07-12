// common/SessionManager.ts
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREFS_NAME: string = 'SessionPrefs';
const KEY_USERNAME: string = 'login_username';
const KEY_PASSWORD: string = 'login_password';

class SessionManagerImpl {
  /**
   * 获取保存的用户名
   */
  async getSavedUsername(): Promise<string> {
    try {
      const context: common.Context =
        AppStorage.get<common.Context>('globalAbilityContext') as common.Context;
      const options: preferences.Options = { name: PREFS_NAME };
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, options);
      const username: string = prefs.getSync(KEY_USERNAME, '') as string;
      return username;
    } catch (e) {
      console.warn('[SessionManager] getSavedUsername 失败:', (e as Error).message);
      return '';
    }
  }

  /**
   * 获取保存的密码
   */
  async getSavedPassword(): Promise<string> {
    try {
      const context: common.Context =
        AppStorage.get<common.Context>('globalAbilityContext') as common.Context;
      const options: preferences.Options = { name: PREFS_NAME };
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, options);
      const password: string = prefs.getSync(KEY_PASSWORD, '') as string;
      return password;
    } catch (e) {
      console.warn('[SessionManager] getSavedPassword 失败:', (e as Error).message);
      return '';
    }
  }

  /**
   * 保存登录凭据
   */
  async saveCredentials(username: string, password: string): Promise<void> {
    try {
      const context: common.Context =
        AppStorage.get<common.Context>('globalAbilityContext') as common.Context;
      const options: preferences.Options = { name: PREFS_NAME };
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, options);
      prefs.putSync(KEY_USERNAME, username);
      prefs.putSync(KEY_PASSWORD, password);
      prefs.flush();
      // 同步写入 AppStorage
      AppStorage.set<string>(KEY_USERNAME, username);
      console.info('[SessionManager] 已保存凭据，用户名: ' + username);
    } catch (e) {
      console.warn('[SessionManager] saveCredentials 失败:', (e as Error).message);
    }
  }

  /**
   * 清除登录凭据
   */
  async clearCredentials(): Promise<void> {
    try {
      const context: common.Context =
        AppStorage.get<common.Context>('globalAbilityContext') as common.Context;
      const options: preferences.Options = { name: PREFS_NAME };
      const prefs: preferences.Preferences = preferences.getPreferencesSync(context, options);
      prefs.putSync(KEY_USERNAME, '');
      prefs.putSync(KEY_PASSWORD, '');
      prefs.flush();
      console.info('[SessionManager] 已清除凭据');
    } catch (e) {
      console.warn('[SessionManager] clearCredentials 失败:', (e as Error).message);
    }
  }

  /**
   * 自动登录：凭据存在则自动登录
   */
  // common/SessionManager.ts — autoLogin 方法

  async autoLogin(): Promise<boolean> {
    try {
      const username: string = await this.getSavedUsername();
      if (username.length === 0) {
        return false;
      }

      // ★ 写入 AppStorage 和 PersistentStorage
      AppStorage.set<string>('login_username', username);
      console.info('[SessionManager] 自动登录: ' + username);
      return true;
    } catch (e) {
      console.warn('[SessionManager] autoLogin 失败:', (e as Error).message);
      return false;
    }
  }
}

export const SessionManager = new SessionManagerImpl();