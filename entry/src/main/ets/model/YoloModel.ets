import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { CLASS_NAMES, DetectionBox } from './DetectionType';

const CLASS_NUM: number = 5;
const OUTPUT_ELEM_PER_ROW: number = 5 + CLASS_NUM;
const OUTPUT_BOX_NUM: number = 25200;
const CONF_THRESHOLD: number = 0.25;
const NMS_THRESHOLD: number = 0.45;
const INPUT_H: number = 640;
const INPUT_W: number = 640;
const EXPECTED_RGBA_SIZE: number = INPUT_H * INPUT_W * 4;

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

  isModelReady(): boolean {
    return this.msModel !== null;
  }

  async init(modelBuffer: ArrayBuffer): Promise<boolean> {
    console.info('[YoloModel] init() called, buffer size=' + modelBuffer.byteLength.toString());
    try {
      if (!modelBuffer || modelBuffer.byteLength === 0) {
        console.error('[YoloModel] init failed: model buffer is null or empty');
        return false;
      }

      let context: mindSporeLite.Context = {};
      context.target = ['cpu'];
      context.cpu = {};
      context.cpu.threadNum = 2;
      context.cpu.threadAffinityMode = 1;
      context.cpu.precisionMode = 'enforce_fp32';

      console.info('[YoloModel] Calling loadModelFromBuffer...');
      let startTime: number = Date.now();
      this.msModel = await mindSporeLite.loadModelFromBuffer(modelBuffer, context);
      let elapsed: number = Date.now() - startTime;
      console.info('[YoloModel] loadModelFromBuffer completed in ' + elapsed.toString() + ' ms');

      if (!this.msModel) {
        console.error('[YoloModel] init failed: loadModelFromBuffer returned null');
        return false;
      }

      let inputs: mindSporeLite.MSTensor[] = this.msModel.getInputs();
      console.info('[YoloModel] Model loaded, input count=' + inputs.length.toString());

      if (inputs.length === 0) {
        console.error('[YoloModel] init failed: model has no inputs');
        this.msModel = null;
        return false;
      }

      console.info('[YoloModel] Input[0] name=' + inputs[0].name +
        ' shape=' + inputs[0].shape.toString() +
        ' dataSize=' + inputs[0].dataSize.toString());
      return true;
    } catch (err) {
      let errMsg: string = '';
      if (err instanceof Error) {
        errMsg = err.message;
      } else if (typeof err === 'string') {
        errMsg = err;
      } else {
        errMsg = JSON.stringify(err);
      }
      console.error('[YoloModel] init exception: ' + errMsg);
      this.msModel = null;
      return false;
    }
  }

  async runInference(rgbaBuffer: ArrayBuffer): Promise<DetectionBox[]> {
    try {
      if (!this.msModel) {
        console.error('[YoloModel] runInference failed: model not initialized, call init() first');
        return [];
      }

      if (!rgbaBuffer || rgbaBuffer.byteLength < EXPECTED_RGBA_SIZE) {
        console.error('[YoloModel] runInference failed: invalid input buffer, expected ' +
          EXPECTED_RGBA_SIZE.toString() + ' bytes, got ' +
          (rgbaBuffer ? rgbaBuffer.byteLength.toString() : 'null'));
        return [];
      }

      let inputs: mindSporeLite.MSTensor[] = this.msModel.getInputs();
      if (inputs.length === 0) {
        console.error('[YoloModel] runInference failed: model has no inputs');
        return [];
      }

      let floatData: Float32Array = this.preprocessRGBA(rgbaBuffer);
      inputs[0].setData(floatData.buffer);
      console.info('[YoloModel] Input data set, running predict...');

      let predictStart: number = Date.now();
      let outputs: mindSporeLite.MSTensor[] = await this.msModel.predict(inputs);
      let predictElapsed: number = Date.now() - predictStart;
      console.info('[YoloModel] predict completed in ' + predictElapsed.toString() + ' ms');

      if (outputs.length === 0) {
        console.error('[YoloModel] runInference failed: predict returned no outputs');
        return [];
      }

      let outputData: ArrayBuffer = outputs[0].getData();
      if (!outputData || outputData.byteLength === 0) {
        console.error('[YoloModel] runInference failed: output[0].getData() returned empty');
        return [];
      }

      console.info('[YoloModel] Output data size: ' + outputData.byteLength.toString() + ' bytes');
      return this.postProcess(outputData);
    } catch (err) {
      let errMsg: string = '';
      if (err instanceof Error) {
        errMsg = err.message;
      } else if (typeof err === 'string') {
        errMsg = err;
      } else {
        errMsg = JSON.stringify(err);
      }
      console.error('[YoloModel] runInference exception: ' + errMsg);
      return [];
    }
  }

  private preprocessRGBA(rgbaBuffer: ArrayBuffer): Float32Array {
    try {
      if (rgbaBuffer.byteLength < EXPECTED_RGBA_SIZE) {
        console.error('[YoloModel] preprocessRGBA: buffer too small, expected ' +
          EXPECTED_RGBA_SIZE.toString() + ', got ' + rgbaBuffer.byteLength.toString());
        return new Float32Array(0);
      }

      let rgba: Uint8Array = new Uint8Array(rgbaBuffer);
      let pixelCount: number = INPUT_H * INPUT_W;
      let floatData: Float32Array = new Float32Array(pixelCount * 3);

      for (let i: number = 0; i < pixelCount; i++) {
        floatData[i] = rgba[i * 4 + 0] / 255.0;
        floatData[pixelCount + i] = rgba[i * 4 + 1] / 255.0;
        floatData[2 * pixelCount + i] = rgba[i * 4 + 2] / 255.0;
      }

      console.info('[YoloModel] preprocessRGBA: ' + pixelCount.toString() + ' pixels converted to float32');
      return floatData;
    } catch (err) {
      let errMsg: string = '';
      if (err instanceof Error) {
        errMsg = err.message;
      } else if (typeof err === 'string') {
        errMsg = err;
      } else {
        errMsg = JSON.stringify(err);
      }
      console.error('[YoloModel] preprocessRGBA exception: ' + errMsg);
      return new Float32Array(0);
    }
  }

  private postProcess(outputBuffer: ArrayBuffer): DetectionBox[] {
    try {
      if (!outputBuffer || outputBuffer.byteLength < 4) {
        console.error('[YoloModel] postProcess failed: output buffer too small, ' +
          (outputBuffer ? outputBuffer.byteLength.toString() : 'null') + ' bytes');
        return [];
      }

      let outputData: Float32Array = new Float32Array(outputBuffer);
      let outputCount: number = outputData.length;
      console.info('[YoloModel] postProcess: output tensor has ' + outputCount.toString() + ' float values');

      let classBoxes: BBoxInternal[][] = [];
      for (let c: number = 0; c < CLASS_NUM; c++) {
        classBoxes.push([]);
      }

      let rawBoxCount: number = 0;
      for (let i: number = 0; i < OUTPUT_BOX_NUM; i++) {
        let rowOffset: number = i * OUTPUT_ELEM_PER_ROW;

        if (rowOffset + OUTPUT_ELEM_PER_ROW > outputCount) {
          break;
        }

        let objConf: number = outputData[rowOffset + 4];
        if (objConf < CONF_THRESHOLD) {
          continue;
        }

        let bestClassId: number = 0;
        let bestClassScore: number = outputData[rowOffset + 5];
        for (let c: number = 1; c < CLASS_NUM; c++) {
          let score: number = outputData[rowOffset + 5 + c];
          if (score > bestClassScore) {
            bestClassScore = score;
            bestClassId = c;
          }
        }

        let finalScore: number = objConf * bestClassScore;
        if (finalScore < CONF_THRESHOLD) {
          continue;
        }

        let cx: number = outputData[rowOffset + 0];
        let cy: number = outputData[rowOffset + 1];
        let w: number = outputData[rowOffset + 2];
        let h: number = outputData[rowOffset + 3];

        let x1: number = (cx - w / 2.0) / INPUT_W;
        let y1: number = (cy - h / 2.0) / INPUT_H;
        let x2: number = (cx + w / 2.0) / INPUT_W;
        let y2: number = (cy + h / 2.0) / INPUT_H;

        x1 = Math.max(0.0, Math.min(1.0, x1));
        y1 = Math.max(0.0, Math.min(1.0, y1));
        x2 = Math.max(0.0, Math.min(1.0, x2));
        y2 = Math.max(0.0, Math.min(1.0, y2));

        if (x1 >= x2 || y1 >= y2) {
          continue;
        }

        let bbox: BBoxInternal = {
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          score: finalScore,
          classId: bestClassId
        };

        classBoxes[bestClassId].push(bbox);
        rawBoxCount = rawBoxCount + 1;
      }

      console.info('[YoloModel] postProcess: ' + rawBoxCount.toString() + ' raw boxes after filter');

      for (let c: number = 0; c < CLASS_NUM; c++) {
        console.info('[YoloModel] Raw boxes class ' + c.toString() +
          ' (' + CLASS_NAMES[c] + '): ' + classBoxes[c].length.toString());
      }

      let finalResults: DetectionBox[] = [];

      for (let c: number = 0; c < CLASS_NUM; c++) {
        let nmsResult: BBoxInternal[] = this.nms(classBoxes[c], NMS_THRESHOLD);

        for (let j: number = 0; j < nmsResult.length; j++) {
          let box: BBoxInternal = nmsResult[j];
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

      console.info('[YoloModel] PostProcess done: ' + finalResults.length.toString() +
        ' detections from ' + OUTPUT_BOX_NUM.toString() + ' candidates');

      return finalResults;
    } catch (err) {
      let errMsg: string = '';
      if (err instanceof Error) {
        errMsg = err.message;
      } else if (typeof err === 'string') {
        errMsg = err;
      } else {
        errMsg = JSON.stringify(err);
      }
      console.error('[YoloModel] postProcess exception: ' + errMsg);
      return [];
    }
  }

  private nms(boxes: BBoxInternal[], iouThreshold: number): BBoxInternal[] {
    let result: BBoxInternal[] = [];
    let boxCount: number = boxes.length;
    if (boxCount === 0) {
      return result;
    }

    try {
      let sorted: BBoxInternal[] = boxes.slice().sort((a: BBoxInternal, b: BBoxInternal) =>
        a.score > b.score ? -1 : 1
      );

      let suppressed: boolean[] = new Array<boolean>(sorted.length);
      for (let k: number = 0; k < sorted.length; k++) {
        suppressed[k] = false;
      }

      for (let i: number = 0; i < sorted.length; i++) {
        if (suppressed[i]) {
          continue;
        }
        result.push(sorted[i]);

        for (let j: number = i + 1; j < sorted.length; j++) {
          if (suppressed[j]) {
            continue;
          }
          let iou: number = this.computeIoU(sorted[i], sorted[j]);
          if (iou > iouThreshold) {
            suppressed[j] = true;
          }
        }
      }

      let suppressedCount: number = boxCount - result.length;
      if (suppressedCount > 0) {
        console.info('[YoloModel] NMS suppressed ' + suppressedCount.toString() +
          ' boxes, kept ' + result.length.toString());
      }

      return result;
    } catch (err) {
      let errMsg: string = '';
      if (err instanceof Error) {
        errMsg = err.message;
      } else if (typeof err === 'string') {
        errMsg = err;
      } else {
        errMsg = JSON.stringify(err);
      }
      console.error('[YoloModel] nms exception: ' + errMsg);
      return result;
    }
  }

  private computeIoU(a: BBoxInternal, b: BBoxInternal): number {
    try {
      let interX1: number = Math.max(a.x1, b.x1);
      let interY1: number = Math.max(a.y1, b.y1);
      let interX2: number = Math.min(a.x2, b.x2);
      let interY2: number = Math.min(a.y2, b.y2);

      let interW: number = Math.max(0.0, interX2 - interX1);
      let interH: number = Math.max(0.0, interY2 - interY1);
      let interArea: number = interW * interH;

      let areaA: number = (a.x2 - a.x1) * (a.y2 - a.y1);
      let areaB: number = (b.x2 - b.x1) * (b.y2 - b.y1);
      let unionArea: number = areaA + areaB - interArea;

      if (unionArea <= 0.0) {
        return 0.0;
      }
      return interArea / unionArea;
    } catch (err) {
      console.error('[YoloModel] computeIoU exception: ' + JSON.stringify(err));
      return 0.0;
    }
  }
}
