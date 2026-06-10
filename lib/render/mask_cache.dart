import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/models/mask_shape.dart';
import 'brush_rasterizer.dart';

/// Develop pass 多条目 LRU 缓存：避免 undo/redo 导致缓存颠簸
class DevelopPassCache {
  static const _capacity = 3;
  final Map<Object, _CachedImage> _entries = {};
  int _seq = 0;

  Future<ui.Image> getOrCompute(
    Object key,
    Future<ui.Image> Function() compute,
  ) async {
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing; // 重新插入，标记为最新
      return existing.image;
    }
    final img = await compute();
    _entries[key] = _CachedImage(img, _seq++);
    _evict();
    return img;
  }

  void _evict() {
    while (_entries.length > _capacity) {
      Object? oldestKey;
      int oldestSeq = -1;
      for (final e in _entries.entries) {
        if (oldestSeq == -1 || e.value.seq < oldestSeq) {
          oldestSeq = e.value.seq;
          oldestKey = e.key;
        }
      }
      if (oldestKey != null) {
        _entries.remove(oldestKey)?.image.dispose();
      }
    }
  }

  void dispose() {
    for (final e in _entries.values) {
      e.image.dispose();
    }
    _entries.clear();
  }
}

class _CachedImage {
  final ui.Image image;
  final int seq;
  _CachedImage(this.image, this.seq);
}

// ── Brush mask 缓存 ──

class _BrushEntry {
  final BrushMask mask;
  final ui.Image texture;
  final int guideEpoch;
  _BrushEntry(this.mask, this.texture, this.guideEpoch);
}

class BrushMaskCache {
  static const _maxEntries = 8;
  final Map<String, _BrushEntry> _cache = {};
  final List<String> _accessOrder = []; // 前 = LRU

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
        // 标记为 MRU
        _accessOrder.remove(maskId);
        _accessOrder.add(maskId);
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
    _accessOrder.remove(maskId);
    _accessOrder.add(maskId);
    _evict();
    return tex;
  }

  void _evict() {
    while (_cache.length > _maxEntries) {
      final evictId = _accessOrder.removeAt(0);
      _cache.remove(evictId)?.texture.dispose();
    }
  }

  /// Local adjustment 删除时主动释放缓存条目，避免 GPU 内存残留
  void evict(String maskId) {
    final e = _cache.remove(maskId);
    e?.texture.dispose();
    _accessOrder.remove(maskId);
  }

  void dispose() {
    for (final e in _cache.values) {
      e.texture.dispose();
    }
    _cache.clear();
    _accessOrder.clear();
  }
}
