// entry/src/main/ets/common/SessionManager.ets
import { common } from '@kit.AbilityKit';
import { distributedApi } from '../api/DistributedApi';
import { CloudCredential, CloudCredentialStore } from './CloudCredentialStore';

export class SessionManager {

  private static getContext(): common.Context {
    const maybeCtx: common.Context | undefined = AppStorage.get<common.Context>('uiAbilityContext');
    if (maybeCtx === undefined) {
      throw new Error('uiAbilityContext not found');
    }
    return maybeCtx;
  }

  static async saveCredentials(username: string, password: string): Promise<void> {
    try {
      await CloudCredentialStore.save(SessionManager.getContext(), username, password);
      console.info('[SessionManager] 登录信息已保存');
    } catch (err) {
      console.error('[SessionManager] 保存失败:', (err as Error).message);
    }
  }

  static async getSavedCredentials(): Promise<CloudCredential | null> {
    try {
      return await CloudCredentialStore.get(SessionManager.getContext());
    } catch (err) {
      console.error('[SessionManager] 读取失败:', (err as Error).message);
      return null;
    }
  }

  static async clearCredentials(): Promise<void> {
    try {
      await CloudCredentialStore.clear(SessionManager.getContext());
      console.info('[SessionManager] 登录信息已清除');
    } catch (err) {
      console.error('[SessionManager] 清除失败:', (err as Error).message);
    }
  }

  static async autoLogin(syncAfterLogin: boolean = true): Promise<boolean> {
    try {
      const creds: CloudCredential | null = await SessionManager.getSavedCredentials();
      if (creds === null) return false;
      const result = await distributedApi.login(creds.username, creds.password, syncAfterLogin);
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
