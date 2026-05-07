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

# JNI 库
set(JNI_LIBS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}")

# libusb-1.0
add_library(libusb1.0 SHARED IMPORTED)
set_target_properties(libusb1.0 PROPERTIES
    IMPORTED_LOCATION "${JNI_LIBS_DIR}/libusb-1.0.so")

# libltdl
add_library(ltdl SHARED IMPORTED)
set_target_properties(ltdl PROPERTIES
    IMPORTED_LOCATION "${JNI_LIBS_DIR}/libltdl.so")

# libgphoto2_port
add_library(libgphoto2_port SHARED IMPORTED)
set_target_properties(libgphoto2_port PROPERTIES
    IMPORTED_LOCATION "${JNI_LIBS_DIR}/libgphoto2_port.so")

# libgphoto2
add_library(libgphoto2 SHARED IMPORTED)
set_target_properties(libgphoto2 PROPERTIES
    IMPORTED_LOCATION "${JNI_LIBS_DIR}/libgphoto2.so")

# JNI Bridge
add_library(e4pix_jni SHARED
    e4pix_gphoto2_jni.cpp
)

target_include_directories(e4pix_jni PRIVATE
    ${E4PIX_ROOT}/third_party/libgphoto2-headers
)

target_link_libraries(e4pix_jni
    libgphoto2
    libgphoto2_port
    libusb1.0
    ltdl
    log
    android
)

message(STATUS "JNI lib will be at: $<TARGET_FILE:e4pix_jni>")