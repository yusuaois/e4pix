import 'package:shared_preferences/shared_preferences.dart';

// 软件通用设置
class AppSettings {
  static const _kTetherFolder = 'tether_default_folder';

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
}