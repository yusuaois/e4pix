import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/models/mask_shape.dart';
import 'brush_rasterizer.dart';

/// Develop pass 单条目缓存：按 key 复用同一张 ui.Image
class DevelopPassCache {
  ui.Image? _image;
  Object? _key;

  Future<ui.Image> getOrCompute(
    Object key,
    Future<ui.Image> Function() compute,
  ) async {
    if (_key == key && _image != null) return _image!;
    final img = await compute();
    if (!identical(_image, img)) _image?.dispose();
    _image = img;
    _key = key;
    return img;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
    _key = null;
  }
}

// ── Brush mask 缓存 ──

class _BrushEntry {
  final BrushMask mask;
  final ui.Image texture;
  final int guideEpoch;
  _BrushEntry(this.mask, this.texture, this.guideEpoch);
}

class BrushMaskCache {
  final Map<String, _BrushEntry> _cache = {};

  Future<ui.Image> getOrRasterize(
    String maskId,
    BrushMask mask,
    int w,
    int h, {
    Uint8List? guideBytes,
    int guideWidth = 0,
    int guideHeight = 0,
    int guideEpoch = 0,
    bool allowStaleGuide = false,
  }) async {
    final hasAuto = mask.strokes.any((s) => s.autoMask);
    final e = _cache[maskId];
    final baseOk =
        e != null &&
        identical(e.mask, mask) &&
        e.texture.width == w &&
        e.texture.height == h;
    if (baseOk) {
      if (!hasAuto || e.guideEpoch == guideEpoch || allowStaleGuide) {
        return e.texture;
      }
    }

    final tex = await rasterizeBrushMask(
      mask,
      w,
      h,
      guideBytes: guideBytes,
      guideWidth: guideWidth,
      guideHeight: guideHeight,
    );
    e?.texture.dispose();
    _cache[maskId] = _BrushEntry(mask, tex, guideEpoch);
    return tex;
  }

  void dispose() {
    for (final e in _cache.values) {
      e.texture.dispose();
    }
    _cache.clear();
  }
}
