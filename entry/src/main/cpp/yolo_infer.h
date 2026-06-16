#pragma once

#include <iostream>
#include <vector>
#include <string>
#include <algorithm>
#include <cmath>
#include <dlfcn.h>
#include <cstdint>

struct DetectionResult {
    float x;
    float y;
    float width;
    float height;
    float confidence;
    int classId;
    std::string label;
};

struct BBoxInternal {
    float x1;
    float y1;
    float x2;
    float y2;
    float score;
    int classId;
};

typedef int (*FN_aclInit)(const char*);
typedef int (*FN_aclrtSetDevice)(int32_t);
typedef int (*FN_aclrtCreateContext)(void**, int32_t);
typedef int (*FN_aclrtCreateStream)(void**);
typedef int (*FN_aclrtSetCurrentContext)(void*);
typedef int (*FN_aclrtMemcpy)(void*, size_t, const void*, size_t, int);
typedef int (*FN_aclrtMalloc)(void**, size_t, unsigned int);
typedef int (*FN_aclrtFree)(void*);
typedef int (*FN_aclrtDestroyStream)(void*);
typedef int (*FN_aclrtDestroyContext)(void*);
typedef int (*FN_aclrtResetDevice)(int32_t);
typedef int (*FN_aclFinalize)();
typedef void* (*FN_aclmdlCreateDesc)();
typedef int (*FN_aclmdlGetDesc)(void*, uint32_t);
typedef int (*FN_aclmdlDestroyDesc)(void*);
typedef int (*FN_aclmdlLoadFromFile)(const char*, uint32_t*);
typedef int (*FN_aclmdlUnload)(uint32_t);
typedef int (*FN_aclmdlExecute)(uint32_t, void*, void*);
typedef size_t (*FN_aclmdlGetNumInputs)(void*);
typedef size_t (*FN_aclmdlGetNumOutputs)(void*);
typedef size_t (*FN_aclmdlGetInputSizeByIndex)(void*, size_t);
typedef size_t (*FN_aclmdlGetOutputSizeByIndex)(void*, size_t);
typedef void* (*FN_aclCreateDataBuffer)(void*, size_t);
typedef int (*FN_aclDestroyDataBuffer)(void*);
typedef void* (*FN_aclmdlCreateDataset)();
typedef int (*FN_aclmdlAddDatasetBuffer)(void*, void*);
typedef int (*FN_aclmdlDestroyDataset)(void*);

static constexpr int ACL_SUCCESS = 0;
static constexpr int ACL_ERROR_REPEAT_INITIALIZE = 100001;
static constexpr int ACL_MEM_MALLOC_HUGE_FIRST = 0;
static constexpr int ACL_RT_MEMCPY_HOST_TO_DEVICE = 1;
static constexpr int ACL_RT_MEMCPY_DEVICE_TO_HOST = 2;

class AclDl {
public:
    static AclDl& Instance() {
        static AclDl inst;
        return inst;
    }

