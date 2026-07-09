import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { DistributedService } from '../service/DistributedService';
import { AIClassifyService } from '../service/AIClassifyService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    DistributedService.getInstance().release().catch(() => {});
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // ✅ 先加载页面（必须在 async 操作之前）
    windowStage.loadContent('pages/TestPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', '❌ 加载失败: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', '✅ 页面加载成功');
    });

    // ✅ 后台初始化（不要阻塞页面加载）
    this.initializeApplication().catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', '❌ 初始化失败: %{public}s', err.message);
    });
  }

  private async initializeApplication(): Promise<void> {
    try {
      AppStorage.setOrCreate<object>('uiAbilityContext', this.context);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'AppStorage 存储失败: %{public}s', (err as Error).message);
    }

    try {
      await DistributedService.getInstance().init(this.context);
      hilog.info(DOMAIN, 'SocialPhotoSync', '%{public}s', 'Distributed sync initialized');
    } catch (err) {
      hilog.error(DOMAIN, 'SocialPhotoSync', 'Distributed sync init failed: %{public}s',
        (err as Error).message);
    }

    try {
      await AIClassifyService.getInstance().preloadModel(this.context);
      hilog.info(DOMAIN, 'SocialPhotoAI', '%{public}s', 'AI model preloaded');
    } catch (err) {
      hilog.error(DOMAIN, 'SocialPhotoAI', 'AI model preload failed: %{public}s',
        (err as Error).message);
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}