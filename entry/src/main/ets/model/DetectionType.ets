// 定义单条检测目标的数据结构
export interface DetectionBox {
  x: number;          // 矩形框左上角 X 轴比例 (0 ~ 1)
  y: number;          // 矩形框左上角 Y 轴比例 (0 ~ 1)
  width: number;      // 矩形框宽度比例 (0 ~ 1)
  height: number;     // 矩形框高度比例 (0 ~ 1)
  confidence: number; // 置信度 (0 ~ 1)
  label: string;      // 类别标签名称
}