import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import '../core/lut/cube_lut.dart';
import '../services/lut/lut_library.dart';

/// 一个已加载的 LUT texture（HALD strip）+ size
class LutTexture {
  final ui.Image texture;
  final int size;
  const LutTexture(this.texture, this.size);
}

/// 按 LUT 名字缓存已加载的 texture，LRU
class LutTextureCache {
  LutTextureCache._();
  static final instance = LutTextureCache._();

  final _map = <String, LutTexture>{};
  final int _capacity = 8; // 缓存容量
  final Set<String> _activeLuts = {}; // 受保护的活跃 LUT 名称集合

  /// 标记当前正在使用的 LUT，防止被意外淘汰
  void protect(String? lutA, String? lutB) {
    _activeLuts.clear();
    if (lutA != null && lutA.isNotEmpty) _activeLuts.add(lutA);
    if (lutB != null && lutB.isNotEmpty) _activeLuts.add(lutB);
  }

  LutTexture? peek(String name) {
    final hit = _map.remove(name);
    if (hit != null) _map[name] = hit;
    return hit;
  }

  Future<LutTexture?> load(String name) async {
    final cached = peek(name);
    if (cached != null) return cached;

    final library = await LutLibrary.listAll();
    LutEntry? entry;
    final target = name.toLowerCase();
    for (final e in library) {
      if (e.name.toLowerCase() == target) {
        entry = e;
        break;
      }
    }
    if (entry == null) return null;

    try {
      final lut = await CubeLut.fromFile(entry.filePath);
      final tex = await lut.toHaldStrip();
      final entry2 = LutTexture(tex, lut.size);
      _put(name, entry2);
      return entry2;
    } catch (e) {
      debugPrint('[LutTextureCache] Failed to load LUT "$name": $e');
      return null;
    }
  }

  void _put(String name, LutTexture entry) {
    final existing = _map.remove(name);
    if (existing != null && !identical(existing.texture, entry.texture)) {
      _disposeLater(existing.texture);
    }
    _map[name] = entry;

    // 跳过受保护的活跃 LUT
    while (_map.length > _capacity) {
      String? keyToEvict;
      // 从最旧的条目开始寻找第一个"不受保护"的 LUT
      for (final key in _map.keys) {
        if (!_activeLuts.contains(key)) {
          keyToEvict = key;
          break;
        }
      }

      // 如果找到了可以淘汰的 LUT
      if (keyToEvict != null) {
        final old = _map.remove(keyToEvict);
        if (old != null) _disposeLater(old.texture);
      } else {
        break;
      }
    }
  }

  bool ownsTexture(ui.Image tex) {
    for (final t in _map.values) {
      if (identical(t.texture, tex)) return true;
    }
    return false;
  }

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
    // 延迟释放 GPU 资源，与 DecodedImageCache 保持一致
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        img.dispose();
      } catch (_) {}
    });
  }
}
