import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../render/cache/decoded_image_cache.dart';

/// 预览解码缓存的容量（张数），0 = 禁用缓存
class ImageCacheCapacityNotifier extends Notifier<int> {
  static const _key = 'image_cache_capacity';

  /// 默认缓存张数
  static const _desktopDefault = 6;
  static const _mobileDefault = 3;

  static int _defaultForPlatform() {
    if (kIsWeb) return _mobileDefault;
    try {
      // 根据系统内存自适应；设备内存不可用则回退平台默认
      final totalMem = _estimateTotalMemoryGB();
      if (totalMem <= 0) {
        return (Platform.isAndroid || Platform.isIOS)
            ? _mobileDefault
            : _desktopDefault;
      }
      if (totalMem <= 4) return 2; // 低内存设备
      if (totalMem <= 8) return 4; // 中等内存
      if (totalMem <= 16) return 8; // 16GB 常见桌面配置
      return 12; // 高内存工作站
    } catch (_) {
      return _desktopDefault;
    }
  }

  static int _estimateTotalMemoryGB() {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        return 0;
      }
      if (Platform.isLinux) {
        final meminfo = File('/proc/meminfo').readAsStringSync();
        final match = RegExp(r'MemTotal:\s+(\d+)').firstMatch(meminfo);
        if (match != null) {
          return (int.parse(match.group(1)!) / 1024 / 1024).round();
        }
      } else if (Platform.isMacOS) {
        final result = Process.runSync('sysctl', ['-n', 'hw.memsize']);
        if (result.exitCode == 0) {
          return (int.parse(result.stdout.toString().trim()) /
                  1024 /
                  1024 /
                  1024)
              .round();
        }
      } else if (Platform.isWindows) {
        return 16;
      }
    } catch (_) {}
    return 0;
  }

  @override
  int build() {
    final initial = _defaultForPlatform();
    DecodedImageCache.instance.setCapacity(initial);
    _load();
    return initial;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null) {
      state = v;
      DecodedImageCache.instance.setCapacity(v);
    }
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
