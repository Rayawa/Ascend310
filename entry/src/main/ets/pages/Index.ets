import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { display } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import yoloEngine from 'libentry.so';
import { DetectionBox, CLASS_NAMES, CLASS_COLORS, MODEL_INPUT_SIZE } from '../model/DetectionType';

@Entry
@Component
struct Index {
  @State displayPixelMap: PixelMap | undefined = undefined;
  @State isProcessing: boolean = false;
  @State tipText: string = '请选择一张X光图片进行检测';
  @State boxList: DetectionBox[] = [];
  @State selectedStats: Map<number, number> = new Map();
  @State isTablet: boolean = false;
  @State canvasSize: number = 360;

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private canvasReady: boolean = false;

  async aboutToAppear(): Promise<void> {
    let displayInfo = display.getDefaultDisplaySync();
    let screenWidth = px2vp(displayInfo.width);
    this.isTablet = screenWidth > 600;
    this.canvasSize = this.isTablet ? 600 : 360;

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

  @Builder
  ResultItem(box: DetectionBox, index: number) {
    Row() {
      Row() {
        Text((index + 1).toString())
          .fontSize(12)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
      }
      .width(24)
      .height(24)
      .borderRadius(12)
      .backgroundColor(CLASS_COLORS[box.classId >= 0 && box.classId < CLASS_COLORS.length ? box.classId : 0])
      .justifyContent(FlexAlign.Center)
      .margin({ right: 12 })

      Column() {
        Text(box.label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .width('100%')

        Text('置信度: ' + (box.confidence * 100).toFixed(1) + '%')
          .fontSize(12)
          .fontColor('#888888')
          .margin({ top: 2 })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row() {
        Text((box.confidence * 100).toFixed(0))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(CLASS_COLORS[box.classId >= 0 && box.classId < CLASS_COLORS.length ? box.classId : 0])
        Text('%')
          .fontSize(12)
          .fontColor('#888888')
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .shadow({
      radius: 4,
      color: '#15000000',
      offsetX: 0,
      offsetY: 2
    })
    .margin({ bottom: 8 })
  }

  @Builder
  ClassLegend(name: string, color: string, index: number) {
    Row() {
      Row()
        .width(16)
        .height(16)
        .borderRadius(4)
        .backgroundColor(color)
        .margin({ right: 10 })

      Text(name)
        .fontSize(13)
        .fontColor('#555555')
        .layoutWeight(1)

      if (this.getClassCount(index) > 0) {
        Row() {
          Text(this.getClassCount(index).toString())
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(color)
        }
        .width(28)
        .height(20)
        .borderRadius(10)
        .backgroundColor(color + '20')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 12 })
    .borderRadius(8)
    .backgroundColor('#F8F9FA')
    .margin({ bottom: 6 })
  }

  @Builder
  HeaderSection() {
    Column() {
      Row() {
        Column() {
          Text('X-Ray Detection')
            .fontSize(this.isTablet ? 32 : 28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .letterSpacing(1)

          Text('YOLOv5s + Ascend 310B')
            .fontSize(this.isTablet ? 16 : 14)
            .fontColor('#FFFFFFCC')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Row() {
            Text('●')
              .fontSize(12)
              .fontColor('#44FF44')
            Text('就绪')
              .fontSize(12)
              .fontColor('#FFFFFF')
              .margin({ left: 4 })
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(12)
          .backgroundColor('#FFFFFF20')
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 32, bottom: 20 })
    }
    .width('100%')
    .linearGradient({
      angle: 135,
      colors: [['#667eea', 0.0], ['#764ba2', 1.0]]
    })
  }

  build() {
    Column() {
      this.HeaderSection()

      if (this.isTablet) {
        this.TabletLayout()
      } else {
        this.PhoneLayout()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TabletLayout() {
    Scroll() {
      Column() {
        Row() {
          Column() {
            this.ImageCanvasSection()
          }
          .layoutWeight(1)
          .padding({ right: 16 })

          Column() {
            this.ControlPanelSection()
            this.ClassLegendSection()
          }
          .width(320)
        }
        .width('92%')
        .alignItems(VerticalAlign.Top)

        if (this.boxList.length > 0) {
          this.ResultsSection()
        }
      }
      .width('100%')
      .padding({ top: 20, bottom: 32 })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#F5F7FA')
    .scrollBar(BarState.Off)
  }

  @Builder
  PhoneLayout() {
    Scroll() {
      Column() {
        Column() {
          Row() {
            Text('📷')
              .fontSize(16)
            Text(this.tipText)
              .fontSize(14)
              .fontColor('#666666')
              .margin({ left: 8 })
              .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .borderRadius(10)
          .backgroundColor('#F0F4FF')
          .margin({ bottom: 16 })
        }
        .width('92%')

        this.ImageCanvasSection()

        Column() {
          Button() {
            Row() {
              if (this.isProcessing) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color('#FFFFFF')
                  .margin({ right: 8 })
              } else {
                Text('📁')
                  .fontSize(18)
                  .margin({ right: 8 })
              }
              Text(this.isProcessing ? '推理中...' : '选择X光图片')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
          .height(50)
          .borderRadius(25)
          .enabled(!this.isProcessing)
          .linearGradient({
            angle: 90,
            colors: [['#667eea', 0.0], ['#764ba2', 1.0]]
          })
          .shadow({
            radius: 8,
            color: '#40667eea',
            offsetX: 0,
            offsetY: 4
          })
          .onClick(() => {
            this.selectAndProcessImage();
          })
        }
        .width('92%')
        .margin({ bottom: 24 })

        if (this.boxList.length > 0) {
          this.ResultsSection()
        }

        this.ClassLegendSection()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#F5F7FA')
    .scrollBar(BarState.Off)
  }

  @Builder
  ImageCanvasSection() {
    Column() {
      Stack() {
        if (this.displayPixelMap) {
          Image(this.displayPixelMap)
            .width(this.canvasSize)
            .height(this.canvasSize)
            .objectFit(ImageFit.Fill)
            .borderRadius(this.isTablet ? 16 : 12)
        } else {
          Column() {
            Text('🔬')
              .fontSize(this.isTablet ? 64 : 48)
              .margin({ bottom: 12 })
            Text('X-Ray Image')
              .fontSize(this.isTablet ? 18 : 16)
              .fontColor('#AAAAAA')
            Text('点击下方按钮选择图片')
              .fontSize(this.isTablet ? 14 : 12)
              .fontColor('#CCCCCC')
              .margin({ top: 4 })
          }
          .width(this.canvasSize)
          .height(this.canvasSize)
          .backgroundColor('#F5F7FA')
          .justifyContent(FlexAlign.Center)
          .borderRadius(this.isTablet ? 16 : 12)
        }

        Canvas(this.canvasContext)
          .width(this.canvasSize)
          .height(this.canvasSize)
          .onReady(() => {
            this.canvasReady = true;
            if (this.boxList.length > 0) {
              this.drawBoxes();
            }
          })
      }
      .width(this.canvasSize)
      .height(this.canvasSize)
      .borderRadius(this.isTablet ? 16 : 12)
      .clip(true)
      .shadow({
        radius: this.isTablet ? 16 : 12,
        color: '#20000000',
        offsetX: 0,
        offsetY: 4
      })
    }
    .margin({ bottom: this.isTablet ? 24 : 20 })
  }

  @Builder
  ControlPanelSection() {
    Column() {
      Column() {
        Row() {
          Text('📷')
            .fontSize(this.isTablet ? 18 : 16)
          Text(this.tipText)
            .fontSize(this.isTablet ? 15 : 14)
            .fontColor('#666666')
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding(this.isTablet ? 14 : 12)
        .borderRadius(10)
        .backgroundColor('#F0F4FF')
        .margin({ bottom: 16 })
      }
      .width('100%')

      Button() {
        Row() {
          if (this.isProcessing) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('#FFFFFF')
              .margin({ right: 8 })
          } else {
            Text('📁')
              .fontSize(this.isTablet ? 20 : 18)
              .margin({ right: 8 })
          }
          Text(this.isProcessing ? '推理中...' : '选择X光图片')
            .fontSize(this.isTablet ? 17 : 16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
        }
      }
      .width('100%')
      .height(this.isTablet ? 56 : 50)
      .borderRadius(this.isTablet ? 28 : 25)
      .enabled(!this.isProcessing)
      .linearGradient({
        angle: 90,
        colors: [['#667eea', 0.0], ['#764ba2', 1.0]]
      })
      .shadow({
        radius: this.isTablet ? 10 : 8,
        color: '#40667eea',
        offsetX: 0,
        offsetY: 4
      })
      .onClick(() => {
        this.selectAndProcessImage();
      })
    }
    .width('100%')
    .padding(16)
    .borderRadius(this.isTablet ? 16 : 12)
    .backgroundColor('#FFFFFF')
    .shadow({
      radius: 8,
      color: '#15000000',
      offsetX: 0,
      offsetY: 2
    })
    .margin({ bottom: 16 })
  }

  @Builder
  ClassLegendSection() {
    Column() {
      Row() {
        Text('类别说明')
          .fontSize(this.isTablet ? 17 : 16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)

        if (this.getTotalDetected() > 0) {
          Text('已检测 ' + this.getTotalDetected() + ' 个')
            .fontSize(this.isTablet ? 13 : 12)
            .fontColor('#888888')
        }
      }
      .width('100%')
      .margin({ bottom: this.isTablet ? 12 : 10 })

      ForEach(CLASS_NAMES, (name: string, index: number) => {
        this.ClassLegend(name, index < CLASS_COLORS.length ? CLASS_COLORS[index] : '#999999', index)
      }, (name: string, index: number) => index.toString())
    }
    .width(this.isTablet ? '100%' : '92%')
    .padding(this.isTablet ? 16 : 0)
    .borderRadius(this.isTablet ? 16 : 0)
    .backgroundColor(this.isTablet ? '#FFFFFF' : '#F5F7FA')
    .shadow(this.isTablet ? {
      radius: 8,
      color: '#15000000',
      offsetX: 0,
      offsetY: 2
    } : {
      radius: 0,
      color: '#00000000',
      offsetX: 0,
      offsetY: 0
    })
    .margin({ bottom: this.isTablet ? 16 : 32 })
  }

  @Builder
  ResultsSection() {
    Column() {
      Row() {
        Text('检测结果')
          .fontSize(this.isTablet ? 20 : 18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)

        Row() {
          Text('共 ')
            .fontSize(this.isTablet ? 15 : 14)
            .fontColor('#888888')
          Text(this.boxList.length.toString())
            .fontSize(this.isTablet ? 18 : 16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#667eea')
          Text(' 个目标')
            .fontSize(this.isTablet ? 15 : 14)
            .fontColor('#888888')
        }
      }
      .width('100%')
      .margin({ bottom: this.isTablet ? 14 : 12 })

      if (this.isTablet) {
        Grid() {
          ForEach(this.boxList, (box: DetectionBox, index: number) => {
            GridItem() {
              this.ResultItem(box, index)
            }
          }, (box: DetectionBox, index: number) => index.toString() + '_' + box.classId.toString() + '_' + box.confidence.toString())
        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsGap(8)
        .columnsGap(8)
        .width('100%')
      } else {
        ForEach(this.boxList, (box: DetectionBox, index: number) => {
          this.ResultItem(box, index)
        }, (box: DetectionBox, index: number) => index.toString() + '_' + box.classId.toString() + '_' + box.confidence.toString())
      }
    }
    .width(this.isTablet ? '92%' : '92%')
    .padding(this.isTablet ? 16 : 0)
    .borderRadius(this.isTablet ? 16 : 0)
    .backgroundColor(this.isTablet ? '#FFFFFF' : '#F5F7FA')
    .shadow(this.isTablet ? {
      radius: 8,
      color: '#15000000',
      offsetX: 0,
      offsetY: 2
    } : {
      radius: 0,
      color: '#00000000',
      offsetX: 0,
      offsetY: 0
    })
    .margin({ bottom: this.isTablet ? 16 : 24 })
  }
}
