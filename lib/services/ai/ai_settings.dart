import 'package:shared_preferences/shared_preferences.dart';
import 'ai_providers.dart';

class AISettings {
  static const _kProvider = 'ai_provider';
  static const _kMaxEdge = 'ai_max_edge';
  static const _kAutoAI = 'ai_auto_tether';
  static String _keyOf(AIProviderId id) => 'ai_key_${id.name}';
  static String _modelOf(AIProviderId id) => 'ai_model_${id.name}';

  static const defaultMaxEdge = 1568;
  static const defaultProvider = AIProviderId.deepseek;

  static Future<AIProviderId> getProvider() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kProvider);
    return AIProviderId.values.firstWhere(
      (e) => e.name == s,
      orElse: () => defaultProvider,
    );
  }

  static Future<void> setProvider(AIProviderId id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProvider, id.name);
  }

  /// 不指定 id 时使用当前选中 provider 的 key
  static Future<String?> getApiKey([AIProviderId? id]) async {
    final pid = id ?? await getProvider();
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyOf(pid));
  }

  static Future<void> setApiKey(AIProviderId id, String? key) async {
    final p = await SharedPreferences.getInstance();
    if (key == null || key.isEmpty) {
      await p.remove(_keyOf(id));
    } else {
      await p.setString(_keyOf(id), key);
    }
  }

  static Future<String> getModel([AIProviderId? id]) async {
    final pid = id ?? await getProvider();
    final p = await SharedPreferences.getInstance();
    return p.getString(_modelOf(pid)) ?? AIProvider.byId(pid).defaultModelId;
  }

  static Future<void> setModel(AIProviderId id, String model) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_modelOf(id), model);
  }

  static Future<int> getMaxEdge() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kMaxEdge) ?? defaultMaxEdge;
  }

  static Future<void> setMaxEdge(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMaxEdge, v.clamp(512, 4096));
  }

  // === 自定义 API 提供商 ===
  static const _kCustomEndpoint = 'ai_custom_endpoint';
  static const _kCustomFormat = 'ai_custom_format';

  static Future<String> getCustomEndpoint() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kCustomEndpoint) ?? '';
  }

  static Future<void> setCustomEndpoint(String url) async {
    final p = await SharedPreferences.getInstance();
    if (url.isEmpty) {
      await p.remove(_kCustomEndpoint);
    } else {
      await p.setString(_kCustomEndpoint, url);
    }
  }

  static Future<String> getCustomFormat() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kCustomFormat) ?? AIProvider.kAnthropicFormat;
  }

  static Future<void> setCustomFormat(String format) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCustomFormat, format);
  }

  // === 联机自动建议 ===
  static Future<bool> getAutoAI() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAutoAI) ?? false;
  }

  static Future<void> setAutoAI(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoAI, v);
  }
}
