import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/constants/hdr_constants.dart';

/// Mertens 曝光融合算法
///
/// 不需要相机响应曲线，直接融合各曝光的亮部/暗部
/// 权重 = 对比度 × 饱和度 × 曝光良好度
/// 融合方式：拉普拉斯金字塔混合（按 RGB 通道独立处理，保留色彩）
class HdrFusionService {
  HdrFusionService._();

  /// 权重下限，避免零权重导致除零
  static const double _weightEpsilon = 1e-6;

  /// 曝光良好度高斯 sigma
  static const double _exposureSigma = 0.2;
  static const double _exposureSigmaSq2 = _exposureSigma * _exposureSigma * 2;

  /// 曝光融合
  ///
  /// [images] RGBA 像素列表，所有图片尺寸必须一致
  /// [w], [h] 图片宽高
  /// [levels] 金字塔层数（默认 5）
  /// [onProgress] 进度回调 0.0~1.0
  ///
  /// 返回融合后的 RGBA 像素
  static Uint8List fuse(
    List<Uint8List> images,
    int w,
    int h, {
    int levels = 5,
    void Function(double)? onProgress,
  }) {
    final n = images.length;
    if (n == 0) throw ArgumentError('No images');
    if (n == 1) return images[0];

    final pixelCount = w * h;

    // 计算每张图的权重图（单通道），占总进度 0%~40%
    final weights = <Float32List>[];
    for (int i = 0; i < n; i++) {
      weights.add(_computeWeight(images[i], w, h));
      onProgress?.call(0.4 * (i + 1) / n);
    }
    _normalizeWeights(weights, pixelCount);

    // 按 RGB 通道独立融合，占总进度 40%~90%
    final result = Uint8List(pixelCount * 4);
    for (int ch = 0; ch < 3; ch++) {
      // 提取每个通道的浮点数据
      final channelData = <Float32List>[];
      for (final img in images) {
        final data = Float32List(pixelCount);
        for (int i = 0; i < pixelCount; i++) {
          data[i] = img[i * 4 + ch] / 255.0;
        }
        channelData.add(data);
      }

      // 拉普拉斯金字塔融合
      final fused = _fuseChannel(channelData, weights, w, h, levels);

      // 写回结果
      for (int i = 0; i < pixelCount; i++) {
        result[i * 4 + ch] = (fused[i].clamp(0.0, 1.0) * 255).round();
      }

      onProgress?.call(0.4 + 0.5 * (ch + 1) / 3);
    }

    // Alpha 通道
    for (int i = 0; i < pixelCount; i++) {
      result[i * 4 + 3] = 255;
    }

    onProgress?.call(1.0);
    return result;
  }

  /// 单通道融合：拉普拉斯金字塔混合
  static Float32List _fuseChannel(
    List<Float32List> channelData,
    List<Float32List> weights,
    int w,
    int h,
    int levels,
  ) {
    final n = channelData.length;

    // 构建每张图的拉普拉斯金字塔
    final lapPyramids = <List<Float32List>>[];
    for (final data in channelData) {
      lapPyramids.add(_buildLaplacianPyramid(data, w, h, levels));
    }

    // 构建每张权重图的高斯金字塔
    final gaussPyramids = <List<Float32List>>[];
    for (final weight in weights) {
      gaussPyramids.add(_buildGaussianPyramid(weight, w, h, levels));
    }

    // 金字塔融合
    final blended = <Float32List>[];
    for (int l = 0; l < levels; l++) {
      // 直接使用金字塔实际尺寸，避免与下采样链的舍入不一致
      final size = lapPyramids[0][l].length;
      final result = Float32List(size);
      for (int img = 0; img < n; img++) {
        final lap = lapPyramids[img][l];
        final gauss = gaussPyramids[img][l];
        for (int i = 0; i < size; i++) {
          result[i] += lap[i] * gauss[i];
        }
      }
      blended.add(result);
    }

    // 重建
    return _reconstruct(blended, w, h, levels);
  }

  /// 权重 = 对比度 × 饱和度 × 曝光良好度
  static Float32List _computeWeight(Uint8List rgba, int w, int h) {
    final weight = Float32List(w * h);
    final contrast = _laplacianContrast(rgba, w, h);
    final saturation = _computeSaturation(rgba, w, h);
    final exposure = _computeWellExposedness(rgba, w, h);
    for (int i = 0; i < w * h; i++) {
      weight[i] = contrast[i] * saturation[i] * exposure[i];
    }
    return weight;
  }

