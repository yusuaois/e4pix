import 'package:shared_preferences/shared_preferences.dart';

// 软件通用设置
class AppSettings {
  static const _kTetherFolder = 'tether_default_folder';
  static const _kExportConcurrency = 'export_concurrency';

  static Future<String?> getTetherFolder() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kTetherFolder);
  }

  static Future<void> setTetherFolder(String? path) async {
    final p = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await p.remove(_kTetherFolder);
    } else {
      await p.setString(_kTetherFolder, path);
    }
  }

  /// 并发导出数（1-4，默认 1）
  static Future<int> getExportConcurrency() async {
    final p = await SharedPreferences.getInstance();
    return (p.getInt(_kExportConcurrency) ?? 1).clamp(1, 4);
  }

  static Future<void> setExportConcurrency(int value) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kExportConcurrency, value.clamp(1, 4));
  }
}
