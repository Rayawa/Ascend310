import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { YoloModel } from '../model/YoloModel';
import { CLASS_COLORS, CLASS_NAMES, DetectionBox, MODEL_INPUT_SIZE } from '../model/DetectionType';

@Entry
@Component
struct Index {
  @State displayPixelMap: PixelMap | undefined = undefined;
  @State isProcessing: boolean = false;
  @State tipText: string = '正在加载模型...';
  @State boxList: DetectionBox[] = [];
  @State selectedStats: Map<number, number> = new Map();
  @State canvasSize: number = 360;
  @State modelReady: boolean = false;

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private canvasReady: boolean = false;
  private yoloModel: YoloModel = new YoloModel();

  aboutToAppear(): void {
    console.info('[Index] aboutToAppear called');
    this.initEngine().catch((err: Error) => {
      console.error('[Index] initEngine failed in aboutToAppear: ' + err.message);
    });
  }

  private async initEngine(): Promise<void> {
    try {
      let modelBuffer: ArrayBuffer | undefined = AppStorage.get<ArrayBuffer>('modelBuffer');
      if (!modelBuffer) {
        console.error('[Index] initEngine: modelBuffer is undefined, AppStorage.get returned null');
        this.tipText = '模型文件未加载，请检查rawfile中是否存在best_kirin.ms';
        this.modelReady = false;
        return;
      }

      console.info('[Index] initEngine: modelBuffer size=' + modelBuffer.byteLength.toString() + ' bytes');

      if (modelBuffer.byteLength === 0) {
        console.error('[Index] initEngine: modelBuffer is empty (0 bytes), rawfile loading may have failed');
        this.tipText = '模型文件为空，请检查rawfile中best_kirin.ms是否有效';
        this.modelReady = false;
        return;
      }

      this.tipText = '正在初始化推理引擎...';
      console.info('[Index] initEngine: starting MindSpore Lite engine initialization...');

      let engineReady: boolean = await this.yoloModel.init(modelBuffer);
      console.info('[Index] initEngine: engine initialization result=' + engineReady.toString());

      if (engineReady) {
        this.tipText = '引擎就绪，请选择X光图片';
        this.modelReady = true;
        console.info('[Index] initEngine: engine initialized successfully');
      } else {
        this.tipText = '引擎初始化失败，请检查模型文件格式';
        this.modelReady = false;
        console.error('[Index] initEngine: engine initialization returned false');
      }
    } catch (err) {
      let errorMsg: string = '';
      if (err instanceof Error) {
        errorMsg = err.message;
      } else if (typeof err === 'string') {
        errorMsg = err;
      } else {
        errorMsg = JSON.stringify(err);
      }
      console.error('[Index] initEngine exception: ' + errorMsg);
      this.tipText = '引擎初始化异常: ' + errorMsg;
      this.modelReady = false;
    }
  }

