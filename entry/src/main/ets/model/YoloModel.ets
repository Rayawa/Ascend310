import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { CLASS_NAMES, DetectionBox } from './DetectionType';

const CLASS_NUM: number = 5;
const OUTPUT_ELEM_PER_ROW: number = 5 + CLASS_NUM;
const OUTPUT_BOX_NUM: number = 25200;
const CONF_THRESHOLD: number = 0.25;
const NMS_THRESHOLD: number = 0.45;
const INPUT_H: number = 640;
const INPUT_W: number = 640;

interface BBoxInternal {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  score: number;
  classId: number;
}

export class YoloModel {
  private msModel: mindSporeLite.Model | null = null;

  async init(modelBuffer: ArrayBuffer): Promise<boolean> {
    try {
      let context: mindSporeLite.Context = {};
      context.target = ['cpu'];
      context.cpu = {};
      context.cpu.threadNum = 2;
      context.cpu.threadAffinityMode = 1;
      context.cpu.precisionMode = 'enforce_fp32';

      this.msModel = await mindSporeLite.loadModelFromBuffer(modelBuffer, context);
      let inputs: mindSporeLite.MSTensor[] = this.msModel.getInputs();
      console.info('[YoloModel] Model loaded, input count=' + inputs.length);
      if (inputs.length > 0) {
        console.info('[YoloModel] Input[0] name=' + inputs[0].name +
          ' shape=' + inputs[0].shape.toString() +
          ' dataSize=' + inputs[0].dataSize.toString());
      }
      return true;
    } catch (err) {
      console.error('[YoloModel] Init failed: ' + JSON.stringify(err));
      return false;
    }
  }

  async runInference(rgbaBuffer: ArrayBuffer): Promise<DetectionBox[]> {
    if (!this.msModel) {
      console.error('[YoloModel] Model not initialized');
      return [];
    }

    let inputs: mindSporeLite.MSTensor[] = this.msModel.getInputs();
    if (inputs.length === 0) {
      console.error('[YoloModel] No model inputs');
      return [];
    }

    let floatData = this.preprocessRGBA(rgbaBuffer);
    inputs[0].setData(floatData.buffer);

    let outputs: mindSporeLite.MSTensor[] = await this.msModel.predict(inputs);

    if (outputs.length === 0) {
      console.error('[YoloModel] No model outputs');
      return [];
    }

    let outputData = outputs[0].getData();
    return this.postProcess(outputData);
  }

  private preprocessRGBA(rgbaBuffer: ArrayBuffer): Float32Array {
    let rgba = new Uint8Array(rgbaBuffer);
    let pixelCount = INPUT_H * INPUT_W;
    let floatData = new Float32Array(pixelCount * 3);

    for (let i = 0; i < pixelCount; i++) {
      floatData[i] = rgba[i * 4 + 0] / 255.0;
      floatData[pixelCount + i] = rgba[i * 4 + 1] / 255.0;
      floatData[2 * pixelCount + i] = rgba[i * 4 + 2] / 255.0;
    }

    return floatData;
  }

  private postProcess(outputBuffer: ArrayBuffer): DetectionBox[] {
    let outputData = new Float32Array(outputBuffer);
    let outputCount = outputData.length;

    let classBoxes: BBoxInternal[][] = [];
    for (let c = 0; c < CLASS_NUM; c++) {
      classBoxes.push([]);
    }

    for (let i = 0; i < OUTPUT_BOX_NUM; i++) {
      let rowOffset = i * OUTPUT_ELEM_PER_ROW;

      if (rowOffset + OUTPUT_ELEM_PER_ROW > outputCount) {
        break;
      }

      let objConf = outputData[rowOffset + 4];
      if (objConf < CONF_THRESHOLD) {
        continue;
      }

      let bestClassId = 0;
      let bestClassScore = outputData[rowOffset + 5];
      for (let c = 1; c < CLASS_NUM; c++) {
        let score = outputData[rowOffset + 5 + c];
        if (score > bestClassScore) {
          bestClassScore = score;
          bestClassId = c;
        }
      }

      let finalScore = objConf * bestClassScore;
      if (finalScore < CONF_THRESHOLD) {
        continue;
      }

      let cx = outputData[rowOffset + 0];
      let cy = outputData[rowOffset + 1];
      let w = outputData[rowOffset + 2];
      let h = outputData[rowOffset + 3];

      let x1 = (cx - w / 2.0) / INPUT_W;
      let y1 = (cy - h / 2.0) / INPUT_H;
      let x2 = (cx + w / 2.0) / INPUT_W;
      let y2 = (cy + h / 2.0) / INPUT_H;

      x1 = Math.max(0.0, Math.min(1.0, x1));
      y1 = Math.max(0.0, Math.min(1.0, y1));
      x2 = Math.max(0.0, Math.min(1.0, x2));
      y2 = Math.max(0.0, Math.min(1.0, y2));

      let bbox: BBoxInternal = {
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        score: finalScore,
        classId: bestClassId
      };

      classBoxes[bestClassId].push(bbox);
    }

    let finalResults: DetectionBox[] = [];

    for (let c = 0; c < CLASS_NUM; c++) {
      let nmsResult = this.nms(classBoxes[c], NMS_THRESHOLD);

      for (let j = 0; j < nmsResult.length; j++) {
        let box = nmsResult[j];
        let det: DetectionBox = {
          x: box.x1,
          y: box.y1,
          width: box.x2 - box.x1,
          height: box.y2 - box.y1,
          confidence: box.score,
          classId: box.classId,
          label: CLASS_NAMES[box.classId]
        };
        finalResults.push(det);
      }
    }

    finalResults.sort((a: DetectionBox, b: DetectionBox) => a.confidence > b.confidence ? -1 : 1);

    console.info('[YoloModel] PostProcess: ' + finalResults.length.toString() +
      ' detections from ' + OUTPUT_BOX_NUM.toString() + ' candidates');

    return finalResults;
  }

  private nms(boxes: BBoxInternal[], iouThreshold: number): BBoxInternal[] {
    let result: BBoxInternal[] = [];
    if (boxes.length === 0) {
      return result;
    }

    let sorted = boxes.slice().sort((a: BBoxInternal, b: BBoxInternal) => a.score > b.score ? -1 : 1);

    let suppressed: boolean[] = new Array(sorted.length).fill(false);

    for (let i = 0; i < sorted.length; i++) {
      if (suppressed[i]) {
        continue;
      }
      result.push(sorted[i]);

      for (let j = i + 1; j < sorted.length; j++) {
        if (suppressed[j]) {
          continue;
        }
        let iou = this.computeIoU(sorted[i], sorted[j]);
        if (iou > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return result;
  }

  private computeIoU(a: BBoxInternal, b: BBoxInternal): number {
    let interX1 = Math.max(a.x1, b.x1);
    let interY1 = Math.max(a.y1, b.y1);
    let interX2 = Math.min(a.x2, b.x2);
    let interY2 = Math.min(a.y2, b.y2);

    let interW = Math.max(0.0, interX2 - interX1);
    let interH = Math.max(0.0, interY2 - interY1);
    let interArea = interW * interH;

    let areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    let areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
    let unionArea = areaA + areaB - interArea;

    if (unionArea <= 0.0) {
      return 0.0;
    }
    return interArea / unionArea;
  }
}
