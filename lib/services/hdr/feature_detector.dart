import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../core/constants/hdr_constants.dart';

/// 检测到的特征点
class DetectedFeature {
  final double x;
  final double y;
  final double response;

  const DetectedFeature(this.x, this.y, this.response);
}

/// 特征匹配对
class FeatureMatch {
  final Offset src;
  final Offset dst;
  final double ncc;

  const FeatureMatch(this.src, this.dst, this.ncc);
}

/// 特征检测与匹配
class FeatureDetector {
  FeatureDetector._();

  static const double _harrisK = 0.04;
  static const int _harrisWindow = 5;
  static const double _harrisSigma = 1.5;
  static const double _harrisThresholdRatio = 0.01;
  static const int _nmsRadius = 3;
  static const int _patchRadius = 5;
  static const double _minNcc = 0.6;
  static const double _minStdEpsilon = 1e-8;

  /// RGBA → 灰度 Float32List [0, 1]
  static Float32List toGrayscale(Uint8List rgba, int w, int h) {
    final gray = Float32List(w * h);
    for (int i = 0; i < w * h; i++) {
      final idx = i * 4;
      gray[i] =
          (kLumaR * rgba[idx] +
              kLumaG * rgba[idx + 1] +
              kLumaB * rgba[idx + 2]) /
          255.0;
    }
    return gray;
  }

