---
name: 实现 YOLOv5s 完整推理流程
overview: 在 OpenHarmony 5.0.3 上实现基于昇腾 310B 的 YOLOv5s 医疗影像检测完整推理流程
todos:
  - content: 创建 rawfile 目录并配置模型路径
    status: pending
    priority: high
  - content: 添加文件读取权限配置
    status: pending
    priority: high
  - content: 完善 C++ 输出 dataset 创建和错误处理
    status: pending
    priority: high
  - content: 实现图片预处理（解码、缩放、归一化）
    status: pending
    priority: high
  - content: 实现 YOLOv5 后处理（解码、NMS、坐标归一化）
    status: pending
    priority: high
  - content: 集成 NAPI 和 YoloInference 类
    status: pending
    priority: high
  - content: 编译测试和运行时验证
    status: pending
    priority: medium
---

# 实现 YOLOv5s 完整推理流程

## Goal

实现完整的端到端 YOLOv5s 推理流程，包括：
- ONNX 模型加载配置
- 图片预处理（解码、缩放、归一化）
- 昇腾 310B NPU 推理
- YOLO 后处理（解码、NMS）
- 结果可视化

用于 X 光胸片医疗影像检测，识别 5 种类别：Pneumonia Bacteria、Pneumonia Virus、Sick、healthy、tuberculosis。

## Scope / Non-goals

**包含**：
- rawfile 目录创建和模型路径配置
- 文件读取权限配置
- C++ 完整推理逻辑（输出 dataset、错误处理）
- 图片预处理（使用 OpenCV 或 CANN DVPP）
- YOLOv5 后处理（解码、置信度过滤、NMS）
- NAPI 和 YoloInference 类集成
- 编译和运行时验证

**不包含**：
- UI 界面重新设计（已有基础功能）
- 模型训练和转换（用户已有 .om 文件）
- 性能优化（后续可优化）
- 多模型切换功能

## Current State And Constraints

**当前状态**：
- ✅ ArkTS UI 层已完成：图片选择、推理调用、Canvas 可视化
- ✅ C++ 框架已有：`yolo_infer.h`（完整）、`yolo_infer.cpp`（部分）、`hello.cpp`（NAPI 框架）
- ✅ CMakeLists.txt 编译配置已完成
- ❌ 缺少 rawfile 目录和模型文件
- ❌ 缺少文件读取权限
- ❌ C++ 实现不完整：输出 dataset、后处理、预处理、NAPI 集成

**ArkTS 约束**：
- 不使用 `any`、`unknown`、`as` 断言
- 不使用动态属性访问
- 使用命名接口和显式类型

**技术约束**：
- OpenHarmony 5.0.3 API 12
- 昇腾 310B NPU + CANN ACL
- YOLOv5s 模型：输入 640x640，输出 [1, 25200, 10]
- 5 个检测类别

## Design

### 整体架构

```
用户选择图片 (ArkTS)
    ↓
ArrayBuffer 传输 (NAPI)
    ↓
图片预处理 (C++ OpenCV/DVPP)
    ↓
CANN 推理 (昇腾 310B NPU)
    ↓
YOLO 后处理 (C++ 解码 + NMS)
    ↓
检测结果返回 (NAPI)
    ↓
Canvas 可视化 (ArkTS)
```

### 关键设计决策

**1. 图片预处理方案**：
- **选择**：使用 OpenCV 进行预处理（而非 DVPP）
- **原因**：
  - OpenCV 更成熟稳定，易于调试
  - DVPP 需要额外的 CANN 依赖和配置
  - 对于单张图片推理，OpenCV 性能足够
- **实现**：
  - 解码：`cv::imdecode()`
  - 缩放：`cv::resize()` 到 640x640
  - 归一化：像素值 / 255.0
  - 格式：RGB（需要 BGR 转 RGB）

**2. YOLOv5 后处理**：
- **输出格式**：[1, 25200, 10]
  - 25200 个候选框
  - 每个框 10 个值：[x, y, w, h, confidence, class0, class1, class2, class3, class4]
- **处理流程**：
  1. 遍历 25200 个候选框
  2. 计算每个框的最大类别置信度
  3. 过滤置信度 < 0.25 的框
  4. 运行 NMS（IoU 阈值 0.45）
  5. 坐标归一化到 [0, 1]
- **NMS 算法**：标准非极大值抑制

**3. 模型加载**：
- 模型路径：`/data/local/tmp/yolov5s.om`（设备上的绝对路径）
- 用户需要将 .om 文件推送到设备：`hdc file send yolov5s.om /data/local/tmp/`
- 初始化时加载模型并创建输入输出 dataset

