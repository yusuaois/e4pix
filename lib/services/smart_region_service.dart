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

    final grad = _sobelMag(guide, w, h);
    // 边缘屏障：梯度超过即不跨越
    final gradThr = 0.07 + tol * 0.35;

    double dseed(int b) {
      final dr = (guide[b * 4] - sr) / 255.0;
      final dg = (guide[b * 4 + 1] - sg) / 255.0;
      final db = (guide[b * 4 + 2] - sb) / 255.0;
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
      for (int ny = ay - 1; ny <= ay + 1; ny++) {
        if (ny < 0 || ny >= h) continue;
        for (int nx = ax - 1; nx <= ax + 1; nx++) {
          if (nx < 0 || nx >= w) continue;
          final b = ny * w + nx;
          if (visited[b] == 1) continue;
          if (dseed(b) > tol) continue; // 与种子色相近
          if (grad[b] > gradThr) continue; // 不跨越强边缘
          visited[b] = 1;
          out[b] = 1.0;
          stack.add(b);
        }
      }
    }
    return out;
  }

  // 亮度 Sobel 梯度幅值（0..~1），用作边缘屏障
  static Float32List _sobelMag(Uint8List guide, int w, int h) {
    final lum = Float32List(w * h);
    for (int i = 0; i < w * h; i++) {
      final o = i * 4;
      lum[i] =
          (0.299 * guide[o] + 0.587 * guide[o + 1] + 0.114 * guide[o + 2]) /
          255.0;
    }
    final mag = Float32List(w * h);
    for (int y = 0; y < h; y++) {
      final ym = y > 0 ? y - 1 : 0;
      final yp = y < h - 1 ? y + 1 : h - 1;
      for (int x = 0; x < w; x++) {
        final xm = x > 0 ? x - 1 : 0;
        final xp = x < w - 1 ? x + 1 : w - 1;
        final tl = lum[ym * w + xm],
            tc = lum[ym * w + x],
            tr = lum[ym * w + xp];
        final ml = lum[y * w + xm], mr = lum[y * w + xp];
        final bl = lum[yp * w + xm],
            bc = lum[yp * w + x],
            br = lum[yp * w + xp];
        final gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl);
        final gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr);
        mag[y * w + x] = math.sqrt(gx * gx + gy * gy) / 4.0;
      }
    }
    return mag;
  }
}
