/**
 * 传入图片的 ArrayBuffer 字节流
 * 异步返回推理结果（底层会被包装成 Promise 传给 ArkTS）
 */
export const runYoloInference: (imageBuffer: ArrayBuffer) => Promise<Array<any>>;