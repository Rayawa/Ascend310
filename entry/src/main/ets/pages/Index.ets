import { image } from '@kit.ImageKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import yoloEngine from 'libentry.so';
import { DetectionBox } from '../model/DetectionType';

@Entry
@Component
struct Index {
  @State imagePixelMap: PixelMap | undefined = undefined;
  @State isProcessing: boolean = false;
  @State tipText: string = "请选择一张图片进行 YOLO 检测";

  private boxList: DetectionBox[] = [];
  // Canvas 画布组件的控制器
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);

  // 画布固定的显示大小（需与 UI 布局一致）
  private readonly COMPONENT_SIZE: number = 360;

  // 2. 选择照片并将其转化为 ArrayBuffer
  async selectAndProcessImage() {
    try {
      let photoPicker = new picker.PhotoViewPicker();
      let photoSelectOptions = new picker.PhotoSelectOptions();

      // 🌟 核心修改：使用 API 12 规范的 PhotoViewMIMETypes 枚举
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      let result = await photoPicker.select(photoSelectOptions);

      if (!result || result.photoUris.length === 0) return;
      let imageUri = result.photoUris[0];


      // 读取文件转化为 ArrayBuffer 传给 C++
      let file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(file.fd);
      let arrayBuffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, arrayBuffer);
      fs.closeSync(file);

      // 解码用于界面原生 <Image> 组件显示
      let imageSource = image.createImageSource(imageUri);
      this.imagePixelMap = await imageSource.createPixelMap();

      // 3. 触发推理
      await this.doInference(arrayBuffer);
    } catch (err) {
      this.tipText = `图片加载失败: ${JSON.stringify(err)}`;
    }
  }

  // 4. 调用 NAPI 异步接口
  async doInference(buffer: ArrayBuffer) {
    this.isProcessing = true;
    this.tipText = "昇腾 310B 正在高能推理中...";

    try {
      // 核心：调用 C++ 暴露的方法，传入图片的二进制数据
      this.boxList = await yoloEngine.runYoloInference(buffer);
      this.tipText = `检测完成，共发现 ${this.boxList.length} 个目标！`;

      // 推理成功，在 Canvas 上画红框
      this.drawBoxes();
    } catch (error) {
      this.tipText = `推理出错: ${error}`;
    } finally {
      this.isProcessing = false;
    }
  }

  // 5. 渲染检测框
  drawBoxes() {
    // 每次画之前，先清空画布
    this.canvasContext.clearRect(0, 0, this.COMPONENT_SIZE, this.COMPONENT_SIZE);

    this.boxList.forEach(box => {
      // C++ 返回的是 0~1 的比例坐标，需要乘以当前画布组件的实际像素宽高
      let rx = box.x * this.COMPONENT_SIZE;
      let ry = box.y * this.COMPONENT_SIZE;
      let rw = box.width * this.COMPONENT_SIZE;
      let rh = box.height * this.COMPONENT_SIZE;

      // 画矩形边框
      this.canvasContext.strokeStyle = '#FF2A2A'; // 醒目红
      this.canvasContext.lineWidth = 3;
      this.canvasContext.strokeRect(rx, ry, rw, rh);

      // 画标签背景
      this.canvasContext.fillStyle = '#FF2A2A';
      let labelText = `${box.label} ${(box.confidence * 100).toFixed(0)}%`;
      let textWidth = this.canvasContext.measureText(labelText).width;
      this.canvasContext.fillRect(rx, ry - 20, textWidth + 10, 20);

      // 画标签文字
      this.canvasContext.fillStyle = '#FFFFFF';
      this.canvasContext.font = '14px sans-serif';
      this.canvasContext.fillText(labelText, rx + 5, ry - 5);
    });
  }

  build() {
    Column() {
      Text("OpenHarmony 5.0 + Ascend 310B")
        .fontSize(20).fontWeight(FontWeight.Bold).margin({ top: 30 })

      Text(this.tipText)
        .fontSize(14).fontColor('#666666').margin({ top: 10, bottom: 20 })

      // 用 Stack 将 Canvas 盖在 Image 上面实现“贴框”效果
      Stack() {
        if (this.imagePixelMap) {
          Image(this.imagePixelMap)
            .width(this.COMPONENT_SIZE)
            .height(this.COMPONENT_SIZE)
            .objectFit(ImageFit.Fill) // 铺满组件，方便和 0~1 的归一化坐标严格对应
        } else {
          Column().width(this.COMPONENT_SIZE).height(this.COMPONENT_SIZE).backgroundColor('#EEEFEF')
        }

        Canvas(this.canvasContext)
          .width(this.COMPONENT_SIZE)
          .height(this.COMPONENT_SIZE)
          .onReady(() => { /* 画布就绪 */ })
      }
      .width(this.COMPONENT_SIZE)
      .height(this.COMPONENT_SIZE)
      .borderRadius(8)
      .clip(true)

      Button(this.isProcessing ? '计算中...' : '选择图片检测')
        .width('80%')
        .height(50)
        .margin({ top: 40 })
        .enabled(!this.isProcessing)
        .onClick(() => {
          this.selectAndProcessImage();
        })
    }
    .width('100%')
    .height('100%')
  }
}