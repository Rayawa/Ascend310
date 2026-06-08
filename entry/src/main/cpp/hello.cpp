#include "napi/native_api.h"
#include <vector>
#include <string>

// 模拟 YOLO 检测结果结构体
struct DetectBoxResult {
    float x;
    float y;
    float w;
    float h;
    float confidence;
    std::string label;
};

// 实际跑 CANN 推理的后台线程函数
void ExecuteInference(napi_env env, void* data) {
    // 这里由算法同学实现：
    // 1. 从 data 中取出图片原本的 ArrayBuffer 裸指针
    // 2. 将数据输入到 Ascend 310B 的 DVPP 进行缩放、量化
    // 3. 调用 aclmdlExecute 驱动 CANN 得到模型输出结果
}

// 推理完成后，把 C++ 的 vector 翻译为 ArkTS 能识别的 Array<Object>
void CompleteInference(napi_env env, napi_status status, void* data) {
    // 假装这是 CANN 算出来的最终结果
    std::vector<DetectBoxResult> cppResults = {
        {0.1f, 0.2f, 0.3f, 0.4f, 0.92f, "person"},
        {0.5f, 0.1f, 0.2f, 0.3f, 0.88f, "car"}
    };

    napi_value jsArray;
    napi_create_array_with_length(env, cppResults.size(), &jsArray);

    for (size_t i = 0; i < cppResults.size(); i++) {
        napi_value obj;
        napi_create_object(env, &obj);

        napi_value x, y, w, h, conf, label;
        napi_create_double(env, cppResults[i].x, &x);
        napi_create_double(env, cppResults[i].y, &y);
        napi_create_double(env, cppResults[i].w, &w);
        napi_create_double(env, cppResults[i].h, &h);
        napi_create_double(env, cppResults[i].confidence, &conf);
        napi_create_string_utf8(env, cppResults[i].label.c_str(), NAPI_AUTO_LENGTH, &label);

        napi_set_named_property(env, obj, "x", x);
        napi_set_named_property(env, obj, "y", y);
        napi_set_named_property(env, obj, "width", w);
        napi_set_named_property(env, obj, "height", h);
        napi_set_named_property(env, obj, "confidence", conf);
        napi_set_named_property(env, obj, "label", label);

        napi_set_element(env, jsArray, i, obj);
    }
    
    // 最终通过之前创建的 deferred 对象 resolve(jsArray) 返回给前端的 Promise
}

// 映射给 ArkTS 的入口
static napi_value RunYoloInferenceAsync(napi_env env, napi_callback_info info) {
    // 1. 获取 ArkTS 传来的入参（ArrayBuffer）
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 2. 创建鸿蒙异步 Promise
    napi_value promise;
    napi_deferred deferred;
    napi_create_promise(env, &deferred, &promise);

    // 3. 创建异步工作队列异步调用 ExecuteInference 和 CompleteInference
    napi_value resourceName;
    napi_create_string_utf8(env, "YoloInferenceJob", NAPI_AUTO_LENGTH, &resourceName);
    
    napi_async_work work;
    napi_create_async_work(env, nullptr, resourceName, ExecuteInference, CompleteInference, nullptr, &work);
    napi_queue_async_work(env, work);

    return promise; // 返回给前端 Promise 对象
}

// NAPI 模块初始化与函数导出
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "runYoloInference", nullptr, RunYoloInferenceAsync, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_START
static napi_module demoModule = { .nm_version = 1, .nm_flags = 0, .nm_filename = nullptr, .nm_register_func = Init, .nm_modname = "entry", .nm_priv = ((void*)0), .reserved = {0} };
#ifdef __cplusplus
}
#endif
__attribute__((constructor)) void RegisterEntryModule(void) { napi_module_register(&demoModule); }