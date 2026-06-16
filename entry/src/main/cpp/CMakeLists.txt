cmake_minimum_required(VERSION 3.4.1)
project(YoloInferenceEngine)

set(CANN_SDK_PATH "${OHOS_NATIVERENDER_ROOT}/sdk" CACHE PATH "Path to native SDK")

include_directories(
    ${NATIVERENDER_ROOT}/include
    ./
)

add_library(entry SHARED
    hello.cpp
    yolo_infer.cpp
)

target_compile_options(entry PRIVATE
    -std=c++17
    -Wall
    -Wextra
    -Wno-unused-parameter
)

target_link_libraries(entry PUBLIC
    ace_napi.z
    hilog_ndk.z
    dl
)
