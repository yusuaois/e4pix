#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <string>
#endif

#define E4PIX_BUILDING_DLL
#include "e4pix_raw.h"

#include <libraw/libraw.h>
#include <cstring>
#include <cstdlib>
#include <algorithm>
#include <new>

namespace
{
    int open_file(LibRaw &raw, const char *path)
    {
#ifdef _WIN32
        if (!path || !*path)
            return raw.open_file(path);

        int wlen = MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
        if (wlen <= 0)
            return raw.open_file(path);
        std::wstring wpath(wlen - 1, L'\0');
        MultiByteToWideChar(CP_UTF8, 0, path, -1, &wpath[0], wlen);
        return raw.open_file(wpath.c_str());
#else
        // 原生 UTF-8
        return raw.open_file(path);
#endif
    }

    // ---------- 内存与错误工具 ----------
    E4pixDecodeResult *alloc_result()
    {
        auto *r = static_cast<E4pixDecodeResult *>(std::calloc(1, sizeof(E4pixDecodeResult)));
        return r;
    }

    void set_error(E4pixDecodeResult *r, int code, const char *msg)
    {
        r->error_code = code != 0 ? code : -1;
        if (msg)
        {
            std::strncpy(r->error_message, msg, sizeof(r->error_message) - 1);
            r->error_message[sizeof(r->error_message) - 1] = '\0';
        }
    }

    void copy_metadata(LibRaw &raw, E4pixDecodeResult *r)
    {
        const auto &d = raw.imgdata;

        r->orientation = d.sizes.flip;
        r->iso = static_cast<int32_t>(d.other.iso_speed);
        r->shutter = d.other.shutter;
        r->aperture = d.other.aperture;
        r->focal_length = d.other.focal_len;
        r->timestamp = static_cast<int64_t>(d.other.timestamp);

        std::strncpy(r->camera_make, d.idata.make, sizeof(r->camera_make) - 1);
        std::strncpy(r->camera_model, d.idata.model, sizeof(r->camera_model) - 1);
        if (d.lens.Lens[0])
        {
            std::strncpy(r->lens_model, d.lens.Lens, sizeof(r->lens_model) - 1);
        }

        // 相机记录的 as-shot 白平衡乘数
        for (int i = 0; i < 4; ++i)
        {
            r->cam_mul[i] = d.color.cam_mul[i];
        }

        // CA 校正系数（由 e4pix_set_ca_correction 在解码前设定，
        // 作为 params.aber[] 而非图像元数据存储）
        r->ca_red = 0.0f;
        r->ca_blue = 0.0f;

        // ── 镜头元数据（makernotes）──
        // 卡口名称映射（LibRaw 内部枚举 → 可读字符串）
        const auto &mn = d.lens.makernotes;
        if (mn.Lens[0])
        {
            std::strncpy(r->lens_make, mn.Lens, sizeof(r->lens_make) - 1);
        }
        // LensFormat / CameraFormat — 直接存为数字或者用宏名
        std::snprintf(r->lens_format, sizeof(r->lens_format), "%u", mn.LensFormat);
        std::snprintf(r->camera_mount, sizeof(r->camera_mount), "%u", mn.CameraMount);
        r->min_focal = mn.MinFocal;
        r->max_focal = mn.MaxFocal;
        r->min_focus_distance = mn.MinFocusDistance;
        r->max_aperture = mn.MaxAp4MinFocal;
        r->min_aperture = mn.MinAp4MaxFocal;
        std::snprintf(r->focal_type, sizeof(r->focal_type), "%hd", mn.FocalType);

        // 也尝试从 d.lens 获取焦距范围
        if (r->min_focal <= 0.0f && d.lens.MinFocal > 0.0f)
            r->min_focal = d.lens.MinFocal;
        if (r->max_focal <= 0.0f && d.lens.MaxFocal > 0.0f)
            r->max_focal = d.lens.MaxFocal;

        // LensMount — 使用数字 ID
        std::snprintf(r->lens_mount, sizeof(r->lens_mount), "%u", mn.LensMount);
    }

