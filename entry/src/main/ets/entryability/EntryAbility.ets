import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';
const MODEL_FILENAME: string = 'best_kirin.ms';

export default class EntryAbility extends UIAbility {
  private modelReady: Promise<void> = Promise.resolve();

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, 'Ability onCreate');

    this.modelReady = this.loadModelBuffer();
  }

  private async loadModelBuffer(): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Loading model from rawfile: %{public}s', MODEL_FILENAME);
      let resMgr: resourceManager.ResourceManager = this.context.resourceManager;
      if (!resMgr) {
        hilog.error(DOMAIN, TAG, 'Failed to get resourceManager, context may not be ready');
        AppStorage.setOrCreate('modelBuffer', new ArrayBuffer(0));
        return;
      }

      let fileData: Uint8Array = await resMgr.getRawFileContent(MODEL_FILENAME);
      if (!fileData || fileData.byteLength === 0) {
        hilog.error(DOMAIN, TAG, 'Model file %{public}s is empty or not found', MODEL_FILENAME);
        AppStorage.setOrCreate('modelBuffer', new ArrayBuffer(0));
        return;
      }

      hilog.info(DOMAIN, TAG, 'Model file size: %{public}d bytes', fileData.byteLength);

      let modelBuffer = fileData.buffer;
      if (!modelBuffer || modelBuffer.byteLength === 0) {
        hilog.error(DOMAIN, TAG, 'Model buffer is empty after extracting from file data');
        AppStorage.setOrCreate('modelBuffer', new ArrayBuffer(0));
        return;
      }

      AppStorage.setOrCreate('modelBuffer', modelBuffer);
      hilog.info(DOMAIN, TAG, 'Model buffer (%{public}d bytes) stored in AppStorage', modelBuffer.byteLength);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadModelBuffer failed: %{public}s', JSON.stringify(err));
      AppStorage.setOrCreate('modelBuffer', new ArrayBuffer(0));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    if (!windowStage) {
      hilog.error(DOMAIN, TAG, 'windowStage is null, cannot load content');
      return;
    }

    this.modelReady.then(() => {
      hilog.info(DOMAIN, TAG, 'Model ready, loading content');
      windowStage.loadContent('pages/Index', (err) => {
        if (err && err.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load the content. Code: %{public}d, Message: %{public}s',
            err.code, err.message);
          return;
        }
        hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');

        this.configureWindow(windowStage);
      });
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Model preparation failed: %{public}s', err.message);
      windowStage.loadContent('pages/Index', (loadErr) => {
        if (loadErr && loadErr.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load fallback content. Code: %{public}d, Message: %{public}s',
            loadErr.code, loadErr.message);
          return;
        }
        hilog.info(DOMAIN, TAG, 'Loaded fallback content (model may not be ready)');
      });
    });
  }

  private configureWindow(windowStage: window.WindowStage): void {
    try {
      let windowClass: window.Window | undefined = windowStage.getMainWindowSync();
      if (!windowClass) {
        hilog.error(DOMAIN, TAG, 'getMainWindowSync returned null');
        return;
      }

      windowClass.setWindowLayoutFullScreen(true).then(() => {
        hilog.info(DOMAIN, TAG, 'Succeeded in setting window layout full screen');
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'Failed to set window layout full screen. Cause: %{public}s', err.message);
      });

      let systemBarProperties: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
        navigationBarColor: '#00000000',
        navigationBarContentColor: '#FFFFFF',
        isStatusBarLightIcon: false,
        isNavigationBarLightIcon: false
      };
      windowClass.setWindowSystemBarProperties(systemBarProperties).then(() => {
        hilog.info(DOMAIN, TAG, 'Succeeded in setting window system bar properties');
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG,
          'Failed to set window system bar properties. Cause: %{public}s', err.message);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'configureWindow failed: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
