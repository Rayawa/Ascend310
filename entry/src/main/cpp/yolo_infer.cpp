#include "yolo_infer.h"
#include <cstring>
#include <algorithm>
#include <numeric>

YoloInference::YoloInference()
    : deviceId_(0), context_(nullptr), stream_(nullptr),
      modelId_(0), modelMemSize_(0), modelWorkSize_(0),
      modelMemPtr_(nullptr), modelWorkPtr_(nullptr),
      isLoad_(false), deviceInited_(false),
      modelDesc_(nullptr),
      inputSize_(0), inputDeviceBuffer_(nullptr),
      outputSize_(0), outputDeviceBuffer_(nullptr),
      outputHostBuffer_(nullptr) {}

YoloInference::~YoloInference() { Unload(); }

bool YoloInference::InitDevice(int32_t deviceId) {
    auto& acl = AclDl::Instance();
    if (!acl.Load()) {
        std::cout << "[YOLO] Failed to load ACL runtime library" << std::endl;
        return false;
    }

    deviceId_ = deviceId;

    int ret = acl.aclInit(nullptr);
    if (ret != ACL_SUCCESS && ret != ACL_ERROR_REPEAT_INITIALIZE) {
        std::cout << "[YOLO] aclInit failed, ret=" << ret << std::endl;
        return false;
    }

    ret = acl.aclrtSetDevice(deviceId_);
    if (ret != ACL_SUCCESS) {
        std::cout << "[YOLO] aclrtSetDevice failed, ret=" << ret << std::endl;
        return false;
    }

    ret = acl.aclrtCreateContext(&context_, deviceId_);
    if (ret != ACL_SUCCESS) {
        std::cout << "[YOLO] aclrtCreateContext failed, ret=" << ret << std::endl;
        return false;
    }

    ret = acl.aclrtCreateStream(&stream_);
    if (ret != ACL_SUCCESS) {
        std::cout << "[YOLO] aclrtCreateStream failed, ret=" << ret << std::endl;
        return false;
    }

    deviceInited_ = true;
    std::cout << "[YOLO] Device init success, deviceId=" << deviceId_ << std::endl;
    return true;
}

bool YoloInference::LoadModel(const std::string& modelPath) {
    auto& acl = AclDl::Instance();
    if (!deviceInited_) {
        std::cout << "[YOLO] Device not initialized!" << std::endl;
        return false;
    }

    modelDesc_ = acl.aclmdlCreateDesc();
    if (modelDesc_ == nullptr) {
        std::cout << "[YOLO] aclmdlCreateDesc failed" << std::endl;
        return false;
    }

    int ret = acl.aclmdlLoadFromFile(modelPath.c_str(), &modelId_);
    if (ret != ACL_SUCCESS) {
        std::cout << "[YOLO] aclmdlLoadFromFile failed, ret=" << ret
                  << " path=" << modelPath << std::endl;
        acl.aclmdlDestroyDesc(modelDesc_);
        modelDesc_ = nullptr;
        return false;
    }

    ret = acl.aclmdlGetDesc(modelDesc_, modelId_);
    if (ret != ACL_SUCCESS) {
        std::cout << "[YOLO] aclmdlGetDesc failed, ret=" << ret << std::endl;
        acl.aclmdlUnload(modelId_);
        acl.aclmdlDestroyDesc(modelDesc_);
        modelDesc_ = nullptr;
        return false;
    }

    size_t inputCount = acl.aclmdlGetNumInputs(modelDesc_);
    size_t outputCount = acl.aclmdlGetNumOutputs(modelDesc_);
    std::cout << "[YOLO] Model loaded: inputs=" << inputCount
              << " outputs=" << outputCount << std::endl;

    if (inputCount > 0) {
        inputSize_ = acl.aclmdlGetInputSizeByIndex(modelDesc_, 0);
        std::cout << "[YOLO] Input[0] size=" << inputSize_ << " bytes" << std::endl;
    }

    if (outputCount > 0) {
        outputSize_ = acl.aclmdlGetOutputSizeByIndex(modelDesc_, 0);
        std::cout << "[YOLO] Output[0] size=" << outputSize_ << " bytes" << std::endl;
    }

    acl.aclrtMalloc(&inputDeviceBuffer_, inputSize_, ACL_MEM_MALLOC_HUGE_FIRST);
    acl.aclrtMalloc(&outputDeviceBuffer_, outputSize_, ACL_MEM_MALLOC_HUGE_FIRST);
    outputHostBuffer_ = new float[outputSize_ / sizeof(float)];

    isLoad_ = true;
    std::cout << "[YOLO] Model load success" << std::endl;
    return true;
}

