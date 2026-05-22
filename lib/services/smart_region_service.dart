import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../render/crop_transform.dart';
import '../render/mask_cache.dart';
import '../render/render_engine.dart';
import '../state/brush_state.dart';
import '../state/local_state.dart';
import '../state/providers.dart';

class SmartRegionService {
  /// 从种子点（裁剪后输出归一化坐标）按颜色连通生长 + 导向滤波收边，写回基底
  static Future<void> compute(
    WidgetRef ref, {
    required String maskId,
    required ui.Offset seed,
  }) async {
    final program = ref.read(shaderProgramProvider).value;
    final image = ref.read(imageNotifierProvider).value;
    if (program == null || image == null) return;

    final params = ref.read(currentParamsNotifierProvider);
    final lut = ref.read(lutNotifierProvider);
    final lutEnabled = ref.read(effectiveLutEnabledProvider);
    final tol = ref.read(wandToleranceProvider).clamp(0.01, 1.0);
    final invert = ref.read(wandInvertProvider);

    // 1) 渲染 develop（~1280）
    const maxEdge = 1280;
    final src = image.uiImage;
    final longest = math.max(src.width, src.height);
    final scale = longest > maxEdge ? maxEdge / longest : 1.0;
    final tw = (src.width * scale).round();
    final th = (src.height * scale).round();

    ui.Image guideImg = await RenderEngine.renderToImage(
      program: program,
      sourceImage: src,
      params: params,
      lutTexture: lutEnabled ? lut.texture : null,
      lutSize: lutEnabled ? lut.size : 0,
      targetWidth: tw,
      targetHeight: th,
    );

    // 2) crop
    if (!params.crop.isIdentity) {
      final cropped = await applyCropTransform(guideImg, params.crop);
      guideImg.dispose();
      guideImg = cropped;
    }

    final gw = guideImg.width;
    final gh = guideImg.height;
    final bd = await guideImg.toByteData(format: ui.ImageByteFormat.rawRgba);
    guideImg.dispose();
    if (bd == null) return;
    final guide = bd.buffer.asUint8List();

    // 3) flood fill
    final mask = _floodFill(guide, gw, gh, seed, tol);

    // 4) 导向滤波收边
    final r = (gw * 0.006).round().clamp(2, 32);
    refineMaskEdges(mask, guide, gw, gh, r, 0.0025);

    // 5) 反选
    if (invert) {
      for (int i = 0; i < mask.length; i++) {
        mask[i] = 1.0 - mask[i];
      }
    }

    // 6) 转单通道并写回
    final raster = Uint8List(gw * gh);
    for (int i = 0; i < gw * gh; i++) {
      int v = (mask[i] * 255.0).round();
      if (v < 0) v = 0;
      if (v > 255) v = 255;
      raster[i] = v;
    }
    LocalAdjustmentActions(ref).setBaseRaster(maskId, raster, gw, gh);
  }

  static Float32List _floodFill(
    Uint8List guide,
    int w,
    int h,
    ui.Offset seedNorm,
    double tol,
  ) {
    final out = Float32List(w * h);
    final sx = (seedNorm.dx * w).round().clamp(0, w - 1);
    final sy = (seedNorm.dy * h).round().clamp(0, h - 1);
    final si = sy * w + sx;
    final sr = guide[si * 4].toDouble();
    final sg = guide[si * 4 + 1].toDouble();
    final sb = guide[si * 4 + 2].toDouble();

    // 局部边缘阈值：跨过强色阶就停（停在山脉/地平线的关键）
    final edgeStop = 0.045 + tol * 0.20;

    double dist(double r1, double g1, double b1, double r2, double g2,
        double b2) {
      final dr = (r1 - r2) / 255.0;
      final dg = (g1 - g2) / 255.0;
      final db = (b1 - b2) / 255.0;
      return math.sqrt(dr * dr + dg * dg + db * db) / 1.7320508;
    }

    final visited = Uint8List(w * h);
    final stack = <int>[];
    visited[si] = 1;
    out[si] = 1.0;
    stack.add(si);

    while (stack.isNotEmpty) {
      final a = stack.removeLast();
      final ax = a % w, ay = a ~/ w;
      final ar = guide[a * 4].toDouble();
      final ag = guide[a * 4 + 1].toDouble();
      final ab = guide[a * 4 + 2].toDouble();
      for (int ny = ay - 1; ny <= ay + 1; ny++) {
        if (ny < 0 || ny >= h) continue;
        for (int nx = ax - 1; nx <= ax + 1; nx++) {
          if (nx < 0 || nx >= w) continue;
          final b = ny * w + nx;
          if (visited[b] == 1) continue;
          final br = guide[b * 4].toDouble();
          final bg = guide[b * 4 + 1].toDouble();
          final bb = guide[b * 4 + 2].toDouble();
          // 判据1：与种子整体相近（松）
          if (dist(br, bg, bb, sr, sg, sb) > tol) continue;
          // 判据2：与当前像素局部相近，不跨边缘（关键）
          if (dist(br, bg, bb, ar, ag, ab) > edgeStop) continue;
          visited[b] = 1; // 只对纳入的标记，失败像素留待其他更平滑路径
          out[b] = 1.0;
          stack.add(b);
        }
      }
    }
    return out;
  }
}