import 'dart:developer' as dev;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

import '../core/models/watermark_config.dart';
import '../native/raw_bridge.dart';
import '../services/watermark/watermark_logo_loader.dart';
import '../utils/image_loader_util.dart';
import 'watermark_geometry.dart';

/// 纯离屏 Canvas 水印边框合成器
///
/// 使用 [WatermarkGeometry] 统一布局 + 动态 scale 因子：
///   scale = fullResW × imageScale / geometry.imageRect.width
///
/// 所有尺寸 = geometry 参考值 × scale，保证与预览比例 100% 一致
/// 文本使用 [ParagraphBuilder] 在导出分辨率上重绘，Logo 从源文件重新解码
class WatermarkExporter {
  WatermarkExporter._();

  /// 合成水印边框，返回 [ui.Image]
  ///
  /// [fullResImage] 是全分辨率调色结果（已裁剪、已调色）
  static Future<ui.Image> composite({
    required ui.Image fullResImage,
    required WatermarkConfig config,
    required RawMetadata? metadata,
  }) async {
    // ── 1. 几何布局（参考画布） ──
    final aspectRatio = fullResImage.width / fullResImage.height;
    final hasLogo = watermarkHasLogo(config);
    final exifStr = resolveWatermarkExif(config, metadata);
    final showExif = exifStr != null;
    final geometry = WatermarkGeometry.compute(
      imageAspectRatio: aspectRatio,
      config: config,
      hasLogo: hasLogo,
      showExif: showExif,
    );

    // ── 2. 导出缩放因子 ──
    final scale = geometry.exportScale(fullResImage.width);
    final exportSize = geometry.exportCanvasSize(fullResImage.width);
    final cw = exportSize.width.ceil();
    final ch = exportSize.height.ceil();

    // 一次性预计算所有缩放后的坐标值
    final scaledImageL = geometry.imageRect.left * scale;
    final scaledImageT = geometry.imageRect.top * scale;
    final scaledImageW = geometry.imageRect.width * scale;
    final scaledImageH = geometry.imageRect.height * scale;
    final scaledImageDst = ui.Rect.fromLTWH(
      scaledImageL,
      scaledImageT,
      scaledImageW,
      scaledImageH,
    );
    final scaledInfoL = geometry.infoRect.left * scale;
    final scaledInfoT = geometry.infoRect.top * scale;
    final scaledInfoW = geometry.infoRect.width * scale;
    final scaledInfoH = geometry.infoRect.height * scale;
    final scaledTextConstraintW = scaledInfoW - 2 * geometry.textPad * scale;
    final scaledCornerR = geometry.cornerRadius * scale;
    final scaledShadowBlur = geometry.shadowBlur * scale;
    final scaledShadowOffY = geometry.shadowOffsetY * scale;
    final scaledTextPad = geometry.textPad * scale;
    final scaledLogoH = geometry.logoMaxH * scale;

    dev.log(
      '══╣ WatermarkExport Geometry Dump ╠══\n'
      '  inputImageSize        = ${fullResImage.width}×${fullResImage.height}\n'
      '  calculatedScale       = ${scale.toStringAsFixed(4)}\n'
      '  FinalCanvasSize       = $cw×$ch\n'
      '  FinalHorizontalMargin = ${geometry.horizontalMargin * scale}\n'
      '  finalDrawRect (image) = $scaledImageDst\n'
      '  imageCenterX          = ${(scaledImageL + scaledImageW / 2).toStringAsFixed(1)}\n'
      '  canvasCenterX         = ${(cw / 2).toStringAsFixed(1)}\n'
      '  textConstraintsWidth  = ${scaledTextConstraintW.toStringAsFixed(1)}\n'
      '  infoRect              = ($scaledInfoL, $scaledInfoT, $scaledInfoW, $scaledInfoH)\n'
      '  ── reference geometry ──\n'
      '  $geometry',
      name: 'WatermarkExporter',
    );

    // ── 3. 加载 Logo（源文件重新解码） ──
    ui.Image? logoImg;
    ui.Image? bgBlur;
    ui.Image? customBg;
    if (hasLogo) {
      logoImg = await WatermarkLogoLoader.load(config);
    }

    try {
      // ── 4. EXIF 段落（导出分辨率下的 TextPainter） ──
      ui.Paragraph? exifPara;
      if (showExif) {
        exifPara = _buildExifParagraph(exifStr, config, scale, geometry);
      }

      // ── 5. 背景图 ──
      if (config.backgroundType == BackgroundType.blurredOriginal) {
        bgBlur = await _makeBlurBg(
          fullResImage,
          config.blurRadius,
          scale,
          cw,
          ch,
        );
      } else if (config.backgroundType == BackgroundType.image &&
          config.customBackgroundPath != null) {
        customBg = await loadWatermarkFileImage(config.customBackgroundPath!);
      }

      // ── 6. Canvas 绘制 ──
      final rec = ui.PictureRecorder();
      final cvs = ui.Canvas(
        rec,
        ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
      );

      _drawBackground(cvs, config, bgBlur, customBg, cw, ch);

      // ── 阴影 ──
      if (config.shadowIntensity > 0.001) {
        final shadowAlpha = (config.shadowIntensity * 0.6 * 255).round().clamp(
          0,
          255,
        );
        final sp = ui.Paint()
          ..color = ui.Color.fromARGB(shadowAlpha, 0, 0, 0)
          ..maskFilter = ui.MaskFilter.blur(
            ui.BlurStyle.normal,
            scaledShadowBlur,
          );
        cvs.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(
              scaledImageL,
              scaledImageT + scaledShadowOffY,
              scaledImageW,
              scaledImageH,
            ),
            ui.Radius.circular(scaledCornerR),
          ),
          sp,
        );
      }

