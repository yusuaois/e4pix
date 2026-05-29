import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/crop_params.dart';
import '../render/crop_transform.dart';
import '../render/render_engine.dart';
import '../state/providers.dart';
import 'sam_session.dart';

class SegmentationService {
  static Future<bool> compute(
    WidgetRef ref, {
    required String maskId,
    required ui.Offset seed,
    bool invert = false,
    bool negative = false,
  }) async {
    final program = ref.read(shaderProgramProvider).value;
    final image = ref.read(imageNotifierProvider).value;
    if (program == null || image == null) return false;
    if (!await SamSession.instance.ensureLoaded()) return false;

    final params = ref.read(currentParamsNotifierProvider);
    final lut = ref.read(lutNotifierProvider);
    final lutEnabled = ref.read(effectiveLutEnabledProvider);

    const maxEdge = 1024;
    final src = image.uiImage;
    final longest = math.max(src.width, src.height);
    final scale = longest > maxEdge ? maxEdge / longest : 1.0;
    final tw = (src.width * scale).round();
    final th = (src.height * scale).round();

    ui.Image guideImg = await RenderEngine.renderToImage(
      program: program,
      sourceImage: src,
      params: params,
      lutTexture: lutEnabled ? lut.textureA : null,
      lutSize: lutEnabled ? lut.sizeA : 0,
      lutTextureB: lutEnabled ? lut.textureB : null,
      lutSizeB: lutEnabled ? lut.sizeB : 0,
      targetWidth: tw,
      targetHeight: th,
    );
    if (!params.crop.isIdentity) {
      final cropped = await applyCropTransform(guideImg, params.crop);
      guideImg.dispose();
      guideImg = cropped;
    }
    final gw = guideImg.width, gh = guideImg.height;
    final bd = await guideImg.toByteData(format: ui.ImageByteFormat.rawRgba);
    guideImg.dispose();
    if (bd == null) return false;
    final guide = bd.buffer.asUint8List();

    final sig = Object.hash(
      identityHashCode(src),
      params.copyWith(locals: const [], crop: CropParams.identity).hashCode,
      params.crop.hashCode,
      gw,
      gh,
    );
    await SamSession.instance.ensureEmbedding(
      guide: guide,
      gw: gw,
      gh: gh,
      signature: sig,
    );
    final mask = await SamSession.instance.decode(seed, negative: negative);
    if (mask == null) return false;

    _featherBox(mask, gw, gh, (gw * 0.0015).round().clamp(1, 3));
    if (invert) {
      for (int i = 0; i < mask.length; i++) {
        mask[i] = 1.0 - mask[i];
      }
    }

    final raster = Uint8List(gw * gh);
    for (int i = 0; i < gw * gh; i++) {
      int v = (mask[i] * 255.0).round();
      raster[i] = v < 0 ? 0 : (v > 255 ? 255 : v);
    }
    LocalAdjustmentActions(ref).setBaseRaster(maskId, raster, gw, gh);
    return true;
  }

  static void _featherBox(Float32List m, int w, int h, int r) {
    if (r < 1) return;
    final win = 2 * r + 1;
    final tmp = Float32List(w * h);
    for (int y = 0; y < h; y++) {
      final base = y * w;
      double sum = 0;
      for (int k = -r; k <= r; k++) {
        sum += m[base + (k < 0 ? 0 : (k >= w ? w - 1 : k))];
      }
      for (int x = 0; x < w; x++) {
        tmp[base + x] = sum / win;
        final ai = x + r + 1 >= w ? w - 1 : x + r + 1;
        final ri = x - r < 0 ? 0 : x - r;
        sum += m[base + ai] - m[base + ri];
      }
    }
    for (int x = 0; x < w; x++) {
      double sum = 0;
      for (int k = -r; k <= r; k++) {
        sum += tmp[(k < 0 ? 0 : (k >= h ? h - 1 : k)) * w + x];
      }
      for (int y = 0; y < h; y++) {
        m[y * w + x] = sum / win;
        final ai = y + r + 1 >= h ? h - 1 : y + r + 1;
        final ri = y - r < 0 ? 0 : y - r;
        sum += tmp[ai * w + x] - tmp[ri * w + x];
      }
    }
  }
}