std::vector<DetectionResult> YoloInference::DoInference(
    const void* imageData, size_t imageSize,
    int origWidth, int origHeight) {
    std::vector<DetectionResult> results;
    auto& acl = AclDl::Instance();

    if (!isLoad_) {
        std::cout << "[YOLO] Model not loaded!" << std::endl;
        return results;
    }

    acl.aclrtSetCurrentContext(context_);

    size_t requiredInputSize = INPUT_H * INPUT_W * 3 * sizeof(float);
    if (inputSize_ == 0) {
        inputSize_ = requiredInputSize;
    }

    std::vector<float> inputFloat(INPUT_H * INPUT_W * 3, 0.0f);

    const uint8_t* rgbaData = static_cast<const uint8_t*>(imageData);
    size_t pixelCount = imageSize / 4;
    if (pixelCount > static_cast<size_t>(INPUT_H * INPUT_W)) {
        pixelCount = INPUT_H * INPUT_W;
    }

    for (size_t i = 0; i < pixelCount; i++) {
        inputFloat[i] = rgbaData[i * 4 + 0] / 255.0f;
        inputFloat[INPUT_H * INPUT_W + i] = rgbaData[i * 4 + 1] / 255.0f;
        inputFloat[2 * INPUT_H * INPUT_W + i] = rgbaData[i * 4 + 2] / 255.0f;
    }

    acl.aclrtMemcpy(inputDeviceBuffer_, inputSize_,
                inputFloat.data(), requiredInputSize,
                ACL_RT_MEMCPY_HOST_TO_DEVICE);

    void* inputDataBuf = acl.aclCreateDataBuffer(inputDeviceBuffer_, inputSize_);
    void* inputDataset = acl.aclmdlCreateDataset();
    acl.aclmdlAddDatasetBuffer(inputDataset, inputDataBuf);

    void* outputDataBuf = acl.aclCreateDataBuffer(outputDeviceBuffer_, outputSize_);
    void* outputDataset = acl.aclmdlCreateDataset();
    acl.aclmdlAddDatasetBuffer(outputDataset, outputDataBuf);

    int ret = acl.aclmdlExecute(modelId_, inputDataset, outputDataset);
    if (ret != ACL_SUCCESS) {
        std::cout << "[YOLO] aclmdlExecute failed, ret=" << ret << std::endl;
        acl.aclDestroyDataBuffer(inputDataBuf);
        acl.aclDestroyDataBuffer(outputDataBuf);
        acl.aclmdlDestroyDataset(inputDataset);
        acl.aclmdlDestroyDataset(outputDataset);
        return results;
    }

    ret = acl.aclrtMemcpy(outputHostBuffer_, outputSize_,
                      outputDeviceBuffer_, outputSize_,
                      ACL_RT_MEMCPY_DEVICE_TO_HOST);
    if (ret != ACL_SUCCESS) {
        std::cout << "[YOLO] aclrtMemcpy output failed, ret=" << ret << std::endl;
    }

    int outputFloatCount = static_cast<int>(outputSize_ / sizeof(float));
    results = PostProcess(outputHostBuffer_, outputFloatCount, origWidth, origHeight);

    acl.aclDestroyDataBuffer(inputDataBuf);
    acl.aclDestroyDataBuffer(outputDataBuf);
    acl.aclmdlDestroyDataset(inputDataset);
    acl.aclmdlDestroyDataset(outputDataset);

    return results;
}

