import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models/watermark_config.dart';
import '../native/raw_bridge.dart';

/// 水印边框统一几何布局模型
///
/// **核心设计**：
/// - 所有尺寸基于固定宽度的参考画布（[kBaseWidth]=1000px），不依赖屏幕尺寸。
/// - Preview 和 Export 共用此模型
/// - 导出时用 [exportScale] 将参考尺寸映射到全分辨率像素。
class WatermarkGeometry {
  /// 参考画布基准宽度（逻辑像素）。
  static const double kBaseWidth = 1000.0;

  // ────────────────────────────────────────────────────────────
  // 输出（均为参考画布上的绝对像素）
  // ────────────────────────────────────────────────────────────

  /// 参考画布尺寸
  final Size canvasSize;

  /// 原图显示区域（圆角裁剪区）
  final Rect imageRect;

  /// 信息层区域（Logo + EXIF）
  final Rect infoRect;

  /// 边框宽度
  final double borderWidth;

  /// 圆角半径
  final double cornerRadius;

  /// 阴影模糊半径
  final double shadowBlur;

  /// 阴影 Y 偏移
  final double shadowOffsetY;

  /// 文字字号
  final double fontSize;

  /// Logo 最大高度
  final double logoMaxH;

  /// 文字/内容边距
  final double textPad;

  /// 是否有 Logo
  final bool hasLogo;

  /// 是否有 EXIF
  final bool hasExif;

  /// 信息层在原图 Z 轴之后（原图覆盖信息层）
  final bool infoBehindImage;

  /// 原图缩放比例（config.imageScale 的快照）
  final double imageScale;

  const WatermarkGeometry({
    required this.canvasSize,
    required this.imageRect,
    required this.infoRect,
    required this.borderWidth,
    required this.cornerRadius,
    required this.shadowBlur,
    required this.shadowOffsetY,
    required this.fontSize,
    required this.logoMaxH,
    required this.textPad,
    required this.hasLogo,
    required this.hasExif,
    required this.infoBehindImage,
    required this.imageScale,
  });

  // ────────────────────────────────────────────────────────────
  // 工厂方法
  // ────────────────────────────────────────────────────────────

  /// 根据图片宽高比和水印配置计算布局。
  ///
  /// [imageAspectRatio] = width / height（裁剪后的原图宽高比）。
  /// [showExif] 覆盖 config.showExif，允许调用方传入 EXIF 是否真正有内容。
  factory WatermarkGeometry.compute({
    required double imageAspectRatio,
    required WatermarkConfig config,
    required bool hasLogo,
    required bool showExif,
  }) {
    final borderW = config.borderWidth;
    final imageScale = config.imageScale.clamp(0.01, 1.0);
    final placement = config.infoPlacement;
    final isOverlay = placement.isOverlay;

    // ── 原图显示区域 ──
    final availW = (kBaseWidth - 2 * borderW).clamp(1.0, kBaseWidth);
    final imageDisplayW = availW * imageScale;
    final imageDisplayH = imageDisplayW / imageAspectRatio;

    // ── 信息层高度 ──
    final logoH = hasLogo ? config.logoSize * 48.0 : 0.0;
    final estTextH = showExif ? config.fontSize * 2.0 : 0.0;
    final gap = (hasLogo && showExif) ? config.textPadding / 2.0 : 0.0;
    final infoContentH = logoH + gap + estTextH + 2 * config.textPadding;
    final infoH = infoContentH;

    // 叠加模式下信息层宽度限制为原图的 75%
    final infoW = isOverlay
        ? (imageDisplayW * 0.75).clamp(120.0, imageDisplayW)
        : imageDisplayW;

    // ── 画布尺寸 ──
    // 叠加模式：画布不需要 info 层额外空间
    final contentW = imageDisplayW + 2 * borderW;
    final contentH = isOverlay
        ? imageDisplayH + 2 * borderW
        : imageDisplayH + 2 * borderW + infoH;

    final targetRatio = config.canvasAspectRatio.value;
    double canvasW = contentW;
    double canvasH = contentH;
    if (targetRatio != null) {
      final currentRatio = canvasW / canvasH;
      if (currentRatio < targetRatio) {
        canvasW = canvasH * targetRatio;
      } else {
        canvasH = canvasW / targetRatio;
      }
    }
    final offsetX = (canvasW - contentW) / 2.0;
    final offsetY = (canvasH - contentH) / 2.0;

    // ── 各层坐标 ──
    final imageX = offsetX + borderW;
    final imageY = offsetY + borderW;

    // 信息层坐标
    final double infoX, infoY;
    final overlayPad = config.textPadding;

    switch (placement) {
      case InfoPlacement.above:
        infoX = offsetX + borderW;
        infoY = offsetY;
        break;
      case InfoPlacement.below:
        infoX = offsetX + borderW;
        infoY = offsetY + imageDisplayH + 2 * borderW;
        break;
      case InfoPlacement.overlayTopLeft:
        infoX = imageX + overlayPad;
        infoY = imageY + overlayPad;
        break;
      case InfoPlacement.overlayTopRight:
        infoX = imageX + imageDisplayW - infoW - overlayPad;
        infoY = imageY + overlayPad;
        break;
      case InfoPlacement.overlayBottomLeft:
        infoX = imageX + overlayPad;
        infoY = imageY + imageDisplayH - infoH - overlayPad;
        break;
      case InfoPlacement.overlayBottomRight:
        infoX = imageX + imageDisplayW - infoW - overlayPad;
        infoY = imageY + imageDisplayH - infoH - overlayPad;
    }

    return WatermarkGeometry(
      canvasSize: Size(canvasW, canvasH),
      imageRect: Rect.fromLTWH(imageX, imageY, imageDisplayW, imageDisplayH),
      infoRect: Rect.fromLTWH(infoX, infoY, infoW, infoH),
      borderWidth: borderW,
      cornerRadius: config.cornerRadius,
      shadowBlur: config.shadowIntensity * 30.0,
      shadowOffsetY: config.shadowIntensity * 8.0,
      fontSize: config.fontSize,
      logoMaxH: logoH,
      textPad: config.textPadding,
      hasLogo: hasLogo,
      hasExif: showExif,
      infoBehindImage: placement.behindImage,
      imageScale: imageScale,
    );
  }