    // ── CA 校正全局状态（被 e4pix_set_ca_correction 和 decode_internal 共享）──
    static float s_ca_red = 0.0f;
    static float s_ca_blue = 0.0f;
    static bool s_ca_enabled = false;

    // ---------- 预设处理参数 ----------
    // 输出 LINEAR 光，gamma=1
    void configure_for_develop(LibRaw &raw, bool half_size, int output_bps, int quality)
    {
        auto &p = raw.imgdata.params;

        p.half_size = half_size ? 1 : 0; // half size
        p.use_camera_wb = 1;             // 相机白平衡
        p.use_auto_wb = 0;
        p.output_bps = output_bps;
        p.output_color = 1;                   // sRGB 色彩矩阵
        p.no_auto_bright = 1;                 // 不自动拉伸亮度
        p.gamm[0] = 1.0;                      // gamma_power = 1
        p.gamm[1] = 1.0;                      // gamma_slope
        p.user_qual = (quality == 1) ? 3 : 2; // 3=AHD, 2=PPG
        p.no_interpolation = 0;
    }

    // 解码
    E4pixDecodeResult *decode_internal(const char *path, bool half_size, int output_bps, int quality)
    {
        auto *result = alloc_result();
        if (!result)
            return nullptr;

        LibRaw raw;
        int err = 0;

        err = open_file(raw, path);
        if (err != LIBRAW_SUCCESS)
        {
            set_error(result, err, libraw_strerror(err));
            return result;
        }

        configure_for_develop(raw, half_size, output_bps, quality);

        // 应用 CA 校正参数（aber[0]=red, aber[2]=blue）
        if (s_ca_enabled)
        {
            raw.imgdata.params.aber[0] = s_ca_red;
            raw.imgdata.params.aber[2] = s_ca_blue;
        }

        err = raw.unpack();
        if (err != LIBRAW_SUCCESS)
        {
            set_error(result, err, libraw_strerror(err));
            raw.recycle();
            return result;
        }

        err = raw.dcraw_process();
        if (err != LIBRAW_SUCCESS)
        {
            set_error(result, err, libraw_strerror(err));
            raw.recycle();
            return result;
        }

        int makemem_err = 0;
        libraw_processed_image_t *img = raw.dcraw_make_mem_image(&makemem_err);
        if (!img)
        {
            set_error(result, makemem_err,
                      makemem_err ? libraw_strerror(makemem_err) : "make_mem_image returned null");
            raw.recycle();
            return result;
        }

        if (img->type != LIBRAW_IMAGE_BITMAP)
        {
            set_error(result, -1001, "Expected bitmap output, got compressed type");
            LibRaw::dcraw_clear_mem(img);
            raw.recycle();
            return result;
        }

        // 拷贝像素数据
        result->width = img->width;
        result->height = img->height;
        result->channels = img->colors;
        result->bits_per_channel = img->bits;
        result->pixels_size = img->data_size;
        result->pixels = static_cast<uint8_t *>(std::malloc(img->data_size));
        if (!result->pixels)
        {
            set_error(result, -1002, "Out of memory copying pixels");
            LibRaw::dcraw_clear_mem(img);
            raw.recycle();
            return result;
        }
        std::memcpy(result->pixels, img->data, img->data_size);

        copy_metadata(raw, result);

        LibRaw::dcraw_clear_mem(img);
        raw.recycle();

        result->error_code = 0;
        return result;
    }

} // namespace

