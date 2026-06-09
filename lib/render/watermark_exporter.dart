import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/watermark_config.dart';
import '../native/raw_bridge.dart';
import '../services/watermark/watermark_asset_manager.dart';

/// 离屏 Canvas 水印边框合成器
///
/// 关键设计：
/// - UI 上所有尺寸参数都是基于 `kRefPreviewSize` 的**逻辑像素**
/// - 导出时按全分辨率原图等比放大
/// - 使用 PictureRecorder + Canvas 分步绘制，避免移动端 OOM
/// - 内置 Logo 从 assets/ 加载；自定义图片从文件系统加载
class WatermarkExporter {
  WatermarkExporter._();

  /// 预览参考尺寸（逻辑像素）
  static const double kRefPreviewSize = 1000.0;

  /// 合成水印边框，返回 [ui.Image]。
  static Future<ui.Image> composite({
    required ui.Image renderedImage,
    required WatermarkConfig config,
    required RawMetadata? metadata,
  }) async {
    final rw = renderedImage.width.toDouble();
    final rh = renderedImage.height.toDouble();
    final longest = math.max(rw, rh);
    final scale = longest / kRefPreviewSize;

    final borderW = (config.borderWidth * scale).round();
    final cornerR = config.cornerRadius * scale;
    final imageScale = config.imageScale.clamp(0.01, 1.0);
    final textPad = (config.textPadding * scale).round();
    final fontSize = config.fontSize * scale;
    final shadowAlpha = (config.shadowIntensity * 0.6 * 255).round().clamp(
      0,
      255,
    );
    final shadowBlur = config.shadowIntensity * 30.0 * scale;
    final shadowOffsetY = config.shadowIntensity * 8.0 * scale;

    final finalImgW = (rw * imageScale).round();
    final finalImgH = (rh * imageScale).round();

    // ═══════════════════════════════════════════════════════
    // EXIF 文本
    // ═══════════════════════════════════════════════════════
    final exifStr = config.showExif ? _resolveExif(config, metadata) : null;

    // ═══════════════════════════════════════════════════════
    // Logo 加载
    // ═══════════════════════════════════════════════════════
    final hasLogo = _hasLogo(config);
    final hasInfo = exifStr != null || hasLogo;

    int infoH = 0;
    ui.Paragraph? exifPara;
    ui.Image? logoImg;

    if (hasInfo) {
      double logoH = 0;
      if (hasLogo) {
        logoImg = await _loadLogoImage(config);
        if (logoImg != null) {
          logoH = config.logoSize * 48.0 * scale;
        }
      }

      if (exifStr != null) {
        final tc = config.colorMode == WatermarkColorMode.light
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000);
        final fw = _toFontWeight(config.fontWeightIndex);
        final ts = TextStyle(
          fontSize: fontSize,
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
              ..addText(exifStr);
        exifPara = pb.build()
          ..layout(
            ui.ParagraphConstraints(width: finalImgW.toDouble() - 2 * textPad),
          );
      }

      final textH = exifPara?.height ?? 0.0;
      final gap = (hasLogo && exifStr != null) ? (textPad / 2.0) : 0.0;
      infoH = (logoH + gap + textH + 2 * textPad).ceil();
    }

    // ═══════════════════════════════════════════════════════
    // 画布尺寸
    // ═══════════════════════════════════════════════════════
    final cw = finalImgW + 2 * borderW;
    final ch = finalImgH + 2 * borderW + infoH;

    // ═══════════════════════════════════════════════════════
    // 背景图加载
    // ═══════════════════════════════════════════════════════
    ui.Image? bgBlur;
    ui.Image? customBg;

    if (config.backgroundType == BackgroundType.blurredOriginal) {
      bgBlur = await _makeBlurBg(
        renderedImage,
        config.blurRadius * scale,
        cw,
        ch,
      );
    } else if (config.backgroundType == BackgroundType.image &&
        config.customBackgroundPath != null) {
      customBg = await _loadBytesAsImage(
        await WatermarkAssetManager.readImageBytes(
          config.customBackgroundPath!,
        ),
      );
    }

    // ═══════════════════════════════════════════════════════
    // Canvas 绘制
    // ═══════════════════════════════════════════════════════
    final rec = ui.PictureRecorder();
    final cvs = ui.Canvas(
      rec,
      ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
    );

    // ── Layer 0: 背景 ──
    switch (config.backgroundType) {
      case BackgroundType.solidColor:
        cvs.drawRect(
          ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
          ui.Paint()..color = ui.Color(config.backgroundColor),
        );
      case BackgroundType.blurredOriginal:
        if (bgBlur != null) {
          _drawFill(cvs, bgBlur, cw, ch);
        } else {
          _drawFallbackBg(cvs, cw, ch);
        }
      case BackgroundType.image:
        if (customBg != null) {
          _drawFill(cvs, customBg, cw, ch);
        } else {
          _drawFallbackBg(cvs, cw, ch);
        }
    }

    // ── 原图位置 ──
    final infoAbove = config.infoPlacement == InfoPlacement.above;
    final imgL = borderW.toDouble();
    final imgT = infoAbove ? (infoH + borderW).toDouble() : borderW.toDouble();

    // ── Layer 2 阴影 ──
    if (config.shadowIntensity > 0.001) {
      final sp = ui.Paint()
        ..color = ui.Color.fromARGB(shadowAlpha, 0, 0, 0)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, shadowBlur);
      cvs.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(
            imgL,
            imgT + shadowOffsetY,
            finalImgW.toDouble(),
            finalImgH.toDouble(),
          ),
          ui.Radius.circular(cornerR),
        ),
        sp,
      );
    }

    // ── Layer 2: 原图（圆角裁剪） ──
    cvs.save();
    cvs.clipRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(
          imgL,
          imgT,
          finalImgW.toDouble(),
          finalImgH.toDouble(),
        ),
        ui.Radius.circular(cornerR),
      ),
    );
    cvs.drawImageRect(
      renderedImage,
      ui.Rect.fromLTWH(0, 0, rw, rh),
      ui.Rect.fromLTWH(imgL, imgT, finalImgW.toDouble(), finalImgH.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    cvs.restore();

    // ── Layer 1: Logo + EXIF ──
    if (hasInfo) {
      final iL = borderW.toDouble();
      final iT = infoAbove ? 0.0 : (imgT + finalImgH + borderW).toDouble();
      final iW = finalImgW.toDouble();
      double y = iT + textPad;

      if (logoImg != null) {
        final logoBaseH = config.logoSize * 48.0 * scale;
        final ar = logoImg.width / logoImg.height;
        final logoW = logoBaseH * ar;
        final logoX = iL + (iW - logoW) / 2;
        cvs.drawImageRect(
          logoImg,
          ui.Rect.fromLTWH(
            0,
            0,
            logoImg.width.toDouble(),
            logoImg.height.toDouble(),
          ),
          ui.Rect.fromLTWH(logoX, y, logoW, logoBaseH),
          ui.Paint()
            ..color = ui.Color.fromARGB(
              (config.logoOpacity * 255).round().clamp(0, 255),
              255,
              255,
              255,
            ),
        );
        y += logoBaseH;
        if (exifPara != null) y += textPad / 2.0;
      }

      if (exifPara != null) {
        exifPara.layout(ui.ParagraphConstraints(width: iW - 2 * textPad));
        cvs.drawParagraph(exifPara, ui.Offset(iL + textPad, y));
      }
    }

    // ── 产出 ──
    final pic = rec.endRecording();
    final result = await pic.toImage(cw, ch);
    pic.dispose();
    bgBlur?.dispose();
    customBg?.dispose();
    logoImg?.dispose();

    return result;
  }

  // ──────────────── 内部工具 ────────────────

  /// 统一图片加载：从 Uint8List 解码为 ui.Image
  static Future<ui.Image?> _loadBytesAsImage(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null; // fail-safe
    }
  }

  /// 加载 Logo 图片（内置或自定义）
  static Future<ui.Image?> _loadLogoImage(WatermarkConfig config) async {
    if (config.logoSource == LogoSource.custom &&
        config.customLogoPath != null) {
      final bytes = await WatermarkAssetManager.readImageBytes(
        config.customLogoPath!,
      );
      return _loadBytesAsImage(bytes);
    }
    // 内置品牌 Logo
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

  static bool _hasLogo(WatermarkConfig c) {
    if (c.logoSource == LogoSource.custom && c.customLogoPath != null)
      return true;
    if (c.logoSource == LogoSource.builtin && c.logoBrand != null) return true;
    return false;
  }

  static String _logoAssetPath(String brand, WatermarkColorMode m) =>
      'assets/borders/logos/${m == WatermarkColorMode.light ? 'light' : 'dark'}/$brand.webp';

  /// 填充绘制
  static void _drawFill(ui.Canvas cvs, ui.Image img, int tw, int th) {
    cvs.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
  }

  /// Fallback 背景
  static void _drawFallbackBg(ui.Canvas cvs, int tw, int th) {
    cvs.drawRect(
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF1A1A1A),
    );
  }

  /// 解析 EXIF 文本
  static String? _resolveExif(WatermarkConfig config, RawMetadata? meta) {
    if (config.exifMode == ExifMode.custom) {
      final t = config.customExifText?.trim();
      return (t != null && t.isNotEmpty) ? t : null;
    }
    return _exifString(meta);
  }

  /// 创建降采样模糊背景
  static Future<ui.Image?> _makeBlurBg(
    ui.Image src,
    double sigma,
    int tw,
    int th,
  ) async {
    final sw = src.width.toDouble(), sh = src.height.toDouble();
    final srcLong = math.max(sw, sh);
    final down = srcLong > 256 ? 256 / srcLong : 1.0;
    final dw = (sw * down).round(), dh = (sh * down).round();

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

    final r2 = ui.PictureRecorder();
    final c2 = ui.Canvas(r2);
    final cs = sigma * down;
    c2.saveLayer(
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: cs.clamp(0.0, 50.0),
          sigmaY: cs.clamp(0.0, 50.0),
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
