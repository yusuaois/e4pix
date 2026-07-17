import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 将打包的 assets 文件按 app 版本释放到可写目录
///
/// 适用场景：preset、lensfun 等"应用内置 + 用户可修改/删除"的资源
///
/// 行为：
/// - 首次启动或 app 升级：释放 assets 下匹配的文件到目标目录，覆盖同名文件
/// - 版本未变：跳过，什么也不做
/// - [deletedBasenames] 中的文件（无后缀名）不会被重新释放（用户手动删除的）
/// - 升级后，系统中不存在的旧文件会被清理
class AssetsInit {
  /// 检查 app 版本，如果版本已变（首次启动或升级），将 [assetPrefix] 下匹配
  /// [fileExtension] 的文件复制到 [targetDirPath]，跳过 [deletedBasenames] 中的文件
  ///
  /// 返回 [ReleaseResult.released] 表示执行了释放，[ReleaseResult.skipped] 表示版本未变
  static Future<ReleaseResult> releaseIfNeeded({
    required String namespace,
    required String assetPrefix,
    required String fileExtension,
    required String targetDirPath,
    Set<String>? deletedBasenames,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final versionKey = 'assets_init_version_$namespace';
    final storedVersion = prefs.getString(versionKey);

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    if (storedVersion == currentVersion) return ReleaseResult.skipped;

    final targetDir = Directory(targetDirPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final deleted = deletedBasenames ?? {};
    final currentFiles = <String>{};

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final key in manifest.listAssets()) {
      if (!key.startsWith(assetPrefix) || !key.endsWith(fileExtension)) {
        continue;
      }

      final basename = p.basenameWithoutExtension(key);
      if (deleted.contains(basename)) continue;

      final filename = p.basename(key);
      final destPath = p.join(targetDirPath, filename);
      currentFiles.add(filename);

      try {
        final data = await rootBundle.load(key);
        await File(destPath).writeAsBytes(data.buffer.asUint8List());
      } catch (e) {
        debugPrint('[AssetsInit] Failed to write $filename: $e');
      }
    }

    // 升级：清理旧版本中存在但新版本 assets 中已移除的文件
    if (storedVersion != null) {
      final entries = targetDir.listSync().whereType<File>();
      for (final file in entries) {
        if (p.extension(file.path) != fileExtension) continue;
        if (currentFiles.contains(p.basename(file.path))) continue;
        final basename = p.basenameWithoutExtension(file.path);
        if (deleted.contains(basename)) continue;
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    await prefs.setString(versionKey, currentVersion);
    return ReleaseResult.released;
  }
}

enum ReleaseResult { released, skipped }
