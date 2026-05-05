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

    file(GLOB_RECURSE LIBRAW_SOURCES
        "${LIBRAW_PATH}/src/*.cpp"
    )
    file(GLOB LIBRAW_INTERNAL_SOURCES
        "${LIBRAW_PATH}/internal/*.cpp"
    )
    list(APPEND LIBRAW_SOURCES ${LIBRAW_INTERNAL_SOURCES})

    # ⭐ 排除"伞状编译单元"，它们 include 了同目录的其他 .cpp，
    #   和我们逐个编译的 .cpp 重复定义符号
    list(FILTER LIBRAW_SOURCES EXCLUDE REGEX ".*_ph\\.cpp$")

    # 调试用：打印实际参与编译的文件数（建议保留几次构建确认无误）
    list(LENGTH LIBRAW_SOURCES _libraw_src_count)
    message(STATUS "  LibRaw source files to compile: ${_libraw_src_count}")

    add_library(libraw_static STATIC ${LIBRAW_SOURCES})
    target_include_directories(libraw_static PUBLIC ${LIBRAW_PATH})

    # ⭐ 关键：LIBRAW_NODLL 让 LibRaw 头文件不再使用 dllimport/dllexport
    # 必须用 PUBLIC，因为 e4pix_raw.cpp 也 #include <libraw/libraw.h>
    target_compile_definitions(libraw_static PUBLIC
        LIBRAW_NODLL          # ← 这个就是修复
        LIBRAW_NODNG
        LIBRAW_NOTHREADS
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
            /bigobj                                   # LibRaw 模板膨胀，需要大对象文件
            /wd4005                                     # 顺带屏蔽 ZERO 宏重定义警告（LibRaw 头里的）
        )
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
    target_compile_definitions(e4pix_raw PRIVATE
        _CRT_SECURE_NO_WARNINGS
    )
    target_compile_options(e4pix_raw PRIVATE
        /utf-8
        /wd4005     # 顺带屏蔽 ZERO 宏重定义警告（LibRaw 头里的）
    )
endif()

target_link_libraries(e4pix_raw PRIVATE ${LIBRAW_LIB})

set_target_properties(e4pix_raw PROPERTIES
    OUTPUT_NAME "e4pix_raw"
)

# 把要 bundle 的所有 DLL 暴露给上层
set(e4pix_raw_bundled_libraries
    $<TARGET_FILE:e4pix_raw>
    ${LIBRAW_RUNTIME_DLLS}
    PARENT_SCOPE
)

set_target_properties(e4pix_raw PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner"
)

# 针对多配置生成器（如 Visual Studio），确保 Debug/Release 路径正确
foreach(OUTPUTCONFIG ${CMAKE_CONFIGURATION_TYPES})
    string(TOUPPER ${OUTPUTCONFIG} OUTPUTCONFIG_UPPER)
    set_target_properties(e4pix_raw PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY_${OUTPUTCONFIG_UPPER} "${CMAKE_BINARY_DIR}/runner/${OUTPUTCONFIG}"
        LIBRARY_OUTPUT_DIRECTORY_${OUTPUTCONFIG_UPPER} "${CMAKE_BINARY_DIR}/runner/${OUTPUTCONFIG}"
        ARCHIVE_OUTPUT_DIRECTORY_${OUTPUTCONFIG_UPPER} "${CMAKE_BINARY_DIR}/runner/${OUTPUTCONFIG}"
    )
endforeach()