extern "C" E4pixDecodeResult *e4pix_extract_thumb(const char *path)
{
    auto *result = alloc_result();
    if (!result)
        return nullptr;

    LibRaw raw;
    int err = open_file(raw, path);
    if (err != LIBRAW_SUCCESS)
    {
        set_error(result, err, libraw_strerror(err));
        return result;
    }

    err = raw.unpack_thumb();
    if (err != LIBRAW_SUCCESS)
    {
        set_error(result, err, libraw_strerror(err));
        raw.recycle();
        return result;
    }

    int makemem_err = 0;
    libraw_processed_image_t *thumb = raw.dcraw_make_mem_thumb(&makemem_err);
    if (!thumb)
    {
        set_error(result, makemem_err,
                  makemem_err ? libraw_strerror(makemem_err) : "no thumbnail");
        raw.recycle();
        return result;
    }

    result->is_embedded_thumb = 1;
    result->thumb_format = (thumb->type == LIBRAW_IMAGE_JPEG) ? 1 : 0;
    result->width = thumb->width;
    result->height = thumb->height;
    result->channels = thumb->colors;
    result->bits_per_channel = thumb->bits;
    result->pixels_size = thumb->data_size;
    result->pixels = static_cast<uint8_t *>(std::malloc(thumb->data_size));
    if (result->pixels)
    {
        std::memcpy(result->pixels, thumb->data, thumb->data_size);
    }
    else
    {
        set_error(result, -1002, "OOM");
    }

    copy_metadata(raw, result);

    LibRaw::dcraw_clear_mem(thumb);
    raw.recycle();
    return result;
}

extern "C" E4pixDecodeResult *e4pix_decode_preview_fast(const char *path)
{
    fprintf(stderr, "[e4pix] preview_fast called\n");
    fflush(stderr);
    return decode_internal(path, /*half_size=*/true, /*bps=*/16, /*quality=*/0);
}

extern "C" E4pixDecodeResult *e4pix_decode_preview(const char *path)
{
    fprintf(stderr, "[e4pix] preview called\n");
    fflush(stderr);
    return decode_internal(path, /*half_size=*/false, /*bps=*/16, /*quality=*/0);
}

extern "C" E4pixDecodeResult *e4pix_decode_full(const char *path)
{
    return decode_internal(path, /*half_size=*/false, /*bps=*/16, /*quality=*/1);
}

extern "C" E4pixDecodeResult *e4pix_read_metadata(const char *path)
{
    auto *result = alloc_result();
    if (!result)
        return nullptr;

    LibRaw raw;
    int err = open_file(raw, path);
    if (err != LIBRAW_SUCCESS)
    {
        set_error(result, err, libraw_strerror(err));
        return result;
    }

    result->width = raw.imgdata.sizes.width;
    result->height = raw.imgdata.sizes.height;
    result->channels = 3;
    result->bits_per_channel = 0; // 未解码
    copy_metadata(raw, result);
    raw.recycle();

    result->error_code = 0;
    return result;
}

extern "C" void e4pix_free_result(E4pixDecodeResult *result)
{
    if (!result)
        return;
    if (result->pixels)
    {
        std::free(result->pixels);
        result->pixels = nullptr;
    }
    std::free(result);
}

// ──────────────────────────────────────────────────────────────────────
// CA 校正设置（修改全局 aber[]，影响后续所有 decode 调用）
// ──────────────────────────────────────────────────────────────────────
extern "C" void e4pix_set_ca_correction(int enabled, float ca_red, float ca_blue)
{
    s_ca_enabled = (enabled != 0);
    s_ca_red = ca_red;
    s_ca_blue = ca_blue;
}

// ──────────────────────────────────────────────────────────────────────
// 镜头元数据读取（不解码像素，仅返回镜头信息）
// ──────────────────────────────────────────────────────────────────────
extern "C" E4pixDecodeResult *e4pix_read_lens_metadata(const char *path)
{
    auto *result = alloc_result();
    if (!result)
        return nullptr;

    LibRaw raw;
    int err = open_file(raw, path);
    if (err != LIBRAW_SUCCESS)
    {
        set_error(result, err, libraw_strerror(err));
        return result;
    }

    // 仅 unpack（不解码），读取元数据后即可获取 lens 信息
    err = raw.unpack();
    if (err != LIBRAW_SUCCESS)
    {
        set_error(result, err, libraw_strerror(err));
        raw.recycle();
        return result;
    }

    result->width = raw.imgdata.sizes.width;
    result->height = raw.imgdata.sizes.height;
    result->channels = 3;
    result->bits_per_channel = 0; // 未解码
    copy_metadata(raw, result);
    raw.recycle();

    result->error_code = 0;
    return result;
}

extern "C" const char *e4pix_libraw_version(void)
{
    return LibRaw::version();
}