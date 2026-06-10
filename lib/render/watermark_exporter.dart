import 'dart:developer' as dev;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/watermark_config.dart';
import '../native/raw_bridge.dart';
import '../services/watermark/watermark_asset_manager.dart';
import 'watermark_geometry.dart';

/// 纯离屏 Canvas 水印边框合成器。
///
/// 使用 [WatermarkGeometry] 统一布局 + 动态 scale 因子：
///   scale = fullResW × imageScale / geometry.imageRect.width
///
/// 所有尺寸 = geometry 参考值 × scale，保证与预览比例 100% 一致。
/// 文本使用 [ParagraphBuilder] 在导出分辨率上重绘，Logo 从源文件重新解码。
class WatermarkExporter {
  WatermarkExporter._();

  /// 合成水印边框，返回 [ui.Image]。
  ///
  /// [fullResImage] 是全分辨率调色结果（已裁剪、已调色）。
  static Future<ui.Image> composite({
    required ui.Image fullResImage,
    required WatermarkConfig config,
    required RawMetadata? metadata,
  }) async {
    // ── 1. 几何布局（参考画布） ──
    final aspectRatio = fullResImage.width / fullResImage.height;
    final hasLogo = watermarkHasLogo(config);
    final exifStr = _resolveExif(config, metadata);
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
    final scaledHMargin = geometry.horizontalMargin * scale;
    final scaledImageW = geometry.imageRect.width * scale;
    final scaledImageH = geometry.imageRect.height * scale;
    final scaledImageL = geometry.imageRect.left * scale;
    final scaledImageT = geometry.imageRect.top * scale;
    final scaledImageDst = ui.Rect.fromLTWH(
      scaledImageL,
      scaledImageT,
      scaledImageW,
      scaledImageH,
    );
    final scaledInfoW = geometry.infoRect.width * scale;
    final scaledTextConstraintW = scaledInfoW - 2 * geometry.textPad * scale;

    dev.log(
      '══╣ WatermarkExport Geometry Dump ╠══\n'
      '  inputImageSize        = ${fullResImage.width}×${fullResImage.height}\n'
      '  calculatedScale       = ${scale.toStringAsFixed(4)}\n'
      '  FinalCanvasSize       = $cw×$ch\n'
      '  FinalHorizontalMargin = ${scaledHMargin.toStringAsFixed(1)}\n'
      '  finalDrawRect (image) = $scaledImageDst\n'
      '  imageCenterX          = ${(scaledImageL + scaledImageW / 2).toStringAsFixed(1)}\n'
      '  canvasCenterX         = ${(cw / 2).toStringAsFixed(1)}\n'
      '  textConstraintsWidth  = ${scaledTextConstraintW.toStringAsFixed(1)}\n'
      '  infoRect              = (${(geometry.infoRect.left * scale).toStringAsFixed(1)}, ${(geometry.infoRect.top * scale).toStringAsFixed(1)}, ${scaledInfoW.toStringAsFixed(1)}, ${(geometry.infoRect.height * scale).toStringAsFixed(1)})\n'
      '  ── reference geometry ──\n'
      '  $geometry',
      name: 'WatermarkExporter',
    );

    // ── 3. 加载 Logo（源文件重新解码） ──
    ui.Image? logoImg;
    ui.Image? bgBlur;
    ui.Image? customBg;
    if (hasLogo) {
      logoImg = await _loadLogoImage(config);
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
        customBg = await _loadBytesAsImage(
          await WatermarkAssetManager.readImageBytes(config.customBackgroundPath!),
        );
      }

      // ── 6. Canvas 绘制 ──
      final rec = ui.PictureRecorder();
      final cvs = ui.Canvas(
        rec,
        ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
      );

      _drawBackground(cvs, config, bgBlur, customBg, cw, ch);

      // 导出坐标系下的各区域
      final imgL = geometry.imageRect.left * scale;
      final imgT = geometry.imageRect.top * scale;
      final imgW = geometry.imageRect.width * scale;
      final imgH = geometry.imageRect.height * scale;
      final cornerR = geometry.cornerRadius * scale;
      final shadowBlur = geometry.shadowBlur * scale;
      final shadowOffY = geometry.shadowOffsetY * scale;
      final infoL = geometry.infoRect.left * scale;
      final infoT = geometry.infoRect.top * scale;
      final infoW = geometry.infoRect.width * scale;
      final infoH = geometry.infoRect.height * scale;
      final textPad = geometry.textPad * scale;
      final logoH = geometry.logoMaxH * scale;

      // ── 阴影 ──
      if (config.shadowIntensity > 0.001) {
        final shadowAlpha = (config.shadowIntensity * 0.6 * 255).round().clamp(0, 255);
        final sp = ui.Paint()
          ..color = ui.Color.fromARGB(shadowAlpha, 0, 0, 0)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, shadowBlur);
        cvs.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(imgL, imgT + shadowOffY, imgW, imgH),
            ui.Radius.circular(cornerR),
          ),
          sp,
        );
      }

      // ── 原图（圆角裁剪） ──
      cvs.save();
      cvs.clipRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(imgL, imgT, imgW, imgH),
          ui.Radius.circular(cornerR),
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
        ui.Rect.fromLTWH(imgL, imgT, imgW, imgH),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      cvs.restore();

      // ── Logo + EXIF（infoRect 内垂直居中） ──
      if (hasLogo || showExif) {
        double contentH = 0;
        if (logoImg != null) contentH += logoH;
        if (logoImg != null && exifPara != null) contentH += textPad / 2.0;
        if (exifPara != null) {
          exifPara.layout(ui.ParagraphConstraints(width: infoW - 2 * textPad));
          contentH += exifPara.height;
        }
        final contentStartY = infoT + (infoH - contentH) / 2.0;

        double y = contentStartY;
        if (logoImg != null) {
          final logoAr = logoImg.width / logoImg.height;
          final logoW = logoH * logoAr;
          final logoX = infoL + (infoW - logoW) / 2.0;
          cvs.drawImageRect(
            logoImg,
            ui.Rect.fromLTWH(0, 0, logoImg.width.toDouble(), logoImg.height.toDouble()),
            ui.Rect.fromLTWH(logoX, y, logoW, logoH),
            ui.Paint()
              ..color = ui.Color.fromARGB(
                (config.logoOpacity * 255).round().clamp(0, 255),
                255,
                255,
                255,
              ),
          );
          y += logoH;
          if (exifPara != null) y += textPad / 2.0;
        }

        if (exifPara != null) {
          exifPara.layout(ui.ParagraphConstraints(width: infoW - 2 * textPad));
          cvs.drawParagraph(exifPara, ui.Offset(infoL + textPad, y));
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
          ui.Paint()..color = ui.Color(config.backgroundColor),
        );
      case BackgroundType.blurredOriginal:
        if (bgBlur != null) {
          cvs.drawImageRect(
            bgBlur,
            ui.Rect.fromLTWH(0, 0, bgBlur.width.toDouble(), bgBlur.height.toDouble()),
            ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
            ui.Paint()..filterQuality = ui.FilterQuality.low,
          );
        } else {
          cvs.drawRect(
            ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
            ui.Paint()..color = const ui.Color(0xFF1A1A1A),
          );
        }
      case BackgroundType.image:
        if (customBg != null) {
          cvs.drawImageRect(
            customBg,
            ui.Rect.fromLTWH(0, 0, customBg.width.toDouble(), customBg.height.toDouble()),
            ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
            ui.Paint()..filterQuality = ui.FilterQuality.low,
          );
        } else {
          cvs.drawRect(
            ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
            ui.Paint()..color = const ui.Color(0xFF1A1A1A),
          );
        }
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
    final fw = _toFontWeight(config.fontWeightIndex);
    final ts = TextStyle(
      fontSize: geometry.fontSize * scale,
      fontWeight: fw,
      color: tc.withValues(alpha: config.textOpacity),
      fontFamily: config.fontFamily,
    );
    final pb = ui.ParagraphBuilder(
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

  /// 降采样 → 模糊 → 拉伸到导出尺寸。
  /// [exportScale] 用于补偿模糊量。
  static Future<ui.Image?> _makeBlurBg(
    ui.Image src,
    double sigma,
    double exportScale,
    int tw,
    int th,
  ) async {
    final sw = src.width.toDouble();
    final sh = src.height.toDouble();
    final srcLong = math.max(sw, sh);
    final down = srcLong > 256 ? 256 / srcLong : 1.0;
    final dw = (sw * down).round();
    final dh = (sh * down).round();

    final r1 = ui.PictureRecorder();
    ui.Canvas(r1).drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, sw, sh),
      ui.Rect.fromLTWH(0, 0, dw.toDouble(), dh.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final p1 = r1.endRecording();
    final small = await p1.toImage(dw, dh);
    p1.dispose();

    final compensatedBlur = sigma * down * exportScale;

    final r2 = ui.PictureRecorder();
    final c2 = ui.Canvas(r2);
    c2.saveLayer(
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: compensatedBlur.clamp(0.0, 50.0),
          sigmaY: compensatedBlur.clamp(0.0, 50.0),
          tileMode: ui.TileMode.clamp,
        ),
    );
    c2.drawImageRect(
      small,
      ui.Rect.fromLTWH(0, 0, dw.toDouble(), dh.toDouble()),
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      ui.Paint(),
    );
    c2.restore();
    final p2 = r2.endRecording();
    final result = await p2.toImage(tw, th);
    p2.dispose();
    small.dispose();
    return result;
  }

  // ────────────────────────────────────────────────────────────
  // 工具
  // ────────────────────────────────────────────────────────────

  static Future<ui.Image?> _loadBytesAsImage(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image?> _loadLogoImage(WatermarkConfig config) async {
    if (config.logoSource == LogoSource.custom && config.customLogoPath != null) {
      final bytes = await WatermarkAssetManager.readImageBytes(config.customLogoPath!);
      return _loadBytesAsImage(bytes);
    }
    if (config.logoBrand != null) {
      final assetPath = _logoAssetPath(config.logoBrand!, config.colorMode);
      try {
        final data = await rootBundle.load(assetPath);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        return (await codec.getNextFrame()).image;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String _logoAssetPath(String brand, WatermarkColorMode m) =>
      'assets/borders/logos/${m == WatermarkColorMode.light ? 'light' : 'dark'}/$brand.webp';

  static String? _resolveExif(WatermarkConfig config, RawMetadata? meta) {
    if (config.exifMode == ExifMode.custom) {
      final t = config.customExifText?.trim();
      return (t != null && t.isNotEmpty) ? t : null;
    }
    return _exifString(meta);
  }

  static String? _exifString(RawMetadata? m) {
    if (m == null) return null;
    final p = <String>[];
    final cam = m.cameraModel.trim();
    if (cam.isNotEmpty) p.add(cam);
    if (m.iso > 0) p.add('ISO ${m.iso}');
    if (m.aperture > 0) p.add('f/${m.aperture.toStringAsFixed(1)}');
    if (m.shutter > 0) p.add(m.shutterDisplay);
    if (m.focalLength > 0) p.add('${m.focalLength.toStringAsFixed(0)}mm');
    final lens = m.lensModel.trim();
    if (lens.isNotEmpty && lens != cam) p.add(lens);
    return p.isEmpty ? null : p.join(' | ');
  }

  static FontWeight _toFontWeight(int i) => const [
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
  ][i.clamp(0, 4)];

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
