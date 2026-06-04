import 'dart:ui' as ui;

import '../core/lut/cube_lut.dart';
import '../services/lut_library.dart';

/// 一个已加载的 LUT texture（HALD strip）+ size
class LutTexture {
  final ui.Image texture;
  final int size;
  const LutTexture(this.texture, this.size);
}

/// 按 LUT 名字缓存已加载的 texture，LRU
///
/// per-image LUT 下，切图频繁按名字加载 LUT；缓存避免重复解析 .cube + 生成 strip
/// 缓存接管 texture 生命周期：淘汰时 dispose
class LutTextureCache {
  LutTextureCache._();
  static final instance = LutTextureCache._();

  final _map = <String, LutTexture>{};
  final int _capacity = 8; // 缓存容量

  /// 按名字取已缓存的 texture（命中提升为最近使用）
  /// 无则 null
  LutTexture? peek(String name) {
    final hit = _map.remove(name);
    if (hit != null) _map[name] = hit;
    return hit;
  }

  /// 按名字加载 LUT texture（命中缓存直接返回，否则从库解析）
  /// 名字在 LUT 库中找不到 → 返回 null
  Future<LutTexture?> load(String name) async {
    final cached = peek(name);
    if (cached != null) return cached;

    // 在库中按名字找文件
    final library = await LutLibrary.listAll();
    LutEntry? entry;
    final target = name.toLowerCase();
    for (final e in library) {
      if (e.name.toLowerCase() == target) {
        entry = e;
        break;
      }
    }
    if (entry == null) return null; // 库里没有该 LUT

    try {
      final lut = await CubeLut.fromFile(entry.filePath);
      final tex = await lut.toHaldStrip();
      final entry2 = LutTexture(tex, lut.size);
      _put(name, entry2);
      return entry2;
    } catch (_) {
      return null;
    }
  }

  void _put(String name, LutTexture entry) {
    final existing = _map.remove(name);
    if (existing != null && !identical(existing.texture, entry.texture)) {
      _disposeLater(existing.texture);
    }
    _map[name] = entry;
    while (_map.length > _capacity) {
      final oldestKey = _map.keys.first;
      final old = _map.remove(oldestKey);
      if (old != null) _disposeLater(old.texture);
    }
  }

  /// 该 texture 是否由缓存持有
  bool ownsTexture(ui.Image tex) {
    for (final t in _map.values) {
      if (identical(t.texture, tex)) return true;
    }
    return false;
  }

  /// 名字对应的 LUT 文件已删除时调用
  void invalidate(String name) {
    final old = _map.remove(name);
    if (old != null) _disposeLater(old.texture);
  }

  void clear() {
    for (final t in _map.values) {
      _disposeLater(t.texture);
    }
    _map.clear();
  }

  void _disposeLater(ui.Image img) {
    Future.microtask(() {
      try {
        img.dispose();
      } catch (_) {}
    });
  }
}