std::vector<DetectionResult> YoloInference::PostProcess(
    const float* outputData, int outputCount,
    int origWidth, int origHeight) {
    std::vector<DetectionResult> finalResults;

    int totalElements = OUTPUT_BOX_NUM * OUTPUT_ELEM_PER_ROW;

    std::vector<std::vector<BBoxInternal>> classBoxes(CLASS_NUM);

    for (int i = 0; i < OUTPUT_BOX_NUM; i++) {
        int rowOffset = i * OUTPUT_ELEM_PER_ROW;

        if (rowOffset + OUTPUT_ELEM_PER_ROW > outputCount) {
            break;
        }

        float objConf = outputData[rowOffset + 4];
        if (objConf < CONF_THRESHOLD) {
            continue;
        }

        int bestClassId = 0;
        float bestClassScore = outputData[rowOffset + 5];
        for (int c = 1; c < CLASS_NUM; c++) {
            float score = outputData[rowOffset + 5 + c];
            if (score > bestClassScore) {
                bestClassScore = score;
                bestClassId = c;
            }
        }

        float finalScore = objConf * bestClassScore;
        if (finalScore < CONF_THRESHOLD) {
            continue;
        }

        float cx = outputData[rowOffset + 0];
        float cy = outputData[rowOffset + 1];
        float w = outputData[rowOffset + 2];
        float h = outputData[rowOffset + 3];

        float x1 = (cx - w / 2.0f) / INPUT_W;
        float y1 = (cy - h / 2.0f) / INPUT_H;
        float x2 = (cx + w / 2.0f) / INPUT_W;
        float y2 = (cy + h / 2.0f) / INPUT_H;

        x1 = std::max(0.0f, std::min(1.0f, x1));
        y1 = std::max(0.0f, std::min(1.0f, y1));
        x2 = std::max(0.0f, std::min(1.0f, x2));
        y2 = std::max(0.0f, std::min(1.0f, y2));

        BBoxInternal bbox;
        bbox.x1 = x1;
        bbox.y1 = y1;
        bbox.x2 = x2;
        bbox.y2 = y2;
        bbox.score = finalScore;
        bbox.classId = bestClassId;

        classBoxes[bestClassId].push_back(bbox);
    }

    for (int c = 0; c < CLASS_NUM; c++) {
        std::vector<BBoxInternal> nmsResult = NMS(classBoxes[c], NMS_THRESHOLD);

        for (const auto& box : nmsResult) {
            DetectionResult det;
            det.x = box.x1;
            det.y = box.y1;
            det.width = box.x2 - box.x1;
            det.height = box.y2 - box.y1;
            det.confidence = box.score;
            det.classId = box.classId;
            det.label = CLASS_NAMES[box.classId];
            finalResults.push_back(det);
        }
    }

    std::sort(finalResults.begin(), finalResults.end(),
              [](const DetectionResult& a, const DetectionResult& b) {
                  return a.confidence > b.confidence;
              });

    std::cout << "[YOLO] PostProcess: " << finalResults.size()
              << " detections from " << OUTPUT_BOX_NUM << " candidates" << std::endl;

    return finalResults;
}

std::vector<BBoxInternal> YoloInference::NMS(
    std::vector<BBoxInternal>& boxes, float iouThreshold) {
    std::vector<BBoxInternal> result;
    if (boxes.empty()) {
        return result;
    }

    std::sort(boxes.begin(), boxes.end(),
              [](const BBoxInternal& a, const BBoxInternal& b) {
                  return a.score > b.score;
              });

    std::vector<bool> suppressed(boxes.size(), false);

    for (size_t i = 0; i < boxes.size(); i++) {
        if (suppressed[i]) {
            continue;
        }
        result.push_back(boxes[i]);

        for (size_t j = i + 1; j < boxes.size(); j++) {
            if (suppressed[j]) {
                continue;
            }
            float iou = ComputeIoU(boxes[i], boxes[j]);
            if (iou > iouThreshold) {
                suppressed[j] = true;
            }
        }
    }

    return result;
}

float YoloInference::ComputeIoU(const BBoxInternal& a, const BBoxInternal& b) {
    float interX1 = std::max(a.x1, b.x1);
    float interY1 = std::max(a.y1, b.y1);
    float interX2 = std::min(a.x2, b.x2);
    float interY2 = std::min(a.y2, b.y2);

    float interW = std::max(0.0f, interX2 - interX1);
    float interH = std::max(0.0f, interY2 - interY1);
    float interArea = interW * interH;

    float areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    float areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
    float unionArea = areaA + areaB - interArea;

    if (unionArea <= 0.0f) {
        return 0.0f;
    }
    return interArea / unionArea;
}

void YoloInference::Unload() {
    auto& acl = AclDl::Instance();

    if (inputDeviceBuffer_ != nullptr && acl.aclrtFree) {
        acl.aclrtFree(inputDeviceBuffer_);
        inputDeviceBuffer_ = nullptr;
    }
    if (outputDeviceBuffer_ != nullptr && acl.aclrtFree) {
        acl.aclrtFree(outputDeviceBuffer_);
        outputDeviceBuffer_ = nullptr;
    }
    if (outputHostBuffer_ != nullptr) {
        delete[] outputHostBuffer_;
        outputHostBuffer_ = nullptr;
    }

    if (isLoad_) {
        if (acl.aclmdlUnload) {
            acl.aclmdlUnload(modelId_);
        }
        if (modelDesc_ != nullptr && acl.aclmdlDestroyDesc) {
            acl.aclmdlDestroyDesc(modelDesc_);
            modelDesc_ = nullptr;
        }
        isLoad_ = false;
    }

    if (deviceInited_) {
        if (stream_ != nullptr && acl.aclrtDestroyStream) {
            acl.aclrtDestroyStream(stream_);
            stream_ = nullptr;
        }
        if (context_ != nullptr && acl.aclrtDestroyContext) {
            acl.aclrtDestroyContext(context_);
            context_ = nullptr;
        }
        if (acl.aclrtResetDevice) {
            acl.aclrtResetDevice(deviceId_);
        }
        if (acl.aclFinalize) {
            acl.aclFinalize();
        }
        deviceInited_ = false;
    }

    std::cout << "[YOLO] Unload complete" << std::endl;
}
