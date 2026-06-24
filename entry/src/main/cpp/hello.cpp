#include "napi/native_api.h"
#include "yolo_infer.h"
#include <cstring>
#include <string>
#include <vector>
#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0000
#define LOG_TAG "YoloNAPI"

struct InitAsyncData {
    napi_async_work work;
    napi_deferred deferred;
    YoloInference* engine;
    std::string modelPath;
    bool result;
};

struct InferAsyncData {
    napi_async_work work;
    napi_deferred deferred;
    YoloInference* engine;
    void* imageData;
    size_t imageSize;
    int origWidth;
    int origHeight;
    std::vector<DetectionResult> results;
    bool engineFailed;
};

static YoloInference* g_engine = nullptr;

static void InitExecute(napi_env env, void* data) {
    InitAsyncData* asyncData = static_cast<InitAsyncData*>(data);

    if (g_engine != nullptr) {
        delete g_engine;
        g_engine = nullptr;
    }

    g_engine = new YoloInference();

    bool devOk = g_engine->InitDevice(0);
    if (!devOk) {
        asyncData->result = false;
        OH_LOG_ERROR(LOG_APP, "[NAPI] InitDevice failed");
        delete g_engine;
        g_engine = nullptr;
        return;
    }

    asyncData->result = g_engine->LoadModel(asyncData->modelPath);
    if (!asyncData->result) {
        OH_LOG_ERROR(LOG_APP, "[NAPI] LoadModel failed, path=%{public}s",
                     asyncData->modelPath.c_str());
        delete g_engine;
        g_engine = nullptr;
    } else {
        OH_LOG_INFO(LOG_APP, "[NAPI] LoadModel success");
    }
}

static void InitComplete(napi_env env, napi_status status, void* data) {
    InitAsyncData* asyncData = static_cast<InitAsyncData*>(data);

    napi_value result;
    napi_get_boolean(env, asyncData->result, &result);

    if (asyncData->result) {
        napi_resolve_deferred(env, asyncData->deferred, result);
    } else {
        napi_value errorMsg;
        napi_create_string_utf8(env, "Engine initialization failed. Check model file and CANN environment.", 
                                NAPI_AUTO_LENGTH, &errorMsg);
        napi_value error;
        napi_create_error(env, nullptr, errorMsg, &error);
        napi_reject_deferred(env, asyncData->deferred, error);
    }

    napi_delete_async_work(env, asyncData->work);
    delete asyncData;
}

static napi_value InitYoloEngine(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_error(env, nullptr, "Expected 1 argument: modelPath");
        return nullptr;
    }

    size_t pathLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &pathLen);
    std::string modelPath(pathLen, '\0');
    napi_get_value_string_utf8(env, args[0], &modelPath[0], pathLen + 1, &pathLen);

    napi_value promise;
    napi_deferred deferred;
    napi_create_promise(env, &deferred, &promise);

    InitAsyncData* asyncData = new InitAsyncData();
    asyncData->deferred = deferred;
    asyncData->modelPath = modelPath;
    asyncData->engine = nullptr;
    asyncData->result = false;

    napi_value resourceName;
    napi_create_string_utf8(env, "InitYoloEngine", NAPI_AUTO_LENGTH, &resourceName);

    napi_create_async_work(env, nullptr, resourceName,
                           InitExecute, InitComplete,
                           asyncData, &asyncData->work);
    napi_queue_async_work(env, asyncData->work);

    return promise;
}

static void InferExecute(napi_env env, void* data) {
    InferAsyncData* asyncData = static_cast<InferAsyncData*>(data);

    if (g_engine == nullptr) {
        OH_LOG_ERROR(LOG_APP, "[NAPI] Engine not initialized!");
        asyncData->engineFailed = true;
        return;
    }

    asyncData->engineFailed = false;
    asyncData->results = g_engine->DoInference(
        asyncData->imageData, asyncData->imageSize,
        asyncData->origWidth, asyncData->origHeight);

    OH_LOG_INFO(LOG_APP, "[NAPI] Inference done, count=%{public}zu",
                asyncData->results.size());
}

