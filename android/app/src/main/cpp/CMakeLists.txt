cmake_minimum_required(VERSION 3.22.1)
project(fknotes_mnn LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(FKNOTES_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../..")
add_library(fknotes_mnn SHARED
    "${FKNOTES_ROOT}/native/mnn/fknotes_mnn_bridge.cpp")
target_include_directories(fknotes_mnn PRIVATE
    "${FKNOTES_ROOT}/native/mnn")
target_compile_options(fknotes_mnn PRIVATE -fvisibility=hidden)
target_link_options(fknotes_mnn PRIVATE "-Wl,-z,max-page-size=16384")

if(ANDROID_ABI STREQUAL "arm64-v8a")
    if(NOT DEFINED MNN_RUNTIME_ROOT OR NOT DEFINED MNN_HEADERS_ROOT)
        message(FATAL_ERROR "MNN runtime paths were not provided")
    endif()
    target_compile_definitions(fknotes_mnn PRIVATE FKNOTES_MNN_RUNTIME=1)
    target_include_directories(fknotes_mnn PRIVATE "${MNN_HEADERS_ROOT}")

    # MNN Chat's Android runtime is built with MNN_SEP_BUILD=OFF and exports
    # the LLM, multimodal, CV and audio APIs from one verified library.
    add_library(MNN SHARED IMPORTED)
    set_target_properties(MNN PROPERTIES
        IMPORTED_LOCATION "${MNN_RUNTIME_ROOT}/libMNN.so")
    target_link_libraries(fknotes_mnn PRIVATE
        MNN android log)
endif()
