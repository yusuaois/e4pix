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

  // 解码结果结构
  typedef struct E4pixDecodeResult
  {
    // 错误信息
    int32_t error_code;
    char error_message[256];

    // 像素维度
    int32_t width;
    int32_t height;
    int32_t channels;         
    int32_t bits_per_channel; // 8 或 16

    // 像素数据
    uint8_t *pixels;
    size_t pixels_size; // 字节数 = width * height * channels * (bits/8)

    // EXIF 元数据
    int32_t orientation; // 1-8
    int32_t iso;
    float shutter;      // 秒
    float aperture;     // f-number
    float focal_length; // mm
    char camera_make[64];
    char camera_model[64];
    char lens_model[128];
    int64_t timestamp; // unix epoch seconds

    // 白平衡系数
    float cam_mul[4]; // R, G1, B, G2

    // 缩略图标记：1=该结果是相机内嵌缩略图
    int32_t is_embedded_thumb;
    int32_t thumb_format; // 0=bitmap, 1=jpeg
  } E4pixDecodeResult;

  // 解码相机内嵌缩略图
  E4PIX_API E4pixDecodeResult *e4pix_extract_thumb(const char *path);

  // 解码为预览RGB
  // 实时调整面板
  E4PIX_API E4pixDecodeResult *e4pix_decode_preview_fast(const char *path);
  E4PIX_API E4pixDecodeResult *e4pix_decode_preview(const char *path);

  // 解码为全分辨率RGB
  E4PIX_API E4pixDecodeResult *e4pix_decode_full(const char *path);

  // 仅元数据
  E4PIX_API E4pixDecodeResult *e4pix_read_metadata(const char *path);

  // 释放结果
  E4PIX_API void e4pix_free_result(E4pixDecodeResult *result);

  // 工具
  E4PIX_API const char *e4pix_libraw_version(void);

#ifdef __cplusplus
}
#endif

#endif // E4PIX_RAW_H