**4. 错误处理**：
- C++ 层：使用 `ACL_SUCCESS` 检查所有 CANN API 调用
- NAPI 层：使用 `napi_create_error` 返回错误信息
- ArkTS 层：使用 try-catch 捕获异常并显示错误信息

**5. 权限配置**：
- `ohos.permission.READ_MEDIA`：读取相册图片
- `ohos.permission.WRITE_MEDIA`：写入相册（可选，当前不需要）

## Key Files

### 需要修改的文件

1. **[entry/src/main/module.json5](entry/src/main/module.json5)**
   - 添加文件读取权限

2. **[entry/src/main/cpp/yolo_infer.cpp](entry/src/main/cpp/yolo_infer.cpp)**
   - 完善输出 dataset 创建
   - 实现模型加载逻辑
   - 实现图片预处理
   - 实现 YOLO 后处理（解码 + NMS）
   - 添加完整的错误处理

3. **[entry/src/main/cpp/hello.cpp](entry/src/main/cpp/hello.cpp)**
   - 集成 YoloInference 类
   - 实现 ExecuteInference 函数
   - 实现 CompleteInference 函数
   - 添加错误处理

4. **[entry/src/main/cpp/CMakeLists.txt](entry/src/main/cpp/CMakeLists.txt)**
   - 添加 OpenCV 依赖（如果使用 OpenCV）

### 需要创建的文件

1. **entry/src/main/resources/rawfile/.gitkeep**
   - 创建 rawfile 目录
   - 用户需要将 .om 模型文件放入此目录

2. **entry/src/main/cpp/yolo_utils.h**（可选）
   - YOLO 后处理工具函数
   - NMS 算法实现

3. **entry/src/main/cpp/yolo_utils.cpp**（可选）
   - yolo_utils.h 的实现

## Execution Sequence

### 阶段 1：配置和准备（优先级：高）

**步骤 1.1：创建 rawfile 目录**
```bash
mkdir -p entry/src/main/resources/rawfile
touch entry/src/main/resources/rawfile/.gitkeep
```

**步骤 1.2：添加权限配置**
修改 `entry/src/main/module.json5`：
```json5
{
  "module": {
    // ... 现有配置 ...
    "requestPermissions": [
      {
        "name": "ohos.permission.READ_MEDIA",
        "reason": "$string:read_media_reason",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "inuse"
        }
      }
    ]
  }
}
```

**步骤 1.3：添加权限说明字符串**
修改 `entry/src/main/resources/base/element/string.json`：
```json
{
  "string": [
    // ... 现有字符串 ...
    {
      "name": "read_media_reason",
      "value": "用于读取相册中的图片进行 YOLO 检测"
    }
  ]
}
```

### 阶段 2：C++ 核心实现（优先级：高）

**步骤 2.1：完善 yolo_infer.cpp - 输出 dataset 创建**

在 `DoInference` 函数中添加输出 dataset 创建：
```cpp
// 创建输出 dataset
outputDataset_ = aclmdlCreateDataset();

// 获取输出大小
size_t outputSize = aclmdlGetOutputSizeByIndex(modelDesc_, 0);

// 申请输出内存
void* outputDeviceBuffer = nullptr;
aclrtMalloc(&outputDeviceBuffer, outputSize, ACL_MEM_MALLOC_HUGE_FIRST);

// 创建输出 data buffer
aclDataBuffer* outputData = aclCreateDataBuffer(outputDeviceBuffer, outputSize);
aclmdlAddDatasetBuffer(outputDataset_, outputData);
```

**步骤 2.2：实现图片预处理**

添加预处理函数：
```cpp
// 图片预处理：解码、缩放、归一化
bool PreprocessImage(const void* imageBuffer, size_t bufferSize, 
                     std::vector<float>& inputData, int targetWidth, int targetHeight) {
    // 1. 解码图片
    std::vector<uchar> imageData((uchar*)imageBuffer, (uchar*)imageBuffer + bufferSize);
    cv::Mat image = cv::imdecode(imageData, cv::IMREAD_COLOR);
    
    if (image.empty()) {
        return false;
    }
    
    // 2. 缩放到 640x640
    cv::Mat resized;
    cv::resize(image, resized, cv::Size(targetWidth, targetHeight));
    
    // 3. BGR 转 RGB
    cv::Mat rgb;
    cv::cvtColor(resized, rgb, cv::COLOR_BGR2RGB);
    
    // 4. 归一化并转为 float
    inputData.resize(targetWidth * targetHeight * 3);
    for (int i = 0; i < targetHeight; i++) {
        for (int j = 0; j < targetWidth; j++) {
            // HWC -> CHW
            inputData[0 * targetHeight * targetWidth + i * targetWidth + j] = rgb.at<cv::Vec3b>(i, j)[0] / 255.0f;
            inputData[1 * targetHeight * targetWidth + i * targetWidth + j] = rgb.at<cv::Vec3b>(i, j)[1] / 255.0f;
            inputData[2 * targetHeight * targetWidth + i * targetWidth + j] = rgb.at<cv::Vec3b>(i, j)[2] / 255.0f;
        }
    }
    
    return true;
}
```

