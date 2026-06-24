import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { resourceManager } from '@kit.LocalizationKit';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';
const MODEL_FILENAME = 'best.om';

export default class EntryAbility extends UIAbility {
  private modelReady: Promise<void> = Promise.resolve();

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, 'Ability onCreate');

    this.modelReady = this.copyModelToSandbox();
  }

  private async copyModelToSandbox(): Promise<void> {
    try {
      let filesDir = this.context.filesDir;
      let modelPath = filesDir + '/' + MODEL_FILENAME;

      try {
        if (fs.accessSync(modelPath)) {
          hilog.info(DOMAIN, TAG, 'Model already exists at %{public}s', modelPath);
          AppStorage.setOrCreate('modelPath', modelPath);
          return;
        }
      } catch (err) {
        hilog.info(DOMAIN, TAG, 'Model file not exist, will copy from rawfile');
      }

      hilog.info(DOMAIN, TAG, 'Copying model from rawfile...');
      let resMgr: resourceManager.ResourceManager = this.context.resourceManager;
      let fileData: Uint8Array = await resMgr.getRawFileContent(MODEL_FILENAME);

      hilog.info(DOMAIN, TAG, 'Model file size: %{public}d bytes', fileData.byteLength);

      let file = fs.openSync(modelPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, fileData.buffer);
      fs.closeSync(file);

      hilog.info(DOMAIN, TAG, 'Model copied to %{public}s', modelPath);
      AppStorage.setOrCreate('modelPath', modelPath);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'copyModelToSandbox failed: %{public}s', JSON.stringify(err));
      AppStorage.setOrCreate('modelPath', '');
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    this.modelReady.then(() => {
      hilog.info(DOMAIN, TAG, 'Model ready, loading content');
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
        
        try {
          let windowClass = windowStage.getMainWindowSync();
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
            hilog.error(DOMAIN, TAG, 'Failed to set window system bar properties. Cause: %{public}s', err.message);
          });
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'Failed to get main window. Cause: %{public}s', JSON.stringify(err));
        }
      });
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Model preparation failed: %{public}s', err.message);
      windowStage.loadContent('pages/Index', (loadErr) => {
        if (loadErr.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(loadErr));
        }
      });
    });
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
