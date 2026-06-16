export interface DetectionBox {
  x: number;
  y: number;
  width: number;
  height: number;
  confidence: number;
  label: string;
  classId: number;
}

export const CLASS_NAMES: string[] = [
  'Pneumonia Bacteria',
  'Pneumonia Virus',
  'Sick',
  'healthy',
  'tuberculosis'
];

export const CLASS_COLORS: string[] = [
  '#FF4444',
  '#FF8800',
  '#FFCC00',
  '#44BB44',
  '#AA44FF'
];

export const MODEL_INPUT_SIZE: number = 640;
export const CLASS_COUNT: number = 5;
