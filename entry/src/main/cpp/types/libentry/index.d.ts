export const initYoloEngine: (modelPath: string) => Promise<boolean>;
export const runYoloInference: (imageBuffer: ArrayBuffer, width: number, height: number) => Promise<Array<DetectionBox>>;

interface DetectionBox {
  x: number;
  y: number;
  width: number;
  height: number;
  confidence: number;
  label: string;
  classId: number;
}
