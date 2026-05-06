cmake_minimum_required(VERSION 3.16)
project(e4pix_raw VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

message(STATUS "==== e4pix_raw build ====")
message(STATUS "  CMAKE_SOURCE_DIR         = ${CMAKE_SOURCE_DIR}")
message(STATUS "  CMAKE_CURRENT_SOURCE_DIR = ${CMAKE_CURRENT_SOURCE_DIR}")

set(LIBRAW_TARGET_FOUND FALSE)
# ============================================================================
# Windows 上探测 vcpkg（Android/Linux/macOS 跳过）
# ============================================================================
if(WIN32 AND NOT ANDROID AND NOT LIBRAW_TARGET_FOUND)
    set(_VCPKG_CANDIDATES "")
    if(DEFINED ENV{VCPKG_ROOT})
        list(APPEND _VCPKG_CANDIDATES "$ENV{VCPKG_ROOT}/installed/x64-windows")
    endif()
    list(APPEND _VCPKG_CANDIDATES
        "C:/vcpkg/installed/x64-windows"
        "C:/dev/vcpkg/installed/x64-windows"
    )
    foreach(_vcp ${_VCPKG_CANDIDATES})
        if(EXISTS "${_vcp}/include/libraw/libraw.h" AND EXISTS "${_vcp}/lib/raw.lib")
            message(STATUS "  ✅ Found LibRaw via vcpkg: ${_vcp}")
            set(LIBRAW_VCPKG_ROOT "${_vcp}")
            set(LIBRAW_TARGET_FOUND TRUE)
            break()
        endif()
    endforeach()

    if(LIBRAW_TARGET_FOUND)
        add_library(libraw_imported STATIC IMPORTED GLOBAL)
        set_target_properties(libraw_imported PROPERTIES
            IMPORTED_LOCATION "${LIBRAW_VCPKG_ROOT}/lib/raw.lib"
            INTERFACE_INCLUDE_DIRECTORIES "${LIBRAW_VCPKG_ROOT}/include"
        )
        set(LIBRAW_LIB libraw_imported)
        set(LIBRAW_RUNTIME_DLLS
            "${LIBRAW_VCPKG_ROOT}/bin/raw.dll"
        )
    endif()
endif()
# ============================================================================
# 从 third_party/libraw 源码构建（不依赖 vcpkg）
# ============================================================================
if(NOT LIBRAW_TARGET_FOUND)
    set(LIBRAW_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/libraw")

    if(NOT EXISTS "${LIBRAW_PATH}/libraw/libraw.h")
        message(FATAL_ERROR
            "\nLibRaw not found anywhere.\n"
            "  Tried vcpkg paths: ${_VCPKG_CANDIDATES}\n"
            "  Tried source path: ${LIBRAW_PATH}\n"
            "\nFix one of:\n"
            "  - Install via vcpkg: vcpkg install libraw:x64-windows\n"
            "  - Clone source: git clone https://github.com/LibRaw/LibRaw.git ${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/libraw\n"
        )
    endif()

    message(STATUS "  ✅ Building LibRaw from source: ${LIBRAW_PATH}")

    file(GLOB_RECURSE LIBRAW_SOURCES "${LIBRAW_PATH}/src/*.cpp")
    file(GLOB LIBRAW_INTERNAL_SOURCES "${LIBRAW_PATH}/internal/*.cpp")
    list(APPEND LIBRAW_SOURCES ${LIBRAW_INTERNAL_SOURCES})
    list(FILTER LIBRAW_SOURCES EXCLUDE REGEX ".*_ph\\.cpp$")

    list(LENGTH LIBRAW_SOURCES _libraw_src_count)
    message(STATUS "  LibRaw source files to compile: ${_libraw_src_count}")

    add_library(libraw_static STATIC ${LIBRAW_SOURCES})
    target_include_directories(libraw_static PUBLIC ${LIBRAW_PATH})

    target_compile_definitions(libraw_static PUBLIC
        LIBRAW_NODLL
        LIBRAW_NODNG
        LIBRAW_NOTHREADS
        NO_JPEG
        NO_LCMS
        NO_JASPER
    )

    if(MSVC)
        target_compile_definitions(libraw_static PRIVATE
            _CRT_SECURE_NO_WARNINGS
            WIN32
            _WINDOWS
        )
        target_compile_options(libraw_static PRIVATE
            /utf-8                                    # 处理 LibRaw 的 UTF-8 源码
            /wd4267 /wd4244 /wd4018 /wd4146           # size_t/int 转换警告
            /wd4819 /wd4251 /wd4273 /wd4996           # UTF-8/dll接口/链接不一致/POSIX 弃用
            /bigobj                                   # LibRaw 模板膨胀
            /wd4005                                   # ZERO 宏重定义警告
        )
    else()
        target_compile_options(libraw_static PRIVATE
            -Wno-narrowing
            -Wno-implicit-function-declaration
            -Wno-unused-result
            -Wno-format-security
            -Wno-attributes
            -Wno-deprecated-declarations
        )
        set_target_properties(libraw_static PROPERTIES POSITION_INDEPENDENT_CODE ON)
    endif()

    set(LIBRAW_LIB libraw_static)
    set(LIBRAW_TARGET_FOUND TRUE)
    set(LIBRAW_RUNTIME_DLLS "")
endif()

# ============================================================================
# 桥接动态库
# ============================================================================
add_library(e4pix_raw SHARED
    src/e4pix_raw.cpp
)

target_include_directories(e4pix_raw PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

if(MSVC)
    target_compile_definitions(e4pix_raw PRIVATE _CRT_SECURE_NO_WARNINGS)
    target_compile_options(e4pix_raw PRIVATE /utf-8 /wd4005)
endif()

target_link_libraries(e4pix_raw PRIVATE ${LIBRAW_LIB})

# logcat
if(ANDROID)
    target_link_libraries(e4pix_raw PRIVATE log)
endif()

set_target_properties(e4pix_raw PROPERTIES OUTPUT_NAME "e4pix_raw")

if(WIN32 AND NOT ANDROID)
    set(e4pix_raw_bundled_libraries
        $<TARGET_FILE:e4pix_raw>
        ${LIBRAW_RUNTIME_DLLS}
        PARENT_SCOPE
    )
endif()