import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/watermark_config.dart';
import '../native/raw_bridge.dart';

/// 离屏 Canvas 水印边框合成器
///
/// 关键设计：
/// - UI 上所有尺寸参数（borderWidth, cornerRadius, fontSize 等）都是基于
///   `kRefPreviewSize` 的**逻辑像素**
/// - 导出时按全分辨率原图等比放大：`scale = max(renderedW, renderedH) / kRefPreviewSize`
/// - 使用 PictureRecorder + Canvas 分步绘制，全程不构建 Widget Tree，避免移动端 OOM
class WatermarkExporter {
  WatermarkExporter._();

  /// 预览参考尺寸（逻辑像素），所有 UI 参数基于此尺寸设计
  static const double kRefPreviewSize = 1000.0;

  /// 合成水印边框，返回 [ui.Image]。
  ///
  /// [renderedImage] 是 FullPipelineRenderer 的调色输出（全分辨率带裁剪）。
  /// 调用方负责 dispose 返回的 Image。
  static Future<ui.Image> composite({
    required ui.Image renderedImage,
    required WatermarkConfig config,
    required RawMetadata? metadata,
  }) async {
    final rw = renderedImage.width.toDouble();
    final rh = renderedImage.height.toDouble();
    final longest = math.max(rw, rh);

    // ═══════════════════════════════════════════════════════
    // 比例映射：逻辑 px → 全分辨率 px
    // ═══════════════════════════════════════════════════════
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
    // 信息层度量
    // ═══════════════════════════════════════════════════════
    final exifStr = config.showExif ? _exifString(metadata) : null;
    final hasLogo = config.logoBrand != null;
    final hasInfo = exifStr != null || hasLogo;

    int infoH = 0;
    ui.Paragraph? exifPara;
    ui.Image? logoImg;

    if (hasInfo) {
      double logoH = 0;
      if (hasLogo) {
        final path = _logoPath(config.logoBrand!, config.colorMode);
        logoImg = await _loadAsset(path);
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
        final b =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  ellipsis: '…',
                  textDirection: ui.TextDirection.ltr,
                ),
              )
              ..pushStyle(_toUiStyle(ts))
              ..addText(exifStr);
        exifPara = b.build()
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
    // 模糊背景（如需）
    // ═══════════════════════════════════════════════════════
    ui.Image? bgBlur;
    if (config.backgroundType == BackgroundType.blurredOriginal) {
      bgBlur = await _makeBlurBg(
        renderedImage,
        config.blurRadius * scale,
        cw,
        ch,
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
          cvs.drawImageRect(
            bgBlur,
            ui.Rect.fromLTWH(
              0,
              0,
              bgBlur.width.toDouble(),
              bgBlur.height.toDouble(),
            ),
            ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
            ui.Paint(),
          );
        }
      case BackgroundType.image:
        cvs.drawRect(
          ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
          ui.Paint()..color = const ui.Color(0xFF1A1A1A),
        );
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

    // ═══════════════════════════════════════════════════════
    // 产出 ui.Image
    // ═══════════════════════════════════════════════════════
    final pic = rec.endRecording();
    final result = await pic.toImage(cw, ch);
    pic.dispose();
    bgBlur?.dispose();
    logoImg?.dispose();

    return result;
  }

  // ──────────────── 内部工具 ────────────────

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

    // Step 1: 降采样
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

    // Step 2: 模糊 + 放大
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

  static Future<ui.Image?> _loadAsset(String path) async {
    try {
      final d = await rootBundle.load(path);
      final c = await ui.instantiateImageCodec(d.buffer.asUint8List());
      return (await c.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  static String _logoPath(String brand, WatermarkColorMode m) =>
      'assets/borders/logos/${m == WatermarkColorMode.light ? 'light' : 'dark'}/$brand.webp';

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
