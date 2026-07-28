import 'dart:ui' as ui;

import '../native/raw_bridge.dart';

/// 缓存的解码结果：preview 级 ui.Image + 元数据 + 尺寸信息
///
/// image 的生命周期由 [DecodedImageCache] 接管——淘汰时 dispose
/// 调用方拿到后只读不 dispose
class CachedDecode {
  final ui.Image image;
  final RawMetadata metadata;
  final int width;
  final int height;
  final int bitsPerChannel;

  const CachedDecode({
    required this.image,
    required this.metadata,
    required this.width,
    required this.height,
    required this.bitsPerChannel,
  });
}

/// 解码后 preview 的 LRU 缓存（按图片路径）
///
/// 缓存 develop 之前的源图
/// 缓存接管 image 生命周期：淘汰/失效时 dispose；调用方不要 dispose 已入缓存的 image
class DecodedImageCache {
  DecodedImageCache._();
  static final instance = DecodedImageCache._();

  final _map = <String, CachedDecode>{};
  int _capacity = 3;

  int get capacity => _capacity;

  /// 设置容量 变小立即淘汰多余项；0 = 禁用并清空
  void setCapacity(int n) {
    _capacity = n < 0 ? 0 : n;
    _evictToCapacity();
  }

  /// 取缓存，命中则提升为最近使用
  CachedDecode? get(String path) {
    final hit = _map.remove(path);
    if (hit != null) _map[path] = hit;
    return hit;
  }

  bool containsPath(String path) => _map.containsKey(path);

  /// 该 image 是否由缓存持有
  bool ownsImage(ui.Image image) =>
      _map.values.any((c) => identical(c.image, image));

  /// 存入缓存 若已有同 path 旧项且 image 不同，dispose 旧 image
  /// 容量为 0 时直接 dispose 传入 image（调用方已交出所有权）
  void put(String path, CachedDecode entry) {
    if (_capacity <= 0) {
      _disposeLater(entry.image);
      return;
    }
    final existing = _map.remove(path);
    if (existing != null && !identical(existing.image, entry.image)) {
      _disposeLater(existing.image);
    }
    _map[path] = entry;
    _evictToCapacity();
  }

  /// 移除并 dispose 指定 path（文件被删/改时）
  void invalidate(String path) {
    final c = _map.remove(path);
    if (c != null) _disposeLater(c.image);
  }

  void clear() {
    for (final c in _map.values) {
      _disposeLater(c.image);
    }
    _map.clear();
  }

  void _evictToCapacity() {
    while (_map.length > _capacity) {
      final oldestKey = _map.keys.first;
      final c = _map.remove(oldestKey);
      if (c != null) _disposeLater(c.image);
    }
  }

  // 延迟 dispose：确保异步渲染引用已释放后再清理 GPU 资源
  void _disposeLater(ui.Image img) {
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        img.dispose();
      } catch (_) {}
    });
  }
}
