# 1. 规定 CMake 的最低版本要求
cmake_minimum_required(VERSION 3.4.1)
project(YoloInferenceEngine)

# 2. 【核心配置】定义 CANN SDK 在板子/交叉编译环境中的路径
# 注意：这个路径取决于你们板子固件里 CANN 的安装位置，通常算法同学知道
set(CANN_SDK_PATH "/usr/local/Ascend/ascend-toolkit/latest" CACHE PATH "Path to CANN SDK")

# 3. 指定 C++ 头文件的查找路径
include_directories(
    ${NATIVERENDER_ROOT}/include     # 鸿蒙 NAPI 的头文件路径（系统自带）
    ./                             # 当前目录
    ${CANN_SDK_PATH}/include       # 🌟 昇腾 CANN 的头文件路径（用于找 acl.h）
)

# 4. 声明要编译的动态库名字叫 "entry"（编译出来就是 libentry.so）
#    后面紧跟所有参与编译的 C++ 源文件
add_library(entry SHARED
    hello.cpp
    yolo_infer.cpp
)

# 5. 指定 CANN 动态库的链接路径（让编译器知道去哪找 libacl_runtime.so）
link_directories(
    ${CANN_SDK_PATH}/lib64
    ${CANN_SDK_PATH}/driver/lib64
)

# 6. 【核心配置】把你的 libentry.so 和系统底层的库紧紧链接在一起
target_link_libraries(entry PUBLIC
    libace_napi.z.so      # 鸿蒙底层 NAPI 库（必选）
    libhilog_ndk.z.so     # 鸿蒙原生日志库（用于在 C++ 打印 hilog）
    libacl_runtime.so     # 🌟 昇腾 CANN 核心运行时库（必选，驱动 310B NPU）
)