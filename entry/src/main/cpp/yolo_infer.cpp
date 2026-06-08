#include "yolo_infer.h"

YoloInference::YoloInference() : deviceId_(0), modelId_(0), isLoad_(false), modelDesc_(nullptr) {}
YoloInference::~YoloInference() { Unload(); }

// ===== 步骤 1：初始化 NPU =====
bool YoloInference::InitDevice(int32_t deviceId) {
    deviceId_ = deviceId;
    // 初始化 CANN 资源
    aclError ret = aclInit(nullptr);
    // 指定使用具体的 310B 芯片设备 (通常单板上填 0)
    ret = aclrtSetDevice(deviceId_);
    // 创建 Context 和 Stream 任务流
    ret = aclrtCreateContext(&context_, deviceId_);
    ret = aclrtCreateStream(&stream_);
    return true;
}

// ===== 步骤 2：加载 .om 模型 =====
bool YoloInference::LoadModel(const std::string& modelPath) {
    // 从板端磁盘读取 .om 文件并加载到 NPU 内存中
    aclError ret = aclmdlLoadFromFileWithMem(modelPath.c_str(), &modelId_, 
                                             modelMemPtr_, modelMemSize_, 
                                             modelWorkPtr_, modelWorkSize_);
    // 获取模型输入输出的结构描述（比如知道模型需要多大分辨率、输出几个 Tensor）
    modelDesc_ = aclmdlCreateDesc();
    ret = aclmdlGetDesc(modelDesc_, modelId_);
    isLoad_ = true;
    return true;
}

// ===== 步骤 3：核心推理业务 =====
std::vector<DetectionResult> YoloInference::DoInference(const void* imageBuffer, size_t bufferSize) {
    std::vector<DetectionResult> results;
    
    // 3.1 申请 NPU 上的输入/输出专用内存（Device 侧内存）
    void* inputDeviceBuffer = nullptr;
    aclrtMalloc(&inputDeviceBuffer, bufferSize, ACL_MEM_MALLOC_HUGE_FIRST);
    
    // 3.2 将前端传进来的内存数据拷贝到 NPU 内存中
    aclrtMemcpy(inputDeviceBuffer, bufferSize, imageBuffer, bufferSize, ACL_RT_MEMCPY_HOST_TO_DEVICE);

    // 3.3 创建 CANN 推理专用的 Dataset 数据包
    inputDataset_ = aclmdlCreateDataset();
    aclDataBuffer* inputData = aclCreateDataBuffer(inputDeviceBuffer, bufferSize);
    aclmdlAddDatasetBuffer(inputDataset_, inputData);

    // (此处省略创建 outputDataset_ 的相似代码，用来接收模型的输出)

    // 3.4 🌟 触发昇腾 310B 硬件推理（阻塞/异步执行）
    aclError ret = aclmdlExecute(modelId_, inputDataset_, outputDataset_);
    if (ret != ACL_SUCCESS) {
        std::cout << "CANN 推理失败!" << std::endl;
        return results;
    }

    // 3.5 调用后处理：提取输出的 Float 数组进行 Yolo 的解码与 NMS
    results = PostProcess();

    // 3.6 记得及时释放本次推理申请的临时 Device 内存
    aclrtFree(inputDeviceBuffer);
    // 销毁 dataset 结构...
    
    return results; // 返回干净的坐标框丢给 NAPI
}

// ===== 步骤 4：YOLO 专属后处理 =====
std::vector<DetectionResult> YoloInference::PostProcess() {
    std::vector<DetectionResult> finalBoxes;
    
    // 从 outputDataset_ 中拿到推理出来的裸数据指针 (Raw Pointer)
    aclDataBuffer* dataBuffer = aclmdlGetDatasetBuffer(outputDataset_, 0);
    void* outData = aclGetDataBufferAddr(dataBuffer);
    float* outFloats = reinterpret_cast<float*>(outData);

    // 📢 算法同学的主场：
    // YOLO 模型输出一般是 [1, 84, 8400] 这样的矩阵
    // 算法同学需要在这里写循环：
    // 1. 遍历这 8400 个候选框
    // 2. 过滤掉置信度低于阈值（如 0.4）的框
    // 3. 运行 NMS（非极大值抑制）算法消灭重复的重叠框
    // 4. 将留下来的有效框坐标【归一化】成 0~1 的比例，压进 finalBoxes
    
    return finalBoxes;
}

// ===== 步骤 5：优雅释放 =====
void YoloInference::Unload() {
    if (isLoad_) {
        aclmdlDestroyDesc(modelDesc_);
        aclmdlUnload(modelId_);
        aclrtDestroyStream(stream_);
        aclrtDestroyContext(context_);
        aclrtResetDevice(deviceId_);
        aclFinalize();
        isLoad_ = false;
    }
}