  async selectAndProcessImage(): Promise<void> {
    if (this.isProcessing) {
      console.info('[Index] selectAndProcessImage: already processing, ignoring');
      return;
    }

    console.info('[Index] selectAndProcessImage: opening photo picker...');
    this.isProcessing = true;

    let file: fs.File | null = null;
    let imageSource: image.ImageSource | undefined = undefined;
    let displayPixelMap: image.PixelMap | undefined = undefined;
    let scaledPixelMap: image.PixelMap | undefined = undefined;

    try {
      let photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      let photoSelectOptions: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      let result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(photoSelectOptions);
      if (!result || result.photoUris.length === 0) {
        console.info('[Index] selectAndProcessImage: user cancelled photo selection');
        this.tipText = '未选择图片';
        this.isProcessing = false;
        return;
      }

      let imageUri: string = result.photoUris[0];
      console.info('[Index] selectAndProcessImage: selected image URI: ' + imageUri);

      this.tipText = '正在加载图片...';

      file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      console.info('[Index] selectAndProcessImage: file opened, fd=' + file.fd.toString());

      imageSource = image.createImageSource(file.fd);
      if (!imageSource) {
        console.error('[Index] selectAndProcessImage: createImageSource returned null');
        this.tipText = '图片源创建失败，文件可能损坏';
        this.isProcessing = false;
        return;
      }

      displayPixelMap = await imageSource.createPixelMap();
      if (!displayPixelMap) {
        console.error('[Index] selectAndProcessImage: createPixelMap returned null');
        this.tipText = '图片解码失败，请尝试其他图片';
        this.isProcessing = false;
        return;
      }

      this.displayPixelMap = displayPixelMap;
      console.info('[Index] selectAndProcessImage: display pixel map created');

      let imageInfo: image.ImageInfo = await displayPixelMap.getImageInfo();
      let origW: number = imageInfo.size.width;
      let origH: number = imageInfo.size.height;
      console.info('[Index] selectAndProcessImage: original image size=' + origW.toString() + 'x' + origH.toString());

      let scale: number = Math.min(MODEL_INPUT_SIZE / origW, MODEL_INPUT_SIZE / origH);
      let newW: number = Math.round(origW * scale);
      let newH: number = Math.round(origH * scale);
      let padX: number = Math.round((MODEL_INPUT_SIZE - newW) / 2);
      let padY: number = Math.round((MODEL_INPUT_SIZE - newH) / 2);
      console.info('[Index] selectAndProcessImage: scaled to ' + newW.toString() + 'x' + newH.toString() +
        ', padding offset=(' + padX.toString() + ',' + padY.toString() + ')');

      this.tipText = '正在预处理图片...';

      scaledPixelMap = await imageSource.createPixelMap({
        desiredSize: { width: newW, height: newH },
        editable: true,
      });
      if (!scaledPixelMap) {
        console.error('[Index] selectAndProcessImage: createPixelMap(scaled) returned null');
        this.tipText = '图片缩放失败';
        this.isProcessing = false;
        return;
      }

      let scaledBuffer: ArrayBuffer = new ArrayBuffer(newW * newH * 4);
      await scaledPixelMap.readPixelsToBuffer(scaledBuffer);
      let scaledPixels: Uint8Array = new Uint8Array(scaledBuffer);
      console.info('[Index] selectAndProcessImage: scaled pixels read, ' + scaledPixels.byteLength.toString() + ' bytes');

      let expectedSize: number = MODEL_INPUT_SIZE * MODEL_INPUT_SIZE * 4;
      let rgbaBuffer: ArrayBuffer = new ArrayBuffer(expectedSize);
      let rgbaView: Uint8Array = new Uint8Array(rgbaBuffer);

      for (let i: number = 0; i < MODEL_INPUT_SIZE * MODEL_INPUT_SIZE; i++) {
        rgbaView[i * 4 + 0] = 114;
        rgbaView[i * 4 + 1] = 114;
        rgbaView[i * 4 + 2] = 114;
        rgbaView[i * 4 + 3] = 255;
      }

      for (let row: number = 0; row < newH; row++) {
        let srcOffset: number = row * newW * 4;
        let dstOffset: number = ((padY + row) * MODEL_INPUT_SIZE + padX) * 4;
        for (let col: number = 0; col < newW; col++) {
          rgbaView[dstOffset + col * 4] = scaledPixels[srcOffset + col * 4];
          rgbaView[dstOffset + col * 4 + 1] = scaledPixels[srcOffset + col * 4 + 1];
          rgbaView[dstOffset + col * 4 + 2] = scaledPixels[srcOffset + col * 4 + 2];
          rgbaView[dstOffset + col * 4 + 3] = scaledPixels[srcOffset + col * 4 + 3];
        }
      }

      console.info('[Index] selectAndProcessImage: letterbox padding complete');

      if (file) {
        fs.closeSync(file);
        file = null;
        console.info('[Index] selectAndProcessImage: file closed');
      }

      if (!this.yoloModel.isModelReady()) {
        console.info('[Index] selectAndProcessImage: model not ready, retrying init...');
        this.tipText = '模型未就绪，正在重新加载...';
        await this.initEngine();
        if (!this.modelReady) {
          console.error('[Index] selectAndProcessImage: model re-init failed, aborting inference');
          this.tipText = '模型加载失败，请重启应用';
          this.isProcessing = false;
          return;
        }
      }

      await this.doInference(rgbaBuffer);
    } catch (err) {
      let errorMsg: string = '';
      if (err instanceof Error) {
        errorMsg = err.message;
      } else if (typeof err === 'string') {
        errorMsg = err;
      } else {
        errorMsg = JSON.stringify(err);
      }
      console.error('[Index] selectAndProcessImage exception: ' + errorMsg);
      this.tipText = '图片处理失败: ' + errorMsg;
      this.isProcessing = false;
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
          console.info('[Index] selectAndProcessImage: file closed in finally');
        } catch (closeErr) {
          console.error('[Index] selectAndProcessImage: failed to close file in finally: ' + JSON.stringify(closeErr));
        }
      }
    }
  }

  async doInference(buffer: ArrayBuffer): Promise<void> {
    this.isProcessing = true;
    this.tipText = 'MindSpore Lite 正在推理中...';

    try {
      console.info('[Index] doInference: starting inference, buffer size=' + buffer.byteLength.toString() + ' bytes');

      if (!this.yoloModel.isModelReady()) {
        console.error('[Index] doInference: model not ready, cannot run inference');
        this.tipText = '模型未就绪，推理失败';
        this.boxList = [];
        this.isProcessing = false;
        return;
      }

      this.boxList = await this.yoloModel.runInference(buffer);

      let detectionCount: number = this.boxList.length;
      console.info('[Index] doInference: inference complete, ' + detectionCount.toString() + ' detections');
      this.tipText = '检测完成，发现 ' + detectionCount.toString() + ' 个目标';

      this.drawBoxes();
    } catch (err) {
      let errorMsg: string = '';
      if (err instanceof Error) {
        errorMsg = err.message;
      } else if (typeof err === 'string') {
        errorMsg = err;
      } else {
        errorMsg = JSON.stringify(err);
      }
      console.error('[Index] doInference exception: ' + errorMsg);
      this.tipText = '推理出错: ' + errorMsg;
      this.boxList = [];
    } finally {
      this.isProcessing = false;
    }
  }

  drawBoxes(): void {
    if (!this.canvasReady) {
      console.info('[Index] drawBoxes: canvas not ready, will draw later');
      return;
    }

    try {
      this.canvasContext.clearRect(0, 0, this.canvasSize, this.canvasSize);
      console.info('[Index] drawBoxes: drawing ' + this.boxList.length.toString() + ' boxes');

      let stats: Map<number, number> = new Map();
      for (let i: number = 0; i < this.boxList.length; i++) {
        let box: DetectionBox = this.boxList[i];
        let rx: number = box.x * this.canvasSize;
        let ry: number = box.y * this.canvasSize;
        let rw: number = box.width * this.canvasSize;
        let rh: number = box.height * this.canvasSize;

        if (rw <= 0 || rh <= 0) {
          console.info('[Index] drawBoxes: skipping box ' + i.toString() + ' with invalid size');
          continue;
        }

        let colorIdx: number = box.classId;
        if (colorIdx < 0 || colorIdx >= CLASS_COLORS.length) {
          console.info('[Index] drawBoxes: invalid classId ' + colorIdx.toString() + ', defaulting to 0');
          colorIdx = 0;
        }
        let strokeColor: string = CLASS_COLORS[colorIdx];

        let count: number = stats.get(box.classId) ?? 0;
        stats.set(box.classId, count + 1);

        this.canvasContext.strokeStyle = strokeColor;
        this.canvasContext.lineWidth = 3;
        this.canvasContext.strokeRect(rx, ry, rw, rh);

        let labelText: string = box.label + ' ' + (box.confidence * 100).toFixed(1) + '%';
        this.canvasContext.font = 'bold 13px sans-serif';
        let textWidth: number = this.canvasContext.measureText(labelText).width;

        let labelY: number = ry - 20;
        if (labelY < 0) {
          labelY = ry;
        }

        this.canvasContext.fillStyle = strokeColor;
        this.canvasContext.fillRect(rx, labelY, textWidth + 10, 20);

        this.canvasContext.fillStyle = '#FFFFFF';
        this.canvasContext.fillText(labelText, rx + 5, labelY + 15);
      }
      this.selectedStats = stats;
      console.info('[Index] drawBoxes: drawing complete');
    } catch (err) {
      let errorMsg: string = '';
      if (err instanceof Error) {
        errorMsg = err.message;
      } else if (typeof err === 'string') {
        errorMsg = err;
      } else {
        errorMsg = JSON.stringify(err);
      }
      console.error('[Index] drawBoxes exception: ' + errorMsg);
    }
  }

  getTotalDetected(): number {
    let total: number = 0;
    let keys: number[] = Array.from(this.selectedStats.keys());
    for (let i: number = 0; i < keys.length; i++) {
      total += this.selectedStats.get(keys[i]) ?? 0;
    }
    return total;
  }

  getClassCount(classId: number): number {
    return this.selectedStats.get(classId) ?? 0;
  }

  build() {
    Navigation() {
      Scroll() {
        Row() {
          Column() {
            Stack() {
              if (this.displayPixelMap) {
                Image(this.displayPixelMap)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
              } else {
                SymbolGlyph($r('sys.symbol.camera'))
                  .fontSize(64)
                  .fontColor(['#CCCCCC'])
                  .width('100%')
                  .height('100%')
              }
              Canvas(this.canvasContext)
                .width('100%')
                .height('100%')
                .onReady(() => {
                  this.canvasReady = true;
                  this.drawBoxes();
                })
            }
            .width(this.canvasSize)
            .height(this.canvasSize)
            .alignContent(Alignment.Center)
            .borderRadius(16)
            .clip(true)
            .shadow({ radius: 16, color: '#20000000', offsetY: 4 })

            Button(this.isProcessing ? '推理中...' : '选择X光图片')
              .width('100%').height(56).borderRadius(28).margin({ top: 20 })
              .onClick(() => this.selectAndProcessImage())
              .enabled(!this.isProcessing && this.modelReady)
          }
          .width('35%').padding(24)

          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.info_circle')).fontSize(20).fontColor(['#667eea'])
              Text(this.tipText).fontSize(16).margin({ left: 12 })
            }
            .width('100%').padding(16).backgroundColor('#F0F4FF').borderRadius(12).margin({ bottom: 20 })

            Column() {
              Text('检测统计').fontSize(18).fontWeight(FontWeight.Bold).margin({ bottom: 12 })
              ForEach(CLASS_NAMES, (name: string, index: number) => {
                this.ClassLegend(name, index < CLASS_COLORS.length ? CLASS_COLORS[index] : '#999999', index)
              })
            }
            .width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(16)
          }
          .width('30%').padding(24)

          Column() {
            Text('检测记录').fontSize(18).fontWeight(FontWeight.Bold).margin({ bottom: 12 })
            if (this.boxList.length > 0) {
              Grid() {
                ForEach(this.boxList, (box: DetectionBox, index: number) => {
                  GridItem() { this.ResultItem(box, index) }
                })
              }
              .columnsTemplate('1fr 1fr')
              .width('100%')
            } else {
              Text('暂无检测数据').fontColor('#999999').margin({ top: 40 })
            }
          }
          .width('35%').padding(24)
        }
        .alignItems(VerticalAlign.Top)
      }
      .width("100%").height("100%")
    }
    .titleMode(NavigationTitleMode.Full)
    .width("100%")
    .title('X-Ray AI检测')
    .mode(NavigationMode.Stack)
  }

  @Builder
  ClassLegend(name: string, color: string, index: number) {
    Row() {
      SymbolGlyph($r('sys.symbol.square_fill')).fontSize(16).fontColor([color])
      Text(name).fontSize(14).margin({ left: 10 }).layoutWeight(1)
      Text(this.getClassCount(index).toString()).fontWeight(FontWeight.Bold).fontColor(color)
    }
    .width('100%').padding(10)
  }

  @Builder
  ResultItem(box: DetectionBox, index: number) {
    Column() {
      Text(box.label).fontWeight(FontWeight.Bold)
      Text((box.confidence * 100).toFixed(1) + '%').fontSize(12)
    }
    .width('100%').padding(12).backgroundColor('#FFFFFF').borderRadius(12)
  }
}
