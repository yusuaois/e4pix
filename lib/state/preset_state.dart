import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/adjustment_params.dart';
import '../core/models/crop_params.dart';
import 'params_state.dart';

@immutable
class Preset {
  final String id;
  final String name;
  final AdjustmentParams params;
  final DateTime createdAt;
  final bool isBuiltin;

  const Preset({
    required this.id,
    required this.name,
    required this.params,
    required this.createdAt,
    this.isBuiltin = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'params': params.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'isBuiltin': isBuiltin,
  };

  factory Preset.fromJson(Map<String, dynamic> j) => Preset(
    id: j['id'] as String,
    name: j['name'] as String,
    params: AdjustmentParams.fromJson(j['params'] as Map<String, dynamic>),
    createdAt: DateTime.parse(j['createdAt'] as String),
    isBuiltin: j['isBuiltin'] as bool? ?? false,
  );
}

class PresetNotifier extends AsyncNotifier<List<Preset>> {
  static const _prefsKey = 'e4pix_presets_v1';

  @override
  Future<List<Preset>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final List<Preset> user = [];
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        user.addAll(
          list.map((j) => Preset.fromJson(j as Map<String, dynamic>)),
        );
      } catch (e) {
        debugPrint('Preset parse failed: $e');
      }
    }
    return [..._builtins(), ...user];
  }

  Future<void> saveCurrentAs(String name) async {
    final current = ref.read(currentParamsNotifierProvider);
    final preset = Preset(
      id: 'p_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      params: current.copyWith(crop: CropParams.identity),
      createdAt: DateTime.now(),
    );
    final list = await future;
    state = AsyncData([...list, preset]);
    await _persist();
  }

  Future<void> rename(String id, String newName) async {
    final list = await future;
    state = AsyncData([
      for (final p in list)
        if (p.id == id && !p.isBuiltin)
          Preset(
            id: p.id,
            name: newName,
            params: p.params,
            createdAt: p.createdAt,
            isBuiltin: p.isBuiltin,
          )
        else
          p,
    ]);
    await _persist();
  }

  Future<void> delete(String id) async {
    final list = await future;
    state = AsyncData(list.where((p) => p.id != id || p.isBuiltin).toList());
    await _persist();
  }

  void apply(String id) {
    final list = state.value;
    if (list == null) return;
    final preset = list.where((p) => p.id == id).firstOrNull;
    if (preset == null) return;
    final current = ref.read(currentParamsNotifierProvider);
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(preset.params.copyWith(crop: current.crop));
  }

  Future<void> _persist() async {
    final list = await future;
    final userPresets = list.where((p) => !p.isBuiltin).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(userPresets.map((p) => p.toJson()).toList()),
    );
  }

  /// 出厂 preset
  List<Preset> _builtins() => [
    Preset(
      id: 'builtin_neutral',
      name: tr("origin"),
      params: AdjustmentParams.neutral,
      createdAt: DateTime(2024),
      isBuiltin: true,
    ),
  ];
}

final presetNotifierProvider =
    AsyncNotifierProvider<PresetNotifier, List<Preset>>(PresetNotifier.new);

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