**步骤 2.3：实现 YOLO 后处理**

添加后处理函数：
```cpp
// YOLOv5 后处理：解码、NMS、坐标归一化
std::vector<DetectionResult> PostProcess(float* outputData, int numBoxes, int numValues,
                                         int imgWidth, int imgHeight,
                                         float confThreshold = 0.25f, float nmsThreshold = 0.45f) {
    std::vector<DetectionResult> results;
    
    // 1. 解码所有候选框
    std::vector<std::tuple<float, float, float, float, float, int>> boxes; // x, y, w, h, conf, class
    
    for (int i = 0; i < numBoxes; i++) {
        float* ptr = outputData + i * numValues;
        float x = ptr[0];
        float y = ptr[1];
        float w = ptr[2];
        float h = ptr[3];
        float confidence = ptr[4];
        
        // 找到最大类别置信度
        int bestClass = 0;
        float bestClassConf = ptr[5];
        for (int c = 1; c < 5; c++) {
            if (ptr[5 + c] > bestClassConf) {
                bestClassConf = ptr[5 + c];
                bestClass = c;
            }
        }
        
        float finalConf = confidence * bestClassConf;
        
        // 过滤低置信度框
        if (finalConf > confThreshold) {
            boxes.push_back(std::make_tuple(x, y, w, h, finalConf, bestClass));
        }
    }
    
    // 2. NMS（非极大值抑制）
    std::vector<int> keepIndices = NMS(boxes, nmsThreshold);
    
    // 3. 坐标归一化并生成结果
    const std::vector<std::string> classNames = {
        "Pneumonia Bacteria", "Pneumonia Virus", "Sick", "healthy", "tuberculosis"
    };
    
    for (int idx : keepIndices) {
        auto& box = boxes[idx];
        DetectionResult result;
        result.x = std::get<0>(box) / imgWidth;
        result.y = std::get<1>(box) / imgHeight;
        result.width = std::get<2>(box) / imgWidth;
        result.height = std::get<3>(box) / imgHeight;
        result.confidence = std::get<4>(box);
        result.label = classNames[std::get<5>(box)];
        results.push_back(result);
    }
    
    return results;
}

// NMS 算法
std::vector<int> NMS(const std::vector<std::tuple<float, float, float, float, float, int>>& boxes, 
                     float nmsThreshold) {
    std::vector<int> indices(boxes.size());
    std::iota(indices.begin(), indices.end(), 0);
    
    // 按置信度排序
    std::sort(indices.begin(), indices.end(), [&boxes](int a, int b) {
        return std::get<4>(boxes[a]) > std::get<4>(boxes[b]);
    });
    
    std::vector<int> keep;
    std::vector<bool> suppressed(boxes.size(), false);
    
    for (int i : indices) {
        if (suppressed[i]) continue;
        keep.push_back(i);
        
        for (int j : indices) {
            if (suppressed[j] || j == i) continue;
            
            float iou = CalculateIoU(boxes[i], boxes[j]);
            if (iou > nmsThreshold) {
                suppressed[j] = true;
            }
        }
    }
    
    return keep;
}

// 计算 IoU
float CalculateIoU(const std::tuple<float, float, float, float, float, int>& a,
                   const std::tuple<float, float, float, float, float, int>& b) {
    float x1 = std::max(std::get<0>(a), std::get<0>(b));
    float y1 = std::max(std::get<1>(a), std::get<1>(b));
    float x2 = std::min(std::get<0>(a) + std::get<2>(a), std::get<0>(b) + std::get<2>(b));
    float y2 = std::min(std::get<1>(a) + std::get<3>(a), std::get<1>(b) + std::get<3>(b));
    
    float intersection = std::max(0.0f, x2 - x1) * std::max(0.0f, y2 - y1);
    float areaA = std::get<2>(a) * std::get<3>(a);
    float areaB = std::get<2>(b) * std::get<3>(b);
    float unionArea = areaA + areaB - intersection;
    
    return intersection / unionArea;
}
```