  // ────────────────────────────────────────────────────────────
  // 导出缩放
  // ────────────────────────────────────────────────────────────

  /// 水平居中边距（参考画布）。
  ///
  /// 由于 canvas 紧贴内容，左右边距相等且正好等于 [borderWidth]。
  double get horizontalMargin => borderWidth;

  /// 计算从参考画布到导出画布的缩放因子。
  ///
  /// [fullResImageWidth] 是全分辨率渲染原图的宽度（像素）。
  /// 导出时所有参考尺寸都应乘以该因子。
  double exportScale(int fullResImageWidth) {
    return (fullResImageWidth * imageScale) / imageRect.width;
  }

  /// 导出画布尺寸（像素）。
  Size exportCanvasSize(int fullResImageWidth) {
    final s = exportScale(fullResImageWidth);
    return Size(canvasSize.width * s, canvasSize.height * s);
  }

  // ────────────────────────────────────────────────────────────
  // Debug
  // ────────────────────────────────────────────────────────────

  @override
  String toString() {
    final w = canvasSize.width.toStringAsFixed(1);
    final h = canvasSize.height.toStringAsFixed(1);
    final iw = imageRect.width.toStringAsFixed(1);
    final ih = imageRect.height.toStringAsFixed(1);
    final bw = borderWidth.toStringAsFixed(1);
    final hm = horizontalMargin.toStringAsFixed(1);
    final ix = imageRect.left.toStringAsFixed(1);
    final iy = imageRect.top.toStringAsFixed(1);
    final nfx = infoRect.left.toStringAsFixed(1);
    final nfw = infoRect.width.toStringAsFixed(1);
    return 'WatermarkGeometry(canvas:${w}x$h image:${iw}x$ih@($ix,$iy) '
        'border:$bw hMargin:$hm info:${nfw}x${infoRect.height.toStringAsFixed(1)}@($nfx,${infoRect.top.toStringAsFixed(1)}) '
        'scale:$imageScale)';
  }
}

// ──────────────────────────────────────────────────────────────
// 辅助判断（不依赖 WatermarkExporter，纯数据函数）
// ──────────────────────────────────────────────────────────────

/// 判断配置中是否包含 Logo。
bool watermarkHasLogo(WatermarkConfig c) {
  if (c.logoSource == LogoSource.custom && c.customLogoPath != null) {
    return true;
  }
  if (c.logoSource == LogoSource.builtin && c.logoBrand != null) return true;
  return false;
}

/// 判断是否应显示 EXIF（自动模式下需有有效元数据）。
bool watermarkShowExif(WatermarkConfig c, {String? exifText}) {
  if (!c.showExif) return false;
  if (c.exifMode == ExifMode.custom) {
    return (c.customExifText?.trim().isNotEmpty ?? false);
  }
  return exifText != null && exifText.isNotEmpty;
}

/// 解析 EXIF 显示字符串
///
/// 自定义模式下返回用户输入文本，自动模式下从 [metadata] 提取
String? resolveWatermarkExif(WatermarkConfig config, RawMetadata? metadata) {
  if (config.exifMode == ExifMode.custom) {
    final t = config.customExifText?.trim();
    return (t != null && t.isNotEmpty) ? t : null;
  }
  if (metadata == null) return null;
  final s = metadata.watermarkExif(enabledFields: config.enabledExifFields);
  return s.isEmpty ? null : s;
}

/// 将 0–4 索引映射为 [FontWeight]
FontWeight fontWeightFromIndex(int index) {
  const map = [
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
  ];
  return map[index.clamp(0, map.length - 1)];
}

/// Logo asset 路径
String logoAssetPath(String brand, WatermarkColorMode mode) {
  final dir = mode == WatermarkColorMode.light ? 'light' : 'dark';
  return 'assets/borders/logos/$dir/$brand.webp';
}

/// 背景模糊降采样参数
///
/// 两阶段策略：降采样到缩略图 → 在缩略图上模糊 → 拉伸填充画布
/// 返回 (缩略图宽, 缩略图高, 降采样比, 补偿后的模糊 sigma)
({int thumbW, int thumbH, double downscale, double compensatedSigma})
computeBlurParams({
  required double srcWidth,
  required double srcHeight,
  required double blurSigma,
  required double refCanvasWidth,
  required double refCanvasHeight,
  double maxThumbEdge = 256.0,
}) {
  final srcLong = math.max(srcWidth, srcHeight);
  final downscale = srcLong > maxThumbEdge ? maxThumbEdge / srcLong : 1.0;
  final thumbW = (srcWidth * downscale).round();
  final thumbH = (srcHeight * downscale).round();
  final fillScale = math.max(refCanvasWidth / thumbW, refCanvasHeight / thumbH);
  final compensatedSigma = blurSigma * downscale * fillScale;
  return (
    thumbW: thumbW,
    thumbH: thumbH,
    downscale: downscale,
    compensatedSigma: compensatedSigma,
  );
}