      // ── 原图（圆角裁剪） ──
      cvs.save();
      cvs.clipRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(
            scaledImageL,
            scaledImageT,
            scaledImageW,
            scaledImageH,
          ),
          ui.Radius.circular(scaledCornerR),
        ),
      );
      cvs.drawImageRect(
        fullResImage,
        ui.Rect.fromLTWH(
          0,
          0,
          fullResImage.width.toDouble(),
          fullResImage.height.toDouble(),
        ),
        ui.Rect.fromLTWH(
          scaledImageL,
          scaledImageT,
          scaledImageW,
          scaledImageH,
        ),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      cvs.restore();

      // ── Logo + EXIF（infoRect 内垂直居中） ──
      if (hasLogo || showExif) {
        double contentH = 0;
        if (logoImg != null) contentH += scaledLogoH;
        if (logoImg != null && exifPara != null) {
          contentH += scaledTextPad / 2.0;
        }
        if (exifPara != null) {
          exifPara.layout(
            ui.ParagraphConstraints(width: scaledInfoW - 2 * scaledTextPad),
          );
          contentH += exifPara.height;
        }
        final contentStartY = scaledInfoT + (scaledInfoH - contentH) / 2.0;

        double y = contentStartY;
        if (logoImg != null) {
          final logoAr = logoImg.width / logoImg.height;
          final logoW = scaledLogoH * logoAr;
          final logoX = scaledInfoL + (scaledInfoW - logoW) / 2.0;
          cvs.drawImageRect(
            logoImg,
            ui.Rect.fromLTWH(
              0,
              0,
              logoImg.width.toDouble(),
              logoImg.height.toDouble(),
            ),
            ui.Rect.fromLTWH(logoX, y, logoW, scaledLogoH),
            ui.Paint()
              ..color = ui.Color.fromARGB(
                (config.logoOpacity * 255).round().clamp(0, 255),
                255,
                255,
                255,
              ),
          );
          y += scaledLogoH;
          if (exifPara != null) y += scaledTextPad / 2.0;
        }

        if (exifPara != null) {
          exifPara.layout(
            ui.ParagraphConstraints(width: scaledInfoW - 2 * scaledTextPad),
          );
          cvs.drawParagraph(
            exifPara,
            ui.Offset(scaledInfoL + scaledTextPad, y),
          );
        }
      }

      final pic = rec.endRecording();
      final result = await pic.toImage(cw, ch);
      pic.dispose();

      return result;
    } finally {
      bgBlur?.dispose();
      customBg?.dispose();
      logoImg?.dispose();
    }
  }

  // ────────────────────────────────────────────────────────────
  // 背景
  // ────────────────────────────────────────────────────────────

  static void _drawBackground(
    ui.Canvas cvs,
    WatermarkConfig config,
    ui.Image? bgBlur,
    ui.Image? customBg,
    int cw,
    int ch,
  ) {
    switch (config.backgroundType) {
      case BackgroundType.solidColor:
        cvs.drawRect(
          ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
          ui.Paint()..color = config.backgroundColor,
        );
      case BackgroundType.blurredOriginal:
        _drawImageBgOrFallback(cvs, bgBlur, cw, ch);
      case BackgroundType.image:
        _drawImageBgOrFallback(cvs, customBg, cw, ch);
    }
  }

  /// 绘制图片背景；若图片为 null 则回退到纯色填充
  static void _drawImageBgOrFallback(
    ui.Canvas cvs,
    ui.Image? image,
    int cw,
    int ch,
  ) {
    if (image != null) {
      cvs.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
    } else {
      cvs.drawRect(
        ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
        ui.Paint()..color = AppColors.fallbackBg,
      );
    }
  }

  // ────────────────────────────────────────────────────────────
  // EXIF 段落（使用 ParagraphBuilder，矢量文本）
  // ────────────────────────────────────────────────────────────

  static ui.Paragraph _buildExifParagraph(
    String text,
    WatermarkConfig config,
    double scale,
    WatermarkGeometry geometry,
  ) {
    final tc = config.colorMode == WatermarkColorMode.light
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    final fw = fontWeightFromIndex(config.fontWeightIndex);
    final ts = TextStyle(
      fontSize: geometry.fontSize * scale,
      fontWeight: fw,
      color: tc.withValues(alpha: config.textOpacity),
      fontFamily: config.fontFamily,
    );
    final pb =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              maxLines: 3,
              ellipsis: '…',
              textDirection: ui.TextDirection.ltr,
            ),
          )
          ..pushStyle(_toUiStyle(ts))
          ..addText(text);
    return pb.build();
  }

  // ────────────────────────────────────────────────────────────
  // 模糊背景
  // ────────────────────────────────────────────────────────────

  /// 降采样+模糊 → 拉伸到导出尺寸（两 pass，从原来的三 pass 优化）
  ///
  /// 与预览 [_BlurredBackgroundLayer] 使用完全相同的两阶段策略：
  ///   Pass 1: 在缩略图上降采样同时施加模糊（合并为一个 saveLayer，省去中间纹理）
  ///   Pass 2: 将模糊后的缩略图拉伸到导出画布
  /// 保证导出模糊的丝滑程度与预览一致
  static Future<ui.Image?> _makeBlurBg(
    ui.Image src,
    double sigma,
    double exportScale,
    int tw,
    int th,
  ) async {
    final b = computeBlurParams(
      srcWidth: src.width.toDouble(),
      srcHeight: src.height.toDouble(),
      blurSigma: sigma,
      refCanvasWidth: tw / exportScale,
      refCanvasHeight: th / exportScale,
    );

    // 第 1 趟：降采样到缩略图 + 模糊（合并：saveLayer 内缩放绘制并施加模糊）
    final r1 = ui.PictureRecorder();
    final c1 = ui.Canvas(r1);
    c1.saveLayer(
      ui.Rect.fromLTWH(0, 0, b.thumbW.toDouble(), b.thumbH.toDouble()),
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: b.compensatedSigma.clamp(0.0, 50.0),
          sigmaY: b.compensatedSigma.clamp(0.0, 50.0),
          tileMode: ui.TileMode.clamp,
        ),
    );
    c1.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, b.thumbW.toDouble(), b.thumbH.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    c1.restore();
    final p1 = r1.endRecording();
    final blurredThumb = await p1.toImage(b.thumbW, b.thumbH);
    p1.dispose();

    // 第 2 趟：拉伸模糊缩略图到导出画布
    final r2 = ui.PictureRecorder();
    ui.Canvas(r2).drawImageRect(
      blurredThumb,
      ui.Rect.fromLTWH(0, 0, b.thumbW.toDouble(), b.thumbH.toDouble()),
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final p2 = r2.endRecording();
    final result = await p2.toImage(tw, th);
    p2.dispose();
    blurredThumb.dispose();
    return result;
  }

  // ────────────────────────────────────────────────────────────
  // 工具
  // ────────────────────────────────────────────────────────────

  static ui.TextStyle _toUiStyle(TextStyle ts) => ui.TextStyle(
    color: ts.color != null
        ? ui.Color.fromARGB(
            (ts.color!.a * 255).round(),
            (ts.color!.r * 255).round(),
            (ts.color!.g * 255).round(),
            (ts.color!.b * 255).round(),
          )
        : null,
    fontSize: ts.fontSize,
    fontWeight: ts.fontWeight,
    fontFamily: ts.fontFamily,
  );
}
