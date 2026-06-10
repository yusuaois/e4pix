import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/watermark_config.dart';

const _kPrefsKey = 'watermark_config';

class WatermarkNotifier extends Notifier<WatermarkConfig> {
  @override
  WatermarkConfig build() {
    _load();
    return const WatermarkConfig();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        state = WatermarkConfig.fromJson(json);
      }
    } catch (_) {
      // 解析失败则保持默认
    }
  }

  Future<void> _persist(WatermarkConfig config) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPrefsKey, jsonEncode(config.toJson()));
    } catch (_) {
      // 持久化失败静默
    }
  }

  void update(WatermarkConfig config) {
    state = config;
    _persist(config);
  }

  void toggle() {
    final next = state.copyWith(enabled: !state.enabled);
    state = next;
    _persist(next);
  }

  void reset() {
    const defaults = WatermarkConfig();
    state = defaults;
    _persist(defaults);
  }
}

final watermarkConfigProvider =
    NotifierProvider<WatermarkNotifier, WatermarkConfig>(WatermarkNotifier.new);
