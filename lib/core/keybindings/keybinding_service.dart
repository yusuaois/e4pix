import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_action.dart';

class KeybindingState {
  final Map<AppAction, LogicalKeyboardKey?> bindings;
  const KeybindingState(this.bindings);

  AppAction? actionFor(LogicalKeyboardKey key) {
    for (final e in bindings.entries) {
      if (e.value == key) return e.key;
    }
    return null;
  }

  LogicalKeyboardKey? keyFor(AppAction a) => bindings[a];
}

class KeybindingNotifier extends Notifier<KeybindingState> {
  static const _prefsKey = 'keybindings_v1';

  @override
  KeybindingState build() {
    _load();
    return KeybindingState({...kDefaultBindings});
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final loaded = <AppAction, LogicalKeyboardKey?>{...kDefaultBindings};
      for (final a in AppAction.values) {
        if (map.containsKey(a.name)) {
          final keyId = map[a.name];
          loaded[a] = keyId == null ? null : LogicalKeyboardKey(keyId as int);
        }
      }
      state = KeybindingState(loaded);
    } catch (e) {
      debugPrint('[Keybinding] Load failed, using defaults: $e');
    }
  }

  Future<void> _persist(Map<AppAction, LogicalKeyboardKey?> b) async {
    try {
      final p = await SharedPreferences.getInstance();
      final map = {for (final e in b.entries) e.key.name: e.value?.keyId};
      await p.setString(_prefsKey, jsonEncode(map));
    } catch (e) {
      debugPrint('[Keybinding] Persist failed: $e');
    }
  }

  // 转发
  AppAction? actionFor(LogicalKeyboardKey key) => state.actionFor(key);
  LogicalKeyboardKey? keyFor(AppAction a) => state.keyFor(a);

  /// 设置绑定
  Future<void> setBinding(AppAction action, LogicalKeyboardKey key) async {
    final next = {...state.bindings};
    // 清除占用同一键的其他动作
    for (final e in next.entries.toList()) {
      if (e.key != action && e.value == key) {
        next[e.key] = null;
      }
    }
    next[action] = key;
    state = KeybindingState(next);
    await _persist(next);
  }

  /// 清除某动作的绑定
  Future<void> clearBinding(AppAction action) async {
    final next = {...state.bindings};
    next[action] = null;
    state = KeybindingState(next);
    await _persist(next);
  }

  /// 全部重置默认
  Future<void> resetDefaults() async {
    final next = {...kDefaultBindings};
    state = KeybindingState(
      next.map((k, v) => MapEntry(k, v as LogicalKeyboardKey?)),
    );
    await _persist(state.bindings);
  }

  /// 找出占用某键的动作
  AppAction? conflictFor(LogicalKeyboardKey key, AppAction exclude) {
    for (final e in state.bindings.entries) {
      if (e.key != exclude && e.value == key) return e.key;
    }
    return null;
  }
}

final keybindingServiceProvider =
    NotifierProvider<KeybindingNotifier, KeybindingState>(
      KeybindingNotifier.new,
    );