  /// Harris 角点检测
  ///
  /// 返回按响应强度降序排列的角点列表
  /// [maxFeatures] 上限（默认 500）
  static List<DetectedFeature> detectCorners(
    Float32List gray,
    int w,
    int h, {
    int maxFeatures = 500,
  }) {
    // 计算梯度（Sobel 3×3）
    final ix = Float32List(w * h);
    final iy = Float32List(w * h);

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final tl = gray[(y - 1) * w + x - 1];
        final tc = gray[(y - 1) * w + x];
        final tr = gray[(y - 1) * w + x + 1];
        final ml = gray[y * w + x - 1];
        final mr = gray[y * w + x + 1];
        final bl = gray[(y + 1) * w + x - 1];
        final bc = gray[(y + 1) * w + x];
        final br = gray[(y + 1) * w + x + 1];
        ix[y * w + x] = (tr + 2 * mr + br) - (tl + 2 * ml + bl);
        iy[y * w + x] = (bl + 2 * bc + br) - (tl + 2 * tc + tr);
      }
    }

    // Harris 响应（5×5 高斯加权窗口）
    final response = Float32List(w * h);
    final hw = _harrisWindow ~/ 2;
    // 高斯权重
    final gaussWeights = _buildGaussianWeights2D(_harrisWindow, _harrisSigma);

    for (int y = hw; y < h - hw; y++) {
      for (int x = hw; x < w - hw; x++) {
        double sxx = 0, syy = 0, sxy = 0;
        for (int dy = -hw; dy <= hw; dy++) {
          for (int dx = -hw; dx <= hw; dx++) {
            final idx = (y + dy) * w + x + dx;
            final gw = gaussWeights[(dy + hw) * _harrisWindow + dx + hw];
            final gx = ix[idx];
            final gy = iy[idx];
            sxx += gx * gx * gw;
            syy += gy * gy * gw;
            sxy += gx * gy * gw;
          }
        }
        final det = sxx * syy - sxy * sxy;
        final trace = sxx + syy;
        response[y * w + x] = det - _harrisK * trace * trace;
      }
    }

    // 阈值
    double maxResp = 0;
    for (int i = 0; i < w * h; i++) {
      if (response[i] > maxResp) maxResp = response[i];
    }
    final threshold = maxResp * _harrisThresholdRatio;
    if (threshold <= 0) return [];

    // 收集角点候选
    final candidates = <DetectedFeature>[];
    for (int y = hw; y < h - hw; y++) {
      for (int x = hw; x < w - hw; x++) {
        final r = response[y * w + x];
        if (r > threshold) {
          candidates.add(DetectedFeature(x.toDouble(), y.toDouble(), r));
        }
      }
    }

    // 非极大值抑制（NMS）
    candidates.sort((a, b) => b.response.compareTo(a.response));
    final result = <DetectedFeature>[];
    final suppressed = List<bool>.filled(w * h, false);

    for (final c in candidates) {
      final px = c.x.round();
      final py = c.y.round();
      if (px < 0 || px >= w || py < 0 || py >= h) continue;
      if (suppressed[py * w + px]) continue;

      result.add(c);
      if (result.length >= maxFeatures) break;

      // 抑制邻域
      for (int dy = -_nmsRadius; dy <= _nmsRadius; dy++) {
        for (int dx = -_nmsRadius; dx <= _nmsRadius; dx++) {
          final nx = px + dx;
          final ny = py + dy;
          if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
            suppressed[ny * w + nx] = true;
          }
        }
      }
    }

    return result;
  }

  /// NCC 块匹配
  ///
  /// [srcGray] / [dstGray]：源图和目标图灰度数据
  /// [srcFeatures]：源图角点
  /// [dstGray]：目标图灰度
  /// [searchRadius]：搜索窗口半径（像素）
  ///
  /// 返回匹配对列表（坐标为原图坐标）
  static List<FeatureMatch> matchFeatures({
    required Float32List srcGray,
    required int srcW,
    required int srcH,
    required List<DetectedFeature> srcFeatures,
    required Float32List dstGray,
    required int dstW,
    required int dstH,
    int searchRadius = 20,
  }) {
    final matches = <FeatureMatch>[];
    final pr = _patchRadius;
    final patchSize = pr * 2 + 1;

    for (final feat in srcFeatures) {
      final cx = feat.x.round();
      final cy = feat.y.round();

      // 源 patch 越界检查
      if (cx - pr < 0 || cx + pr >= srcW || cy - pr < 0 || cy + pr >= srcH) {
        continue;
      }

      // 提取源 patch 并预计算统计量
      final srcPatch = Float32List(patchSize * patchSize);
      double srcSum = 0;
      for (int dy = -pr; dy <= pr; dy++) {
        for (int dx = -pr; dx <= pr; dx++) {
          final v = srcGray[(cy + dy) * srcW + cx + dx];
          srcPatch[(dy + pr) * patchSize + dx + pr] = v;
          srcSum += v;
        }
      }
      final srcMean = srcSum / srcPatch.length;
      double srcVarSum = 0;
      for (int i = 0; i < srcPatch.length; i++) {
        final d = srcPatch[i] - srcMean;
        srcVarSum += d * d;
      }
      final srcStd = math.sqrt(srcVarSum);
      if (srcStd < _minStdEpsilon) continue; // 无纹理 patch

      // 在搜索窗口中找最佳匹配
      double bestNcc = _minNcc;
      int bestDx = 0, bestDy = 0;
      bool found = false;

      final sr = searchRadius;
      final minX = math.max(pr, cx - sr);
      final maxX = math.min(dstW - pr - 1, cx + sr);
      final minY = math.max(pr, cy - sr);
      final maxY = math.min(dstH - pr - 1, cy + sr);

      for (int sy = minY; sy <= maxY; sy++) {
        for (int sx = minX; sx <= maxX; sx++) {
          // 计算 NCC
          double dstSum = 0;
          for (int dy = -pr; dy <= pr; dy++) {
            for (int dx = -pr; dx <= pr; dx++) {
              dstSum += dstGray[(sy + dy) * dstW + sx + dx];
            }
          }
          final dstMean = dstSum / srcPatch.length;

          double dot = 0, dstVarSum = 0;
          for (int dy = -pr; dy <= pr; dy++) {
            for (int dx = -pr; dx <= pr; dx++) {
              final d = dstGray[(sy + dy) * dstW + sx + dx] - dstMean;
              final s = srcPatch[(dy + pr) * patchSize + dx + pr] - srcMean;
              dot += s * d;
              dstVarSum += d * d;
            }
          }
          final dstStd = math.sqrt(dstVarSum);
          if (dstStd < _minStdEpsilon) continue;

          final ncc = dot / (srcStd * dstStd);
          if (ncc > bestNcc) {
            bestNcc = ncc;
            bestDx = sx;
            bestDy = sy;
            found = true;
          }
        }
      }

      if (found) {
        matches.add(
          FeatureMatch(
            Offset(feat.x, feat.y),
            Offset(bestDx.toDouble(), bestDy.toDouble()),
            bestNcc,
          ),
        );
      }
    }

    return matches;
  }

  /// 构建 2D 高斯权重
  static Float32List _buildGaussianWeights2D(int size, double sigma) {
    final weights = Float32List(size * size);
    final center = size ~/ 2;
    final s2 = 2 * sigma * sigma;
    double sum = 0;

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final dy = y - center;
        final dx = x - center;
        final w = math.exp(-(dx * dx + dy * dy) / s2);
        weights[y * size + x] = w;
        sum += w;
      }
    }

    // 归一化
    for (int i = 0; i < weights.length; i++) {
      weights[i] /= sum;
    }
    return weights;
  }
}
