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
  // Must match the first entry in AIProviderPreset.all
  static const _defaultProviderId = 'anthropic';

  // ============================================================
  // Provider
  // ============================================================

  static Future<String> getProvider() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kProvider);
    if (raw == null) return _defaultProviderId;

    // Already a valid preset id?
    if (AIProviderPreset.safeById(raw) != null) return raw;

    // 【可删除】下个大版本：旧 enum 迁移已全部完成，此分支可删
    // Try old enum migration
    final migrated = AIProviderPreset.migrateOldEnumName(raw);
    if (migrated == null) return _defaultProviderId;
    if (migrated != '__needs_custom_migration__') return migrated;

    // 【可删除】与 _migrateOldCustom 一起删
    // Old 'custom' needs special handling
    return await _migrateOldCustom(p);
  }

  static Future<void> setProvider(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProvider, id);
  }

  // ============================================================
  // 【可删除】下个大版本清理：整个 _migrateOldCustom 方法
  // Migration: old AIProviderId.custom → custom_openai | custom_anthropic
  // ============================================================

  static Future<String> _migrateOldCustom(SharedPreferences p) async {
    // Read old custom format to decide which new preset
    final oldFormat = p.getString('ai_custom_format') ?? 'anthropic';
    final newId = oldFormat == 'openai' ? 'custom_openai' : 'custom_anthropic';

    // Migrate: ai_custom_endpoint → ai_endpoint_{newId}
    final oldEndpoint = p.getString('ai_custom_endpoint') ?? '';
    if (oldEndpoint.isNotEmpty) {
      await p.setString(_endpointOfId(newId), oldEndpoint);
    }
    await p.remove('ai_custom_endpoint');

    // Migrate: ai_custom_format → no equivalent needed (protocol is in preset)
    await p.remove('ai_custom_format');

    // Migrate: ai_key_custom → ai_key_{newId}
    final oldKey = p.getString('ai_key_custom');
    if (oldKey != null && oldKey.isNotEmpty) {
      await p.setString(_keyOfId(newId), oldKey);
    }

    // Migrate: ai_model_custom → ai_model_{newId}
    final oldModel = p.getString('ai_model_custom');
    if (oldModel != null && oldModel.isNotEmpty) {
      await p.setString(_modelOfId(newId), oldModel);
    }

    await p.setString(_kProvider, newId);
    return newId;
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
