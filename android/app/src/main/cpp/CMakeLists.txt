cmake_minimum_required(VERSION 3.22)
project(e4pix_android)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

message(STATUS "==== e4pix_android build ====")
message(STATUS "  ANDROID_ABI:        ${ANDROID_ABI}")
message(STATUS "  ANDROID_PLATFORM:   ${ANDROID_PLATFORM}")
message(STATUS "  E4PIX_ROOT:         ${E4PIX_ROOT}")

if(NOT DEFINED E4PIX_ROOT)
    message(FATAL_ERROR "E4PIX_ROOT 未传入。检查 build.gradle 的 externalNativeBuild.arguments")
endif()

# 现有 native/raw_bridge
add_subdirectory(
    ${E4PIX_ROOT}/native/raw_bridge
    ${CMAKE_BINARY_DIR}/raw_bridge
)