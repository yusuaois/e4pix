import 'dart:math' as math;
import 'dart:typed_data';

import 'feature_detector.dart';
import 'image_warper.dart';
import 'transform_estimator.dart';

/// 图像对齐结果
class AlignmentResult {
  /// 对齐后的 RGBA 像素列表（已裁剪到有效区域）
  final List<Uint8List> images;

  /// 输出宽度（有效区域宽度）
  final int width;

  /// 输出高度（有效区域高度）
  final int height;

  const AlignmentResult({
    required this.images,
    required this.width,
    required this.height,
  });
}

/// 图像对齐服务
///
/// 将多张不同曝光的图像对齐到同一坐标系，
/// 消除手持拍摄时相机抖动导致的重影。
class ImageAlignmentService {
  ImageAlignmentService._();

  /// 特征检测降采样长边
  static const int _defaultTargetLongEdge = 600;

  /// 搜索窗口半径占图像短边比例
  static const double _searchRadiusFraction = 0.05;
  static const int _searchRadiusMin = 10;
  static const int _searchRadiusMax = 50;

  /// 最少匹配对数（仿射变换至少需要 3 对）
  static const int _minMatchesForAlignment = 3;

  /// 内部进度阶段边界
  static const double _progGrayscaleEnd = 0.05;
  static const double _progRefSelectEnd = 0.08;
  static const double _progAlignRange = 0.72;
  static const double _progWarpStart = 0.80;
  static const double _progWarpRange = 0.15;

  /// 对齐图像
  ///
  /// [images]：RGBA 像素列表（所有图像尺寸必须一致）
  /// [width], [height]：图像宽高
  /// [targetLongEdge]：特征检测用降采样长边（默认 600）
  /// [onProgress]：进度回调 0.0~1.0
  ///
  /// 返回对齐后的 [AlignmentResult]。
  /// 若对齐失败，返回原图（无变换）。
  static AlignmentResult align({
    required List<Uint8List> images,
    required int width,
    required int height,
    int targetLongEdge = _defaultTargetLongEdge,
    void Function(double)? onProgress,
  }) {
    final n = images.length;
    if (n <= 1) {
      return AlignmentResult(images: images, width: width, height: height);
    }

    // ── 阶段 1：灰度降采样（0%~5%） ──
    final longEdge = math.max(width, height);
    final scale = longEdge > targetLongEdge ? targetLongEdge / longEdge : 1.0;
    final dsW = (width * scale).round().clamp(1, width);
    final dsH = (height * scale).round().clamp(1, height);
    final dsScale = width / dsW; // 实际缩放比

    final grayImages = <Float32List>[];
    for (int i = 0; i < n; i++) {
      grayImages.add(_downsampleGrayscale(images[i], width, height, dsW, dsH));
      onProgress?.call(_progGrayscaleEnd * (i + 1) / n);
    }

    // ── 阶段 2：参考图选择（5%~8%） ──
    // 选对比度最高的图（Laplacian 方差最大）
    int refIdx = 0;
    double bestContrast = -1;
    for (int i = 0; i < n; i++) {
      final c = _laplacianVariance(grayImages[i], dsW, dsH);
      if (c > bestContrast) {
        bestContrast = c;
        refIdx = i;
      }
    }
    onProgress?.call(_progRefSelectEnd);

    // ── 阶段 3：逐图对齐（8%~80%） ──
    // 保存到 reference 的变换矩阵（source → reference 坐标）
    final forwardTransforms = <int, List<double>>{};

    final refGray = grayImages[refIdx];
    final refFeatures = FeatureDetector.detectCorners(refGray, dsW, dsH);

    for (int i = 0; i < n; i++) {
      if (i == refIdx) {
        onProgress?.call(_progRefSelectEnd + _progAlignRange * (i + 1) / n);
        continue;
      }

      final progress0 = _progRefSelectEnd + _progAlignRange * i / n;
      final progress1 = _progRefSelectEnd + _progAlignRange * (i + 1) / n;

      // 检测源图角点
      final srcFeatures = FeatureDetector.detectCorners(
        grayImages[i],
        dsW,
        dsH,
      );
      onProgress?.call(progress0 + (progress1 - progress0) * 0.3);

      if (srcFeatures.isEmpty || refFeatures.isEmpty) {
        // 特征不足，跳过对齐
        onProgress?.call(progress1);
        continue;
      }

      // NCC 块匹配
      final searchRadius = (dsW * _searchRadiusFraction).round().clamp(
        _searchRadiusMin,
        _searchRadiusMax,
      );
      final matches = FeatureDetector.matchFeatures(
        srcGray: grayImages[i],
        srcW: dsW,
        srcH: dsH,
        srcFeatures: srcFeatures,
        dstGray: refGray,
        dstW: dsW,
        dstH: dsH,
        searchRadius: searchRadius,
      );
      onProgress?.call(progress0 + (progress1 - progress0) * 0.6);

      if (matches.length < _minMatchesForAlignment) {
        onProgress?.call(progress1);
        continue;
      }

      // RANSAC 在降采样坐标系中运行（坐标一致性）
      final srcPoints = matches.map((m) => m.src).toList();
      final dstPoints = matches.map((m) => m.dst).toList();

      // RANSAC 估计变换
      final estimated = TransformEstimator.ransacEstimate(
        srcPoints: srcPoints,
        dstPoints: dstPoints,
        targetType: TransformType.affine,
      );

      if (estimated != null) {
        // 只放大平移分量：旋转/缩放/剪切与坐标尺度无关
        final m = List<double>.from(estimated.matrix);
        m[2] *= dsScale; // tx
        m[5] *= dsScale; // ty
        forwardTransforms[i] = m;
      }
      onProgress?.call(progress1);
    }

    // ── 阶段 4：全分辨率变换（80%~95%） ──
    final warped = List<Uint8List>.of(images);
    final sourceTransforms = <List<double>>[];

    for (int i = 0; i < n; i++) {
      if (i == refIdx) continue;
      final tf = forwardTransforms[i];
      if (tf != null) {
        sourceTransforms.add(tf);
      }
    }

    if (sourceTransforms.isNotEmpty) {
      for (int i = 0; i < n; i++) {
        if (i == refIdx) continue;
        final tf = forwardTransforms[i];
        if (tf != null) {
          warped[i] = ImageWarper.warpAffine(
            rgba: images[i],
            srcW: width,
            srcH: height,
            matrix: tf,
            outW: width,
            outH: height,
          );
        }
        onProgress?.call(_progWarpStart + _progWarpRange * (i + 1) / n);
      }
    } else {
      onProgress?.call(0.95);
    }

    // ── 阶段 5：裁剪有效区域（95%~100%） ──
    onProgress?.call(0.96);

    ValidRegion? validRegion;
    if (sourceTransforms.isNotEmpty) {
      validRegion = ImageWarper.computeValidRegion(
        transforms: sourceTransforms,
        srcW: width,
        srcH: height,
        refW: width,
        refH: height,
      );
    }

    final int outW, outH;
    final List<Uint8List> cropped;

    if (validRegion != null &&
        validRegion.width > 0 &&
        validRegion.height > 0) {
      outW = validRegion.width;
      outH = validRegion.height;
      cropped = <Uint8List>[];
      for (int i = 0; i < n; i++) {
        cropped.add(
          ImageWarper.cropRgba(warped[i], width, height, validRegion),
        );
      }
    } else {
      // 无法计算有效区域，保持原图
      outW = width;
      outH = height;
      cropped = warped;
    }

    onProgress?.call(1.0);
    return AlignmentResult(images: cropped, width: outW, height: outH);
  }

