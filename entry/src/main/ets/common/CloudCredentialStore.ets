import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREF_NAME: string = 'session_pref';
const KEY_USERNAME: string = 'username';
const KEY_PASSWORD: string = 'password';

export class CloudCredential {
  username: string = '';
  password: string = '';
}

export class CloudCredentialStore {
  private static async getPrefs(context: common.Context): Promise<preferences.Preferences> {
    return await preferences.getPreferences(context, PREF_NAME);
  }

  static async save(context: common.Context, username: string, password: string): Promise<void> {
    const prefs: preferences.Preferences = await CloudCredentialStore.getPrefs(context);
    await prefs.put(KEY_USERNAME, username);
    await prefs.put(KEY_PASSWORD, password);
    await prefs.flush();
  }

  static async get(context: common.Context): Promise<CloudCredential | null> {
    const prefs: preferences.Preferences = await CloudCredentialStore.getPrefs(context);
    const username: string = await prefs.get(KEY_USERNAME, '') as string;
    const password: string = await prefs.get(KEY_PASSWORD, '') as string;
    if (username.length === 0 || password.length === 0) {
      return null;
    }

    const credential: CloudCredential = new CloudCredential();
    credential.username = username;
    credential.password = password;
    return credential;
  }

  static async clear(context: common.Context): Promise<void> {
    const prefs: preferences.Preferences = await CloudCredentialStore.getPrefs(context);
    await prefs.delete(KEY_USERNAME);
    await prefs.delete(KEY_PASSWORD);
    await prefs.flush();
  }
}
