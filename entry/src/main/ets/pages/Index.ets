import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import yoloEngine from 'libentry.so';
import { DetectionBox, CLASS_NAMES, CLASS_COLORS, MODEL_INPUT_SIZE } from '../model/DetectionType';

@Entry
@Component
struct Index {
  @State displayPixelMap: PixelMap | undefined = undefined;
  @State isProcessing: boolean = false;
  @State tipText: string = '请选择一张X光图片进行检测';
  @State engineReady: boolean = false;
  @State boxList: DetectionBox[] = [];

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private readonly CANVAS_SIZE: number = 360;
  private canvasReady: boolean = false;

  async aboutToAppear(): Promise<void> {
    let modelPath = AppStorage.get<string>('modelPath') ?? '';
    if (modelPath.length === 0) {
      this.tipText = '模型文件未就绪，请确认rawfile中存在.om文件';
      return;
    }
    try {
      this.engineReady = await yoloEngine.initYoloEngine(modelPath);
      if (this.engineReady) {
        this.tipText = '引擎就绪，请选择X光图片';
      } else {
        this.tipText = '引擎初始化失败';
      }
    } catch (err) {
      this.tipText = '引擎初始化异常: ' + JSON.stringify(err);
    }
  }

  async selectAndProcessImage(): Promise<void> {
    if (this.isProcessing) {
      return;
    }
    if (!this.engineReady) {
      this.tipText = '引擎未就绪，无法进行检测';
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

      this.isProcessing = true;
      this.tipText = '正在加载图片...';

      let imageSource = image.createImageSource(imageUri);

      let decodingOptions: image.DecodingOptions = {
        desiredSize: { width: MODEL_INPUT_SIZE, height: MODEL_INPUT_SIZE },
        editable: true,
      };
      let preprocessedPixelMap = await imageSource.createPixelMap(decodingOptions);

      let displaySource = image.createImageSource(imageUri);
      this.displayPixelMap = await displaySource.createPixelMap();

      let rgbaBuffer = new ArrayBuffer(MODEL_INPUT_SIZE * MODEL_INPUT_SIZE * 4);
      await preprocessedPixelMap.readPixelsToBuffer(rgbaBuffer);

      await this.doInference(rgbaBuffer);
    } catch (err) {
      this.tipText = '图片加载失败: ' + JSON.stringify(err);
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
    this.canvasContext.clearRect(0, 0, this.CANVAS_SIZE, this.CANVAS_SIZE);

    for (let i = 0; i < this.boxList.length; i++) {
      let box = this.boxList[i];
      let rx = box.x * this.CANVAS_SIZE;
      let ry = box.y * this.CANVAS_SIZE;
      let rw = box.width * this.CANVAS_SIZE;
      let rh = box.height * this.CANVAS_SIZE;

      let colorIdx = box.classId;
      if (colorIdx < 0 || colorIdx >= CLASS_COLORS.length) {
        colorIdx = 0;
      }
      let strokeColor = CLASS_COLORS[colorIdx];

      this.canvasContext.strokeStyle = strokeColor;
      this.canvasContext.lineWidth = 3;
      this.canvasContext.strokeRect(rx, ry, rw, rh);

      let labelText = box.label + ' ' + (box.confidence * 100).toFixed(1) + '%';
      this.canvasContext.font = '12px sans-serif';
      let textWidth = this.canvasContext.measureText(labelText).width;

      let labelY = ry - 18;
      if (labelY < 0) {
        labelY = ry;
      }

      this.canvasContext.fillStyle = strokeColor;
      this.canvasContext.fillRect(rx, labelY, textWidth + 8, 18);

      this.canvasContext.fillStyle = '#FFFFFF';
      this.canvasContext.fillText(labelText, rx + 4, labelY + 13);
    }
  }

  @Builder
  ResultItem(box: DetectionBox) {
    Row() {
      Row()
        .width(12)
        .height(12)
        .borderRadius(2)
        .backgroundColor(CLASS_COLORS[box.classId >= 0 && box.classId < CLASS_COLORS.length ? box.classId : 0])
        .margin({ right: 8 })

      Text(box.label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)

      Text((box.confidence * 100).toFixed(1) + '%')
        .fontSize(14)
        .fontColor('#666666')
    }
    .width('100%')
    .height(36)
    .padding({ left: 12, right: 12 })
    .borderRadius(6)
    .backgroundColor('#F5F5F5')
    .margin({ bottom: 6 })
  }

  @Builder
  ClassLegend(name: string, color: string) {
    Row() {
      Row()
        .width(10)
        .height(10)
        .borderRadius(2)
        .backgroundColor(color)
        .margin({ right: 6 })
      Text(name)
        .fontSize(12)
        .fontColor('#666666')
    }
    .margin({ bottom: 4 })
  }

  build() {
    Scroll() {
      Column() {
        Text('X-Ray YOLOv5s')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 40 })

        Text('OpenHarmony 5.0.3 + Ascend 310B')
          .fontSize(13)
          .fontColor('#999999')
          .margin({ top: 4 })

        Text(this.tipText)
          .fontSize(14)
          .fontColor('#666666')
          .margin({ top: 12, bottom: 16 })
          .textAlign(TextAlign.Center)
          .width('80%')

        Stack() {
          if (this.displayPixelMap) {
            Image(this.displayPixelMap)
              .width(this.CANVAS_SIZE)
              .height(this.CANVAS_SIZE)
              .objectFit(ImageFit.Fill)
          } else {
            Column() {
              Text('X-Ray Image')
                .fontSize(16)
                .fontColor('#CCCCCC')
            }
            .width(this.CANVAS_SIZE)
            .height(this.CANVAS_SIZE)
            .backgroundColor('#F0F0F0')
            .justifyContent(FlexAlign.Center)
            .borderRadius(8)
          }

          Canvas(this.canvasContext)
            .width(this.CANVAS_SIZE)
            .height(this.CANVAS_SIZE)
            .onReady(() => {
              this.canvasReady = true;
              if (this.boxList.length > 0) {
                this.drawBoxes();
              }
            })
        }
        .width(this.CANVAS_SIZE)
        .height(this.CANVAS_SIZE)
        .borderRadius(8)
        .clip(true)

        Button(this.isProcessing ? '推理中...' : '选择X光图片')
          .width('80%')
          .height(48)
          .margin({ top: 24 })
          .enabled(!this.isProcessing && this.engineReady)
          .backgroundColor(this.engineReady ? '#007DFF' : '#CCCCCC')
          .onClick(() => {
            this.selectAndProcessImage();
          })

        if (!this.engineReady) {
          Text('引擎未就绪，请检查模型文件')
            .fontSize(12)
            .fontColor('#FF4444')
            .margin({ top: 8 })
        }

        if (this.boxList.length > 0) {
          Column() {
            Text('检测结果')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 8 })

            ForEach(this.boxList, (box: DetectionBox) => {
              this.ResultItem(box)
            }, (box: DetectionBox, index: number) => index.toString() + '_' + box.classId.toString() + '_' + box.confidence.toString())
          }
          .width('85%')
          .margin({ top: 16 })
        }

        Column() {
          Text('类别说明')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 6 })

          ForEach(CLASS_NAMES, (name: string, index: number) => {
            this.ClassLegend(name, index < CLASS_COLORS.length ? CLASS_COLORS[index] : '#999999')
          }, (name: string, index: number) => index.toString())
        }
        .margin({ top: 16, bottom: 40 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