  /// 拉普拉斯对比度
  static Float32List _laplacianContrast(Uint8List rgba, int w, int h) {
    final result = Float32List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;
        final i4 = idx * 4;
        final lum =
            kLumaR * rgba[i4] + kLumaG * rgba[i4 + 1] + kLumaB * rgba[i4 + 2];
        double lap = 0;
        int count = 0;
        if (x > 0) {
          final li = (y * w + x - 1) * 4;
          lap -=
              kLumaR * rgba[li] + kLumaG * rgba[li + 1] + kLumaB * rgba[li + 2];
          count++;
        }
        if (x < w - 1) {
          final ri = (y * w + x + 1) * 4;
          lap -=
              kLumaR * rgba[ri] + kLumaG * rgba[ri + 1] + kLumaB * rgba[ri + 2];
          count++;
        }
        if (y > 0) {
          final ti = ((y - 1) * w + x) * 4;
          lap -=
              kLumaR * rgba[ti] + kLumaG * rgba[ti + 1] + kLumaB * rgba[ti + 2];
          count++;
        }
        if (y < h - 1) {
          final bi = ((y + 1) * w + x) * 4;
          lap -=
              kLumaR * rgba[bi] + kLumaG * rgba[bi + 1] + kLumaB * rgba[bi + 2];
          count++;
        }
        lap += count * lum;
        result[idx] = (lap.abs() + _weightEpsilon);
      }
    }
    return result;
  }

  /// 饱和度
  static Float32List _computeSaturation(Uint8List rgba, int w, int h) {
    final result = Float32List(w * h);
    for (int i = 0; i < w * h; i++) {
      final i4 = i * 4;
      final r = rgba[i4] / 255.0;
      final g = rgba[i4 + 1] / 255.0;
      final b = rgba[i4 + 2] / 255.0;
      final mean = (r + g + b) / 3.0;
      final variance =
          (r - mean) * (r - mean) +
          (g - mean) * (g - mean) +
          (b - mean) * (b - mean);
      result[i] = (math.sqrt(variance / 3.0) + _weightEpsilon);
    }
    return result;
  }

  /// 曝光良好度
  static Float32List _computeWellExposedness(Uint8List rgba, int w, int h) {
    final result = Float32List(w * h);
    for (int i = 0; i < w * h; i++) {
      final i4 = i * 4;
      final r = rgba[i4] / 255.0;
      final g = rgba[i4 + 1] / 255.0;
      final b = rgba[i4 + 2] / 255.0;
      final er = math.exp(-((r - 0.5) * (r - 0.5)) / _exposureSigmaSq2);
      final eg = math.exp(-((g - 0.5) * (g - 0.5)) / _exposureSigmaSq2);
      final eb = math.exp(-((b - 0.5) * (b - 0.5)) / _exposureSigmaSq2);
      result[i] = (er * eg * eb + _weightEpsilon);
    }
    return result;
  }

  /// 归一化权重
  static void _normalizeWeights(List<Float32List> weights, int pixelCount) {
    for (int i = 0; i < pixelCount; i++) {
      double sum = 0;
      for (final w in weights) {
        sum += w[i];
      }
      if (sum > 0) {
        for (final w in weights) {
          w[i] = w[i] / sum;
        }
      }
    }
  }

  /// 高斯金字塔
  static List<Float32List> _buildGaussianPyramid(
    Float32List data,
    int w,
    int h,
    int levels,
  ) {
    final pyramid = <Float32List>[data];
    int cw = w, ch = h;
    Float32List current = data;
    for (int l = 1; l < levels; l++) {
      current = _downsample(current, cw, ch);
      pyramid.add(current);
      cw = (cw + 1) ~/ 2;
      ch = (ch + 1) ~/ 2;
    }
    return pyramid;
  }

  /// 拉普拉斯金字塔
  static List<Float32List> _buildLaplacianPyramid(
    Float32List data,
    int w,
    int h,
    int levels,
  ) {
    final pyramid = <Float32List>[];
    int cw = w, ch = h;
    Float32List current = data;

    for (int l = 0; l < levels - 1; l++) {
      final down = _downsample(current, cw, ch);
      final up = _upsample(down, cw, ch);
      final lap = Float32List(cw * ch);
      for (int i = 0; i < cw * ch; i++) {
        lap[i] = current[i] - up[i];
      }
      pyramid.add(lap);
      cw = (cw + 1) ~/ 2;
      ch = (ch + 1) ~/ 2;
      current = down;
    }
    pyramid.add(current);
    return pyramid;
  }

  /// 下采样（5-tap 高斯核 [1,4,6,4,1]/16）
  ///
  /// 使用 5×5 可分离高斯核（先列后行合并为 2D 查找），
  /// 比简单 2×2 平均更平滑，减少金字塔重建时的混叠伪影
  static Float32List _downsample(Float32List src, int w, int h) {
    final nw = (w + 1) ~/ 2;
    final nh = (h + 1) ~/ 2;
    final result = Float32List(nw * nh);

    for (int y = 0; y < nh; y++) {
      for (int x = 0; x < nw; x++) {
        // 源坐标（2x 采样）
        final sx = x * 2;
        final sy = y * 2;
        double sum = 0;
        double wSum = 0;

        // 5-tap 高斯核：行方向 [1,4,6,4,1]，列方向同理
        // 等价于 5×5 核，但用可分离实现：先列后行
        for (int dy = -2; dy <= 2; dy++) {
          final py = sy + dy;
          if (py < 0 || py >= h) continue;
          final ky = _gaussianTap5(dy);
          for (int dx = -2; dx <= 2; dx++) {
            final px = sx + dx;
            if (px < 0 || px >= w) continue;
            final kx = _gaussianTap5(dx);
            final k = ky * kx;
            sum += src[py * w + px] * k;
            wSum += k;
          }
        }
        result[y * nw + x] = wSum > 0 ? sum / wSum : 0;
      }
    }
    return result;
  }

  /// 5-tap 高斯核权重：[1, 4, 6, 4, 1] / 16
  static double _gaussianTap5(int offset) {
    switch (offset.abs()) {
      case 0:
        return 6.0;
      case 1:
        return 4.0;
      case 2:
        return 1.0;
      default:
        return 0.0;
    }
  }

  /// 上采样（双线性插值）
  static Float32List _upsample(Float32List src, int targetW, int targetH) {
    final srcW = (targetW + 1) ~/ 2;
    final srcH = (targetH + 1) ~/ 2;
    final result = Float32List(targetW * targetH);
    for (int y = 0; y < targetH; y++) {
      for (int x = 0; x < targetW; x++) {
        final sx = x / 2.0;
        final sy = y / 2.0;
        final x0 = sx.floor().clamp(0, srcW - 1);
        final y0 = sy.floor().clamp(0, srcH - 1);
        final x1 = (x0 + 1).clamp(0, srcW - 1);
        final y1 = (y0 + 1).clamp(0, srcH - 1);
        final fx = sx - x0;
        final fy = sy - y0;
        result[y * targetW + x] =
            src[y0 * srcW + x0] * (1 - fx) * (1 - fy) +
            src[y0 * srcW + x1] * fx * (1 - fy) +
            src[y1 * srcW + x0] * (1 - fx) * fy +
            src[y1 * srcW + x1] * fx * fy;
      }
    }
    return result;
  }

  /// 从拉普拉斯金字塔重建
  static Float32List _reconstruct(
    List<Float32List> pyramid,
    int w,
    int h,
    int levels,
  ) {
    // 预推算每层的精确尺寸（与 _downsample 的 (c+1)~/2 链一致）
    final levelW = List<int>.filled(levels, 0);
    final levelH = List<int>.filled(levels, 0);
    int cw = w, ch = h;
    for (int l = 0; l < levels; l++) {
      levelW[l] = cw;
      levelH[l] = ch;
      cw = (cw + 1) ~/ 2;
      ch = (ch + 1) ~/ 2;
    }

    Float32List current = pyramid[levels - 1];
    for (int l = levels - 2; l >= 0; l--) {
      final targetW = levelW[l];
      final targetH = levelH[l];
      final up = _upsample(current, targetW, targetH);
      final lap = pyramid[l];
      current = Float32List(targetW * targetH);
      for (int i = 0; i < targetW * targetH; i++) {
        current[i] = lap[i] + (i < up.length ? up[i] : 0);
      }
    }
    return current;
  }
}