  /// 降采样 RGBA → 灰度 Float32（双线性插值）
  /// 当降采样比例 > 2.0 时，先做 3×3 box blur 抗锯齿
  static Float32List _downsampleGrayscale(
    Uint8List rgba,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    if (dstW >= srcW && dstH >= srcH) {
      return FeatureDetector.toGrayscale(rgba, srcW, srcH);
    }

    // 先转灰度
    Float32List gray = FeatureDetector.toGrayscale(rgba, srcW, srcH);

    final sx = srcW / dstW;
    final sy = srcH / dstH;

    // 降采样比例过大时，做 3×3 box blur 抗锯齿
    if (sx > 2.0 || sy > 2.0) {
      final blurred = Float32List(srcW * srcH);
      for (int y = 0; y < srcH; y++) {
        for (int x = 0; x < srcW; x++) {
          double sum = 0;
          int count = 0;
          for (int dy = -1; dy <= 1; dy++) {
            final ny = y + dy;
            if (ny < 0 || ny >= srcH) continue;
            for (int dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              if (nx < 0 || nx >= srcW) continue;
              sum += gray[ny * srcW + nx];
              count++;
            }
          }
          blurred[y * srcW + x] = sum / count;
        }
      }
      gray = blurred;
    }

    // 双线性插值降采样
    final result = Float32List(dstW * dstH);
    for (int dy = 0; dy < dstH; dy++) {
      final srcY = dy * sy;
      final y0 = srcY.floor().clamp(0, srcH - 1);
      final y1 = (y0 + 1).clamp(0, srcH - 1);
      final fy = srcY - y0;

      for (int dx = 0; dx < dstW; dx++) {
        final srcX = dx * sx;
        final x0 = srcX.floor().clamp(0, srcW - 1);
        final x1 = (x0 + 1).clamp(0, srcW - 1);
        final fx = srcX - x0;

        result[dy * dstW + dx] =
            gray[y0 * srcW + x0] * (1 - fx) * (1 - fy) +
            gray[y0 * srcW + x1] * fx * (1 - fy) +
            gray[y1 * srcW + x0] * (1 - fx) * fy +
            gray[y1 * srcW + x1] * fx * fy;
      }
    }
    return result;
  }

  /// Laplacian 方差（对比度度量）
  static double _laplacianVariance(Float32List gray, int w, int h) {
    double sum = 0;
    int count = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final c = gray[y * w + x];
        final lap =
            gray[(y - 1) * w + x] +
            gray[(y + 1) * w + x] +
            gray[y * w + x - 1] +
            gray[y * w + x + 1] -
            4 * c;
        sum += lap * lap;
        count++;
      }
    }
    return count > 0 ? sum / count : 0;
  }
}