**步骤 2.4：完善 DoInference 函数**

整合预处理、推理、后处理：
```cpp
std::vector<DetectionResult> YoloInference::DoInference(const void* imageBuffer, size_t bufferSize) {
    std::vector<DetectionResult> results;
    
    // 1. 图片预处理
    std::vector<float> inputData;
    if (!PreprocessImage(imageBuffer, bufferSize, inputData, 640, 640)) {
        std::cout << "图片预处理失败!" << std::endl;
        return results;
    }
    
    // 2. 申请输入内存并拷贝数据
    size_t inputSize = inputData.size() * sizeof(float);
    void* inputDeviceBuffer = nullptr;
    aclrtMalloc(&inputDeviceBuffer, inputSize, ACL_MEM_MALLOC_HUGE_FIRST);
    aclrtMemcpy(inputDeviceBuffer, inputSize, inputData.data(), inputSize, ACL_RT_MEMCPY_HOST_TO_DEVICE);
    
    // 3. 创建输入 dataset
    inputDataset_ = aclmdlCreateDataset();
    aclDataBuffer* inputDataBuffer = aclCreateDataBuffer(inputDeviceBuffer, inputSize);
    aclmdlAddDatasetBuffer(inputDataset_, inputDataBuffer);
    
    // 4. 创建输出 dataset（已在步骤 2.1 实现）
    // ...
    
    // 5. 执行推理
    aclError ret = aclmdlExecute(modelId_, inputDataset_, outputDataset_);
    if (ret != ACL_SUCCESS) {
        std::cout << "推理失败! 错误码: " << ret << std::endl;
        aclrtFree(inputDeviceBuffer);
        return results;
    }
    
    // 6. 获取输出数据
    aclDataBuffer* outputDataBuffer = aclmdlGetDatasetBuffer(outputDataset_, 0);
    void* outputData = aclGetDataBufferAddr(outputDataBuffer);
    float* outputFloats = reinterpret_cast<float*>(outputData);
    
    // 7. 后处理
    results = PostProcess(outputFloats, 25200, 10, 640, 640, 0.25f, 0.45f);
    
    // 8. 释放资源
    aclrtFree(inputDeviceBuffer);
    // ...
    
    return results;
}
```

**步骤 2.5：完善 hello.cpp - NAPI 集成**

修改 `ExecuteInference` 和 `CompleteInference`：
```cpp
// 异步工作数据结构
struct InferenceWorkData {
    napi_env env;
    napi_deferred deferred;
    void* imageBuffer;
    size_t bufferSize;
    std::vector<DetectionResult> results;
    YoloInference* inference;
};

// 执行推理
void ExecuteInference(napi_env env, void* data) {
    InferenceWorkData* workData = (InferenceWorkData*)data;
    
    // 调用 YoloInference 进行推理
    workData->results = workData->inference->DoInference(workData->imageBuffer, workData->bufferSize);
}

// 完成推理
void CompleteInference(napi_env env, napi_status status, void* data) {
    InferenceWorkData* workData = (InferenceWorkData*)data;
    
    // 将 C++ 结果转换为 JS 数组
    napi_value jsArray;
    napi_create_array_with_length(env, workData->results.size(), &jsArray);
    
    const std::vector<std::string> classNames = {
        "Pneumonia Bacteria", "Pneumonia Virus", "Sick", "healthy", "tuberculosis"
    };
    
    for (size_t i = 0; i < workData->results.size(); i++) {
        napi_value obj;
        napi_create_object(env, &obj);
        
        // 设置属性
        napi_value x, y, w, h, conf, label;
        napi_create_double(env, workData->results[i].x, &x);
        napi_create_double(env, workData->results[i].y, &y);
        napi_create_double(env, workData->results[i].width, &w);
        napi_create_double(env, workData->results[i].height, &h);
        napi_create_double(env, workData->results[i].confidence, &conf);
        napi_create_string_utf8(env, workData->results[i].label.c_str(), NAPI_AUTO_LENGTH, &label);
        
        napi_set_named_property(env, obj, "x", x);
        napi_set_named_property(env, obj, "y", y);
        napi_set_named_property(env, obj, "width", w);
        napi_set_named_property(env, obj, "height", h);
        napi_set_named_property(env, obj, "confidence", conf);
        napi_set_named_property(env, obj, "label", label);
        
        napi_set_element(env, jsArray, i, obj);
    }
    
    // resolve Promise
    napi_resolve_deferred(env, workData->deferred, jsArray);
    
    // 释放资源
    free(workData->imageBuffer);
    delete workData;
}
```

