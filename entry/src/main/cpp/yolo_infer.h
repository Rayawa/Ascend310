#pragma once

#include <iostream>
#include <vector>
#include <string>
#include "acl/acl.h" // 核心：引入昇腾 CANN ACL 头文件

// 定义传给前端的检测框结构体
struct DetectionResult {
    float x;
    float y;
    float width;
    float height;
    float confidence;
    std::string label;
};

class YoloInference {
public:
    YoloInference();
    ~YoloInference();

    // 1. 初始化 CANN 和 310B NPU 设备
    bool InitDevice(int32_t deviceId = 0);
    
    // 2. 加载转换好的文件 yolov8.om
    bool LoadModel(const std::string& modelPath);
    
    // 3. 执行推理主业务
    std::vector<DetectionResult> DoInference(const void* imageBuffer, size_t bufferSize);
    
    // 4. 卸载模型与释放资源
    void Unload();

private:
    // 内部后处理：解析 NPU 输出的裸数据，进行 NMS（非极大值抑制）
    std::vector<DetectionResult> PostProcess();

private:
    int32_t deviceId_;
    aclrtContext context_;
    aclrtStream stream_;
    
    uint32_t modelId_;
    size_t modelMemSize_;
    size_t modelWorkSize_;
    void* modelMemPtr_;
    void* modelWorkPtr_;
    bool isLoad_;

    // 模型输入输出的数据集描述
    aclmdlDesc* modelDesc_;
    aclmdlDataset* inputDataset_;
    aclmdlDataset* outputDataset_;
};