    bool Load() {
        if (loaded_) return true;

        handle_ = dlopen("libacl_runtime.so", RTLD_NOW);
        if (!handle_) {
            std::cout << "[YOLO] dlopen libacl_runtime.so failed: " << dlerror() << std::endl;
            return false;
        }

        if (!LoadSym("aclInit", reinterpret_cast<void**>(&aclInit))) return CleanupOnFail();
        if (!LoadSym("aclrtSetDevice", reinterpret_cast<void**>(&aclrtSetDevice))) return CleanupOnFail();
        if (!LoadSym("aclrtCreateContext", reinterpret_cast<void**>(&aclrtCreateContext))) return CleanupOnFail();
        if (!LoadSym("aclrtCreateStream", reinterpret_cast<void**>(&aclrtCreateStream))) return CleanupOnFail();
        if (!LoadSym("aclrtSetCurrentContext", reinterpret_cast<void**>(&aclrtSetCurrentContext))) return CleanupOnFail();
        if (!LoadSym("aclrtMemcpy", reinterpret_cast<void**>(&aclrtMemcpy))) return CleanupOnFail();
        if (!LoadSym("aclrtMalloc", reinterpret_cast<void**>(&aclrtMalloc))) return CleanupOnFail();
        if (!LoadSym("aclrtFree", reinterpret_cast<void**>(&aclrtFree))) return CleanupOnFail();
        if (!LoadSym("aclrtDestroyStream", reinterpret_cast<void**>(&aclrtDestroyStream))) return CleanupOnFail();
        if (!LoadSym("aclrtDestroyContext", reinterpret_cast<void**>(&aclrtDestroyContext))) return CleanupOnFail();
        if (!LoadSym("aclrtResetDevice", reinterpret_cast<void**>(&aclrtResetDevice))) return CleanupOnFail();
        if (!LoadSym("aclFinalize", reinterpret_cast<void**>(&aclFinalize))) return CleanupOnFail();
        if (!LoadSym("aclmdlCreateDesc", reinterpret_cast<void**>(&aclmdlCreateDesc))) return CleanupOnFail();
        if (!LoadSym("aclmdlGetDesc", reinterpret_cast<void**>(&aclmdlGetDesc))) return CleanupOnFail();
        if (!LoadSym("aclmdlDestroyDesc", reinterpret_cast<void**>(&aclmdlDestroyDesc))) return CleanupOnFail();
        if (!LoadSym("aclmdlLoadFromFile", reinterpret_cast<void**>(&aclmdlLoadFromFile))) return CleanupOnFail();
        if (!LoadSym("aclmdlUnload", reinterpret_cast<void**>(&aclmdlUnload))) return CleanupOnFail();
        if (!LoadSym("aclmdlExecute", reinterpret_cast<void**>(&aclmdlExecute))) return CleanupOnFail();
        if (!LoadSym("aclmdlGetNumInputs", reinterpret_cast<void**>(&aclmdlGetNumInputs))) return CleanupOnFail();
        if (!LoadSym("aclmdlGetNumOutputs", reinterpret_cast<void**>(&aclmdlGetNumOutputs))) return CleanupOnFail();
        if (!LoadSym("aclmdlGetInputSizeByIndex", reinterpret_cast<void**>(&aclmdlGetInputSizeByIndex))) return CleanupOnFail();
        if (!LoadSym("aclmdlGetOutputSizeByIndex", reinterpret_cast<void**>(&aclmdlGetOutputSizeByIndex))) return CleanupOnFail();
        if (!LoadSym("aclCreateDataBuffer", reinterpret_cast<void**>(&aclCreateDataBuffer))) return CleanupOnFail();
        if (!LoadSym("aclDestroyDataBuffer", reinterpret_cast<void**>(&aclDestroyDataBuffer))) return CleanupOnFail();
        if (!LoadSym("aclmdlCreateDataset", reinterpret_cast<void**>(&aclmdlCreateDataset))) return CleanupOnFail();
        if (!LoadSym("aclmdlAddDatasetBuffer", reinterpret_cast<void**>(&aclmdlAddDatasetBuffer))) return CleanupOnFail();
        if (!LoadSym("aclmdlDestroyDataset", reinterpret_cast<void**>(&aclmdlDestroyDataset))) return CleanupOnFail();

        loaded_ = true;
        return true;
    }

