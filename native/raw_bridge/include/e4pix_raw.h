#ifndef E4PIX_RAW_H
#define E4PIX_RAW_H

#include <stdint.h>
#include <stddef.h>

#ifdef _WIN32
#ifdef E4PIX_BUILDING_DLL
#define E4PIX_API __declspec(dllexport)
#else
#define E4PIX_API __declspec(dllimport)
#endif
#else
#define E4PIX_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

  // ----------------------------------------------------------------------------
  // 解码结果结构 - C ABI 必须是 POD（Plain Old Data）
  // 字段顺序与 Dart 端 Struct 必须 1:1 对应
  // ----------------------------------------------------------------------------
  typedef struct E4pixDecodeResult
  {
    // 错误信息（error_code == 0 表示成功）
    int32_t error_code;
    char error_message[256];

    // 像素维度
    int32_t width;
    int32_t height;
    int32_t channels;         // 通常 3
    int32_t bits_per_channel; // 8 或 16

    // 像素数据：interleaved RGB(RGB)，linear 光（gamma=1.0）
    // 16-bit 时按 little-endian Uint16 存储
    uint8_t *pixels;
    size_t pixels_size; // 字节数 = width * height * channels * (bits/8)

    // EXIF 元数据
    int32_t orientation; // 1-8 (LibRaw flip 字段)
    int32_t iso;
    float shutter;      // 秒
    float aperture;     // f-number
    float focal_length; // mm
    char camera_make[64];
    char camera_model[64];
    char lens_model[128];
    int64_t timestamp; // unix epoch seconds

    // 相机白平衡系数（用于在 shader 中复现 as-shot WB）
    float cam_mul[4]; // R, G1, B, G2

    // 缩略图标记：1=该结果是相机内嵌缩略图（可能是 JPEG 编码字节）
    int32_t is_embedded_thumb;
    int32_t thumb_format; // 0=bitmap, 1=jpeg
  } E4pixDecodeResult;

  // ----------------------------------------------------------------------------
  // 公开函数
  // ----------------------------------------------------------------------------

  // 解码相机内嵌缩略图（极快，<100ms）。
  // 适用于文件浏览器、缩略图墙。
  // 返回指针的所有权属于调用方，必须用 e4pix_free_result 释放
  E4PIX_API E4pixDecodeResult *e4pix_extract_thumb(const char *path);

  // 解码为预览级 RGB（half-size + 16-bit linear）。
  // 用于实时调整面板。典型耗时 200-800ms。
  E4PIX_API E4pixDecodeResult *e4pix_decode_preview(const char *path);

  // 解码为全分辨率 16-bit linear RGB。用于导出。
  E4PIX_API E4pixDecodeResult *e4pix_decode_full(const char *path);

  // 仅读元数据（不做解码，<10ms）
  E4PIX_API E4pixDecodeResult *e4pix_read_metadata(const char *path);

  // 释放结果。安全接受 NULL。
  E4PIX_API void e4pix_free_result(E4pixDecodeResult *result);

  // 工具
  E4PIX_API const char *e4pix_libraw_version(void);

#ifdef __cplusplus
}
#endif

#endif // E4PIX_RAW_H