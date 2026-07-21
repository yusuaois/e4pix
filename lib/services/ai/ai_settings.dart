import 'package:shared_preferences/shared_preferences.dart';
import 'ai_providers.dart';

class AISettings {
  static const _kProvider = 'ai_provider';
  static const _kMaxEdge = 'ai_max_edge';
  static const _kAutoAI = 'ai_auto_tether';

  static String _keyOfId(String id) => 'ai_key_$id';
  static String _modelOfId(String id) => 'ai_model_$id';
  static String _endpointOfId(String id) => 'ai_endpoint_$id';

  static const defaultMaxEdge = 1568;
  // 须与 AIProviderPreset.all 第一项匹配
  static const _defaultProviderId = 'anthropic';

  // ── 提供商 ──

  static Future<String> getProvider() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kProvider);
    if (raw == null) return _defaultProviderId;

    // 已是有效预设 id？
    if (AIProviderPreset.safeById(raw) != null) return raw;

    return _defaultProviderId;
  }

  static Future<void> setProvider(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProvider, id);
  }

  // API Key

  /// 不指定 id 时使用当前选中 provider 的 key
  static Future<String?> getApiKey([String? pid]) async {
    final id = pid ?? await getProvider();
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyOfId(id));
  }

  static Future<void> setApiKey(String pid, String? key) async {
    final p = await SharedPreferences.getInstance();
    if (key == null || key.isEmpty) {
      await p.remove(_keyOfId(pid));
    } else {
      await p.setString(_keyOfId(pid), key);
    }
  }

  // Model

  static Future<String> getModel([String? pid]) async {
    final id = pid ?? await getProvider();
    final p = await SharedPreferences.getInstance();
    return p.getString(_modelOfId(id)) ??
        AIProviderPreset.byId(id).defaultModelId;
  }

  static Future<void> setModel(String pid, String model) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_modelOfId(pid), model);
  }

  // Endpoint (per-preset, falls back to preset default)

  static Future<String> getEndpoint([String? pid]) async {
    final id = pid ?? await getProvider();
    final preset = AIProviderPreset.byId(id);
    final p = await SharedPreferences.getInstance();
    return p.getString(_endpointOfId(id)) ?? preset.defaultEndpoint ?? '';
  }

  static Future<void> setEndpoint(String pid, String url) async {
    final p = await SharedPreferences.getInstance();
    if (url.isEmpty) {
      await p.remove(_endpointOfId(pid));
    } else {
      await p.setString(_endpointOfId(pid), url);
    }
  }

  // Max edge

  static Future<int> getMaxEdge() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kMaxEdge) ?? defaultMaxEdge;
  }

  static Future<void> setMaxEdge(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMaxEdge, v.clamp(512, 4096));
  }

  // Auto AI

  static Future<bool> getAutoAI() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAutoAI) ?? false;
  }

  static Future<void> setAutoAI(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoAI, v);
  }
}