    FN_aclInit aclInit = nullptr;
    FN_aclrtSetDevice aclrtSetDevice = nullptr;
    FN_aclrtCreateContext aclrtCreateContext = nullptr;
    FN_aclrtCreateStream aclrtCreateStream = nullptr;
    FN_aclrtSetCurrentContext aclrtSetCurrentContext = nullptr;
    FN_aclrtMemcpy aclrtMemcpy = nullptr;
    FN_aclrtMalloc aclrtMalloc = nullptr;
    FN_aclrtFree aclrtFree = nullptr;
    FN_aclrtDestroyStream aclrtDestroyStream = nullptr;
    FN_aclrtDestroyContext aclrtDestroyContext = nullptr;
    FN_aclrtResetDevice aclrtResetDevice = nullptr;
    FN_aclFinalize aclFinalize = nullptr;
    FN_aclmdlCreateDesc aclmdlCreateDesc = nullptr;
    FN_aclmdlGetDesc aclmdlGetDesc = nullptr;
    FN_aclmdlDestroyDesc aclmdlDestroyDesc = nullptr;
    FN_aclmdlLoadFromFile aclmdlLoadFromFile = nullptr;
    FN_aclmdlUnload aclmdlUnload = nullptr;
    FN_aclmdlExecute aclmdlExecute = nullptr;
    FN_aclmdlGetNumInputs aclmdlGetNumInputs = nullptr;
    FN_aclmdlGetNumOutputs aclmdlGetNumOutputs = nullptr;
    FN_aclmdlGetInputSizeByIndex aclmdlGetInputSizeByIndex = nullptr;
    FN_aclmdlGetOutputSizeByIndex aclmdlGetOutputSizeByIndex = nullptr;
    FN_aclCreateDataBuffer aclCreateDataBuffer = nullptr;
    FN_aclDestroyDataBuffer aclDestroyDataBuffer = nullptr;
    FN_aclmdlCreateDataset aclmdlCreateDataset = nullptr;
    FN_aclmdlAddDatasetBuffer aclmdlAddDatasetBuffer = nullptr;
    FN_aclmdlDestroyDataset aclmdlDestroyDataset = nullptr;

private:
    AclDl() = default;
    void* handle_ = nullptr;
    bool loaded_ = false;

    bool LoadSym(const char* name, void** target) {
        *target = dlsym(handle_, name);
        if (!*target) {
            std::cout << "[YOLO] dlsym " << name << " failed: " << dlerror() << std::endl;
            return false;
        }
        return true;
    }

    bool CleanupOnFail() {
        dlclose(handle_);
        handle_ = nullptr;
        return false;
    }
};

class YoloInference {
public:
    YoloInference();
    ~YoloInference();

    bool InitDevice(int32_t deviceId = 0);
    bool LoadModel(const std::string& modelPath);
    std::vector<DetectionResult> DoInference(const void* imageData, size_t imageSize,
                                              int origWidth, int origHeight);
    void Unload();

private:
    std::vector<DetectionResult> PostProcess(const float* outputData, int outputCount,
                                              int origWidth, int origHeight);
    std::vector<BBoxInternal> NMS(std::vector<BBoxInternal>& boxes, float iouThreshold);
    static float ComputeIoU(const BBoxInternal& a, const BBoxInternal& b);

private:
    int32_t deviceId_;
    void* context_;
    void* stream_;

    uint32_t modelId_;
    size_t modelMemSize_;
    size_t modelWorkSize_;
    void* modelMemPtr_;
    void* modelWorkPtr_;
    bool isLoad_;
    bool deviceInited_;

    void* modelDesc_;

    size_t inputSize_;
    void* inputDeviceBuffer_;

    size_t outputSize_;
    void* outputDeviceBuffer_;
    float* outputHostBuffer_;

    static constexpr int INPUT_H = 640;
    static constexpr int INPUT_W = 640;
    static constexpr int CLASS_NUM = 5;
    static constexpr int OUTPUT_ELEM_PER_ROW = 5 + CLASS_NUM;
    static constexpr int OUTPUT_BOX_NUM = 25200;
    static constexpr float CONF_THRESHOLD = 0.25f;
    static constexpr float NMS_THRESHOLD = 0.45f;

    static constexpr const char* CLASS_NAMES[] = {
        "Pneumonia Bacteria",
        "Pneumonia Virus",
        "Sick",
        "healthy",
        "tuberculosis"
    };
};
