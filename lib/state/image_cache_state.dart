import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/decoded_image_cache.dart';

/// 预览解码缓存的容量（张数）。0 = 禁用缓存。
class ImageCacheCapacityNotifier extends Notifier<int> {
  static const _key = 'image_cache_capacity';
  static const _default = 3;

  @override
  int build() {
    _load();
    // 初始即同步给缓存（_load 异步，先用默认值）
    DecodedImageCache.instance.setCapacity(_default);
    return _default;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key) ?? _default;
    state = v;
    DecodedImageCache.instance.setCapacity(v);
  }

  Future<void> set(int n) async {
    state = n;
    DecodedImageCache.instance.setCapacity(n);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, n);
  }
}

final imageCacheCapacityProvider =
    NotifierProvider<ImageCacheCapacityNotifier, int>(
      ImageCacheCapacityNotifier.new,
    );