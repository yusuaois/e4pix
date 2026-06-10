import 'package:flutter/material.dart';

import '../core/models/watermark_config.dart';

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

  /// 信息层是否在原图上方
  final bool infoAbove;

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
    required this.infoAbove,
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
    final infoAbove = config.infoPlacement == InfoPlacement.above;

    // ── 原图显示区域 ──
    // 可用宽度 = 画布宽度 - 两侧边框
    final availW = (kBaseWidth - 2 * borderW).clamp(1.0, kBaseWidth);
    // 原图按比例适配可用宽度
    final imageDisplayW = availW * imageScale;
    final imageDisplayH = imageDisplayW / imageAspectRatio;

    // ── 信息层高度 ──
    final logoH = hasLogo ? config.logoSize * 48.0 : 0.0;
    final estTextH = showExif ? config.fontSize * 2.0 : 0.0;
    final gap = (hasLogo && showExif) ? config.textPadding / 2.0 : 0.0;
    final infoContentH = logoH + gap + estTextH + 2 * config.textPadding;
    final infoH = infoContentH; // 不裁剪，导出需要完整高度；预览由 FittedBox 保证可见

    // ── 画布尺寸（紧贴内容） ──
    final contentW = imageDisplayW + 2 * borderW;
    final contentH = imageDisplayH + 2 * borderW + infoH;

    // 固定画布比例：扩展画布并居中内容
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

    // ── 各层坐标（加入扩展偏移，自动模式下 offset=0） ──
    final imageX = offsetX + borderW;
    final imageY = offsetY + (infoAbove ? infoH + borderW : borderW);

    final infoX = offsetX + borderW;
    final infoY = offsetY + (infoAbove ? 0.0 : imageDisplayH + 2 * borderW);

    return WatermarkGeometry(
      canvasSize: Size(canvasW, canvasH),
      imageRect: Rect.fromLTWH(imageX, imageY, imageDisplayW, imageDisplayH),
      infoRect: Rect.fromLTWH(infoX, infoY, imageDisplayW, infoH),
      borderWidth: borderW,
      cornerRadius: config.cornerRadius,
      shadowBlur: config.shadowIntensity * 30.0,
      shadowOffsetY: config.shadowIntensity * 8.0,
      fontSize: config.fontSize,
      logoMaxH: logoH,
      textPad: config.textPadding,
      hasLogo: hasLogo,
      hasExif: showExif,
      infoAbove: infoAbove,
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
