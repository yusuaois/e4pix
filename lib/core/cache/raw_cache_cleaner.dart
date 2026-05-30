import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RawCacheCleaner {
  static const _rawExts = [
    '.arw',
    '.cr2',
    '.cr3',
    '.nef',
    '.nrw',
    '.raf',
    '.dng',
    '.orf',
    '.rw2',
    '.pef',
    '.srw',
    '.rwl',
  ];

  /// 启动时清理
  static Future<void> cleanOld({
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(maxAge);
      await for (final entity in cacheDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final upper = entity.path.toUpperCase();
        if (!_rawExts.any((e) => upper.endsWith(e))) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 如果传入的 path 在 cache 目录里就删掉
  static Future<void> deleteIfCached(String path) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (!path.startsWith(cacheDir.path)) return;
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
