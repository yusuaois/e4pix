import 'dart:math' as math;
import 'dart:typed_data';

/// 有效区域（参考坐标系中的矩形）
class ValidRegion {
  final int x;
  final int y;
  final int width;
  final int height;

  const ValidRegion(this.x, this.y, this.width, this.height);
}

/// 图像变换器：仿射/透视变换 + 有效区域裁剪
class ImageWarper {
  ImageWarper._();

  static const double _perspectiveEpsilon = 1e-10;
  static const double _determinantEpsilon = 1e-12;
  static const int _boundarySamples = 20;

  /// 双线性插值仿射变换
  ///
  /// [rgba]：源图像 RGBA 像素
  /// [srcW], [srcH]：源图像尺寸
  /// [matrix]：3×3 行优先变换矩阵（source → reference）
  /// 返回变换后的 RGBA 像素（尺寸为 [outW] × [outH]，边界填黑）
  static Uint8List warpAffine({
    required Uint8List rgba,
    required int srcW,
    required int srcH,
    required List<double> matrix,
    required int outW,
    required int outH,
  }) {
    // 计算逆矩阵（reference → source）
    final inv = invertMatrix3(matrix);
    if (inv == null) {
      // 矩阵不可逆，返回黑图
      return Uint8List(outW * outH * 4);
    }

    final out = Uint8List(outW * outH * 4);
    final srcW1 = srcW - 1;
    final srcH1 = srcH - 1;

    for (int oy = 0; oy < outH; oy++) {
      for (int ox = 0; ox < outW; ox++) {
        // 逆变换：输出坐标 → 源坐标
        final w = inv[6] * ox + inv[7] * oy + inv[8];
        if (w.abs() < _perspectiveEpsilon) continue;
        final sx = (inv[0] * ox + inv[1] * oy + inv[2]) / w;
        final sy = (inv[3] * ox + inv[4] * oy + inv[5]) / w;

        // 半像素边界：双线性插值需要邻近像素，-0.5 确保不越界
        if (sx < -0.5 || sx > srcW - 0.5 || sy < -0.5 || sy > srcH - 0.5) {
          continue; // 黑色（默认 0）
        }

        // 双线性插值
        final x0 = sx.floor().clamp(0, srcW1);
        final y0 = sy.floor().clamp(0, srcH1);
        final x1 = (x0 + 1).clamp(0, srcW1);
        final y1 = (y0 + 1).clamp(0, srcH1);
        final fx = sx - x0;
        final fy = sy - y0;

        final i00 = (y0 * srcW + x0) * 4;
        final i10 = (y0 * srcW + x1) * 4;
        final i01 = (y1 * srcW + x0) * 4;
        final i11 = (y1 * srcW + x1) * 4;
        final oIdx = (oy * outW + ox) * 4;

        // R, G, B, A 各通道双线性插值
        for (int ch = 0; ch < 4; ch++) {
          final v =
              rgba[i00 + ch] * (1 - fx) * (1 - fy) +
              rgba[i10 + ch] * fx * (1 - fy) +
              rgba[i01 + ch] * (1 - fx) * fy +
              rgba[i11 + ch] * fx * fy;
          out[oIdx + ch] = v.round().clamp(0, 255);
        }
      }
    }

    return out;
  }

  /// 计算所有变换后的有效区域交集
  ///
  /// [transforms]：每张源图的变换矩阵（source → reference）
  /// [srcW], [srcH]：源图尺寸（假设所有源图尺寸相同）
  /// [refW], [refH]：参考图尺寸
  ///
  /// 返回所有变换后非黑区域的交集矩形
  static ValidRegion? computeValidRegion({
    required List<List<double>> transforms,
    required int srcW,
    required int srcH,
    required int refW,
    required int refH,
  }) {
    int minX = 0, minY = 0, maxX = refW, maxY = refH;

    for (final matrix in transforms) {
      // 采样源图边界点，变换到参考坐标系
      double tMinX = double.infinity, tMinY = double.infinity;
      double tMaxX = double.negativeInfinity, tMaxY = double.negativeInfinity;

      void updateBounds(double x, double y) {
        if (x < tMinX) tMinX = x;
        if (x > tMaxX) tMaxX = x;
        if (y < tMinY) tMinY = y;
        if (y > tMaxY) tMaxY = y;
      }

      // 上边 (y=0)
      for (int i = 0; i <= _boundarySamples; i++) {
        final sx = srcW * i / _boundarySamples;
        _transformPoint(matrix, sx, 0, updateBounds);
      }
      // 下边 (y=srcH)
      for (int i = 0; i <= _boundarySamples; i++) {
        final sx = srcW * i / _boundarySamples;
        _transformPoint(matrix, sx, srcH.toDouble(), updateBounds);
      }
      // 左边 (x=0)
      for (int i = 0; i <= _boundarySamples; i++) {
        final sy = srcH * i / _boundarySamples;
        _transformPoint(matrix, 0, sy, updateBounds);
      }
      // 右边 (x=srcW)
      for (int i = 0; i <= _boundarySamples; i++) {
        final sy = srcH * i / _boundarySamples;
        _transformPoint(matrix, srcW.toDouble(), sy, updateBounds);
      }

      // 与当前有效区域取交集
      minX = math.max(minX, tMinX.ceil());
      minY = math.max(minY, tMinY.ceil());
      maxX = math.min(maxX, tMaxX.floor());
      maxY = math.min(maxY, tMaxY.floor());
    }

    final w = maxX - minX;
    final h = maxY - minY;
    if (w <= 0 || h <= 0) return null;
    return ValidRegion(minX, minY, w, h);
  }

  static void _transformPoint(
    List<double> m,
    double x,
    double y,
    void Function(double, double) update,
  ) {
    final w = m[6] * x + m[7] * y + m[8];
    if (w.abs() < 1e-10) return;
    update((m[0] * x + m[1] * y + m[2]) / w, (m[3] * x + m[4] * y + m[5]) / w);
  }

  /// 裁剪 RGBA 图像到指定区域
  static Uint8List cropRgba(
    Uint8List rgba,
    int srcW,
    int srcH,
    ValidRegion region,
  ) {
    final out = Uint8List(region.width * region.height * 4);
    for (int y = 0; y < region.height; y++) {
      final srcRow = (y + region.y) * srcW + region.x;
      final dstRow = y * region.width;
      final byteLen = region.width * 4;
      final srcStart = srcRow * 4;
      final dstStart = dstRow * 4;
      if (srcStart >= 0 &&
          srcStart + byteLen <= rgba.length &&
          dstStart + byteLen <= out.length) {
        out.setRange(dstStart, dstStart + byteLen, rgba, srcStart);
      }
    }
    return out;
  }

  /// 3×3 矩阵求逆（行优先存储）
  static List<double>? invertMatrix3(List<double> m) {
    final a = m[0], b = m[1], c = m[2];
    final d = m[3], e = m[4], f = m[5];
    final g = m[6], h = m[7], i = m[8];

    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if (det.abs() < _determinantEpsilon) return null;
    final invDet = 1.0 / det;

    return [
      (e * i - f * h) * invDet,
      (c * h - b * i) * invDet,
      (b * f - c * e) * invDet,
      (f * g - d * i) * invDet,
      (a * i - c * g) * invDet,
      (c * d - a * f) * invDet,
      (d * h - e * g) * invDet,
      (b * g - a * h) * invDet,
      (a * e - b * d) * invDet,
    ];
  }
}
