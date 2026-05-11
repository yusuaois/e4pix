import 'package:shared_preferences/shared_preferences.dart';

class AISettings {
  static const _kApiKey = 'ai_anthropic_key';
  static const _kModel = 'ai_model';
  static const _kMaxEdge = 'ai_max_edge';

  // deepseek
  static const defaultModel = 'deepseek-v4-flash';
  static const defaultMaxEdge = 768;

  // shared_preferences 在 Android 上是 app-private 文件，不加密
  static Future<String?> getApiKey() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kApiKey);
  }

  static Future<void> setApiKey(String? key) async {
    final p = await SharedPreferences.getInstance();
    if (key == null || key.isEmpty) {
      await p.remove(_kApiKey);
    } else {
      await p.setString(_kApiKey, key);
    }
  }

  static Future<String> getModel() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kModel) ?? defaultModel;
  }

  static Future<void> setModel(String model) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kModel, model);
  }

  static Future<int> getMaxEdge() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kMaxEdge) ?? defaultMaxEdge;
  }
}