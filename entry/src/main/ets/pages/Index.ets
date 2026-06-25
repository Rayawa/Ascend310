import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import yoloEngine from 'libentry.so';
import { CLASS_COLORS, CLASS_NAMES, DetectionBox, MODEL_INPUT_SIZE } from '../model/DetectionType';

@Entry
@Component
struct Index {
  @State displayPixelMap: PixelMap | undefined = undefined;
  @State isProcessing: boolean = false;
  @State tipText: string = '请选择一张X光图片进行检测';
  @State boxList: DetectionBox[] = [];
  @State selectedStats: Map<number, number> = new Map();
  @State canvasSize: number = 360;

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private canvasReady: boolean = false;

  async aboutToAppear(): Promise<void> {
    let modelPath = AppStorage.get<string>('modelPath') ?? '';
    console.info('[Index] Model path from AppStorage: ' + modelPath);

    if (modelPath.length === 0) {
      this.tipText = '模型文件未就绪，请检查rawfile中是否存在best.om';
      console.error('[Index] Model path is empty');
      return;
    }

    try {
      this.tipText = '正在初始化推理引擎...';
      console.info('[Index] Starting engine initialization...');
      let engineReady = await yoloEngine.initYoloEngine(modelPath);
      console.info('[Index] Engine initialization result: ' + engineReady);
      if (engineReady) {
        this.tipText = '引擎就绪，请选择X光图片';
        console.info('[Index] Engine initialized successfully');
      } else {
        this.tipText = '引擎初始化失败，请检查模型文件格式';
        console.error('[Index] Engine initialization returned false');
      }
    } catch (err) {
      console.error('[Index] Engine initialization error:', err);
      let errorMsg = '';
      if (err instanceof Error) {
        errorMsg = err.message;
      } else if (typeof err === 'string') {
        errorMsg = err;
      } else {
        errorMsg = JSON.stringify(err);
      }
      this.tipText = '引擎初始化异常: ' + errorMsg;
      console.error('[Index] Error details: ' + errorMsg);
    }
  }

  async selectAndProcessImage(): Promise<void> {
    if (this.isProcessing) {
      return;
    }

    try {
      let photoPicker = new photoAccessHelper.PhotoViewPicker();
      let photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      let result = await photoPicker.select(photoSelectOptions);
      if (!result || result.photoUris.length === 0) {
        this.tipText = '未选择图片';
        return;
      }

      let imageUri = result.photoUris[0];
      console.info('[Index] Selected image URI: ' + imageUri);

      this.isProcessing = true;
      this.tipText = '正在加载图片...';

      let file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      console.info('[Index] File opened, fd: ' + file.fd);

      let imageSource = image.createImageSource(file.fd);
      if (!imageSource) {
        this.tipText = '图片源创建失败';
        fs.closeSync(file);
        this.isProcessing = false;
        return;
      }

      let decodingOptions: image.DecodingOptions = {
        desiredSize: { width: MODEL_INPUT_SIZE, height: MODEL_INPUT_SIZE },
        editable: true,
      };
      let preprocessedPixelMap = await imageSource.createPixelMap(decodingOptions);
      if (!preprocessedPixelMap) {
        this.tipText = '预处理图片创建失败';
        fs.closeSync(file);
        this.isProcessing = false;
        return;
      }

      let displayPixelMap = await imageSource.createPixelMap();
      if (!displayPixelMap) {
        this.tipText = '显示图片创建失败';
        fs.closeSync(file);
        this.isProcessing = false;
        return;
      }

      this.displayPixelMap = displayPixelMap;

      let rgbaBuffer = new ArrayBuffer(MODEL_INPUT_SIZE * MODEL_INPUT_SIZE * 4);
      await preprocessedPixelMap.readPixelsToBuffer(rgbaBuffer);

      fs.closeSync(file);
      console.info('[Index] File closed');

      await this.doInference(rgbaBuffer);
    } catch (err) {
      console.error('[Index] Image loading error: ' + JSON.stringify(err));
      this.tipText = '图片加载失败: ' + (err instanceof Error ? err.message : JSON.stringify(err));
      this.isProcessing = false;
    }
  }

  async doInference(buffer: ArrayBuffer): Promise<void> {
    this.isProcessing = true;
    this.tipText = '昇腾 310B 正在推理中...';

    try {
      this.boxList = await yoloEngine.runYoloInference(buffer, MODEL_INPUT_SIZE, MODEL_INPUT_SIZE);
      this.tipText = '检测完成，发现 ' + this.boxList.length.toString() + ' 个目标';
      this.drawBoxes();
    } catch (error) {
      this.tipText = '推理出错: ' + JSON.stringify(error);
      this.boxList = [];
    } finally {
      this.isProcessing = false;
    }
  }

  drawBoxes(): void {
    if (!this.canvasReady) {
      return;
    }
    this.canvasContext.clearRect(0, 0, this.canvasSize, this.canvasSize);

    let stats = new Map<number, number>();
    for (let i = 0; i < this.boxList.length; i++) {
      let box = this.boxList[i];
      let rx = box.x * this.canvasSize;
      let ry = box.y * this.canvasSize;
      let rw = box.width * this.canvasSize;
      let rh = box.height * this.canvasSize;

      let colorIdx = box.classId;
      if (colorIdx < 0 || colorIdx >= CLASS_COLORS.length) {
        colorIdx = 0;
      }
      let strokeColor = CLASS_COLORS[colorIdx];

      let count = stats.get(box.classId) ?? 0;
      stats.set(box.classId, count + 1);

      this.canvasContext.strokeStyle = strokeColor;
      this.canvasContext.lineWidth = 3;
      this.canvasContext.strokeRect(rx, ry, rw, rh);

      let labelText = box.label + ' ' + (box.confidence * 100).toFixed(1) + '%';
      this.canvasContext.font = 'bold 13px sans-serif';
      let textWidth = this.canvasContext.measureText(labelText).width;

      let labelY = ry - 20;
      if (labelY < 0) {
        labelY = ry;
      }

      this.canvasContext.fillStyle = strokeColor;
      this.canvasContext.fillRect(rx, labelY, textWidth + 10, 20);

      this.canvasContext.fillStyle = '#FFFFFF';
      this.canvasContext.fillText(labelText, rx + 5, labelY + 15);
    }
    this.selectedStats = stats;
  }

  getTotalDetected(): number {
    let total = 0;
    let keys = Array.from(this.selectedStats.keys());
    for (let i = 0; i < keys.length; i++) {
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
                  .width(this.canvasSize)
                  .height(this.canvasSize)
                  .objectFit(ImageFit.Fill)
              } else {
                SymbolGlyph($r('sys.symbol.camera'))
                  .fontSize(64)
                  .fontColor(['#CCCCCC'])
                  .width(this.canvasSize)
                  .height(this.canvasSize)
                  .backgroundColor('#F5F7FA')
              }

              Canvas(this.canvasContext)
                .width(this.canvasSize)
                .height(this.canvasSize)
                .onReady(() => { this.canvasReady = true; this.drawBoxes(); })
            }
            .alignContent(Alignment.Center)
            .borderRadius(16).clip(true).shadow({ radius: 16, color: '#20000000', offsetY: 4 })

            Button(this.isProcessing ? '推理中...' : '选择X光图片')
              .width('100%').height(56).borderRadius(28).margin({ top: 20 })
              .onClick(() => this.selectAndProcessImage())
              .enabled(!this.isProcessing)
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