**步骤 2.6：更新 CMakeLists.txt**

如果使用 OpenCV，需要添加 OpenCV 依赖：
```cmake
# 添加 OpenCV 路径（根据实际安装路径调整）
set(OpenCV_DIR "/usr/local/lib/cmake/opencv4")

find_package(OpenCV REQUIRED)

include_directories(
    ${OpenCV_INCLUDE_DIRS}
)

target_link_libraries(entry PUBLIC
    ${OpenCV_LIBS}
)
```

### 阶段 3：验证和测试（优先级：中）

**步骤 3.1：编译测试**
```bash
# 在 DevEco Studio 中编译项目
# 检查是否有编译错误
```

**步骤 3.2：推送模型文件到设备**
```bash
# 将 .om 模型文件推送到设备
hdc file send yolov5s.om /data/local/tmp/
```

**步骤 3.3：运行时测试**
- 在设备上运行应用
- 选择一张 X 光胸片
- 检查推理结果是否正确
- 验证检测框是否准确

**步骤 3.4：功能验证**
- 验证图片选择功能
- 验证推理功能
- 验证结果可视化
- 验证错误处理

## Verification

| 验证项 | 方法 | 预期结果 |
|--------|------|----------|
| 编译检查 | DevEco Studio 编译 | 无编译错误 |
| 权限配置 | 检查 module.json5 | 包含 READ_MEDIA 权限 |
| rawfile 目录 | 检查目录存在 | entry/src/main/resources/rawfile 存在 |
| C++ 编译 | 检查 libentry.so 生成 | 编译成功生成动态库 |
| 运行时推理 | 选择图片测试 | 返回检测结果 |
| 检测框可视化 | 检查 Canvas 绘制 | 检测框正确显示 |
| 错误处理 | 测试异常情况 | 显示错误信息 |

**build agent 应该使用 `check_ets_files` 检查 ArkTS 语法**。

## Risks And Compatibility

### 风险

1. **OpenCV 依赖风险**：
   - 风险：设备上可能没有 OpenCV 库
   - 缓解：在 CMakeLists.txt 中正确配置 OpenCV 路径，或使用静态链接

2. **模型路径风险**：
   - 风险：模型文件路径不正确
   - 缓解：使用绝对路径 `/data/local/tmp/yolov5s.om`，并提供清晰的推送指令

3. **内存泄漏风险**：
   - 风险：C++ 层未正确释放资源
   - 缓解：在所有退出路径上释放资源，使用 RAII 模式

4. **性能风险**：
   - 风险：预处理和后处理可能成为性能瓶颈
   - 缓解：后续可优化为 DVPP 加速

### 兼容性

- **SDK 版本**：OpenHarmony 5.0.3 API 12
- **NPU**：昇腾 310B
- **CANN**：需要正确安装和配置

## Rollback

如果实现失败，按以下步骤回滚：

1. **回滚代码修改**：
   ```bash
   git checkout entry/src/main/module.json5
   git checkout entry/src/main/cpp/yolo_infer.cpp
   git checkout entry/src/main/cpp/hello.cpp
   git checkout entry/src/main/cpp/CMakeLists.txt
   ```

2. **删除创建的文件**：
   ```bash
   rm -rf entry/src/main/resources/rawfile
   ```

3. **恢复权限字符串**：
   - 从 string.json 中删除 `read_media_reason`

4. **重新编译**：
   ```bash
   # 清理编译缓存
   # 重新编译项目
   ```

## Additional Notes

### 用户需要准备的内容

1. **模型文件**：
   - 将训练好的 YOLOv5s 模型转换为 .om 格式
   - 使用 ATC 工具转换：
     ```bash
     atc --model=yolov5s.onnx --framework=5 --output=yolov5s --soc_version=Ascend310B
     ```
   - 推送到设备：
     ```bash
     hdc file send yolov5s.om /data/local/tmp/
     ```

2. **OpenCV 库**：
   - 确保设备上有 OpenCV 库
   - 或在编译时静态链接 OpenCV

3. **CANN 环境**：
   - 确保 CANN ACL 正确安装
   - 配置正确的 CANN SDK 路径

### 后续优化方向

1. **性能优化**：
   - 使用 DVPP 加速图片预处理
   - 使用异步推理提高吞吐量

2. **功能扩展**：
   - 支持多模型切换
   - 支持实时视频流检测
   - 添加模型管理功能

3. **用户体验**：
   - 添加推理时间显示
   - 添加检测类别筛选
   - 优化 UI 交互