static void InferComplete(napi_env env, napi_status status, void* data) {
    InferAsyncData* asyncData = static_cast<InferAsyncData*>(data);

    if (asyncData->engineFailed) {
        napi_value errorMsg;
        napi_create_string_utf8(env, "Engine not initialized", NAPI_AUTO_LENGTH, &errorMsg);
        napi_reject_deferred(env, asyncData->deferred, errorMsg);
    } else {
        napi_value jsArray;
        napi_create_array_with_length(env, asyncData->results.size(), &jsArray);

        for (size_t i = 0; i < asyncData->results.size(); i++) {
            const DetectionResult& det = asyncData->results[i];

            napi_value obj;
            napi_create_object(env, &obj);

            napi_value x, y, w, h, conf, classId, label;
            napi_create_double(env, static_cast<double>(det.x), &x);
            napi_create_double(env, static_cast<double>(det.y), &y);
            napi_create_double(env, static_cast<double>(det.width), &w);
            napi_create_double(env, static_cast<double>(det.height), &h);
            napi_create_double(env, static_cast<double>(det.confidence), &conf);
            napi_create_int32(env, det.classId, &classId);
            napi_create_string_utf8(env, det.label.c_str(), NAPI_AUTO_LENGTH, &label);

            napi_set_named_property(env, obj, "x", x);
            napi_set_named_property(env, obj, "y", y);
            napi_set_named_property(env, obj, "width", w);
            napi_set_named_property(env, obj, "height", h);
            napi_set_named_property(env, obj, "confidence", conf);
            napi_set_named_property(env, obj, "classId", classId);
            napi_set_named_property(env, obj, "label", label);

            napi_set_element(env, jsArray, i, obj);
        }

        napi_resolve_deferred(env, asyncData->deferred, jsArray);
    }

    if (asyncData->imageData != nullptr) {
        delete[] static_cast<uint8_t*>(asyncData->imageData);
        asyncData->imageData = nullptr;
    }

    napi_delete_async_work(env, asyncData->work);
    delete asyncData;
}

static napi_value RunYoloInference(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_error(env, nullptr, "Expected at least 1 argument: imageBuffer");
        return nullptr;
    }

    void* arrayBuffer = nullptr;
    size_t bufferSize = 0;
    napi_status bufStatus = napi_get_arraybuffer_info(env, args[0], &arrayBuffer, &bufferSize);
    if (bufStatus != napi_ok || arrayBuffer == nullptr || bufferSize == 0) {
        napi_throw_error(env, nullptr, "Invalid ArrayBuffer argument");
        return nullptr;
    }

    int32_t origWidth = 640;
    int32_t origHeight = 640;
    if (argc >= 2) {
        napi_get_value_int32(env, args[1], &origWidth);
    }
    if (argc >= 3) {
        napi_get_value_int32(env, args[2], &origHeight);
    }

    napi_value promise;
    napi_deferred deferred;
    napi_create_promise(env, &deferred, &promise);

    InferAsyncData* asyncData = new InferAsyncData();
    asyncData->deferred = deferred;
    asyncData->engine = g_engine;
    asyncData->imageSize = bufferSize;
    asyncData->origWidth = origWidth;
    asyncData->origHeight = origHeight;
    asyncData->engineFailed = false;

    asyncData->imageData = new uint8_t[bufferSize];
    std::memcpy(asyncData->imageData, arrayBuffer, bufferSize);

    napi_value resourceName;
    napi_create_string_utf8(env, "RunYoloInference", NAPI_AUTO_LENGTH, &resourceName);

    napi_create_async_work(env, nullptr, resourceName,
                           InferExecute, InferComplete,
                           asyncData, &asyncData->work);
    napi_queue_async_work(env, asyncData->work);

    return promise;
}

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"initYoloEngine", nullptr, InitYoloEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"runYoloInference", nullptr, RunYoloInference, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

EXTERN_C_START
static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = {0}};
#ifdef __cplusplus
}
#endif
__attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&demoModule);
}
