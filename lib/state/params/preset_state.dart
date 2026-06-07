import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/crop_params.dart';
import '../../services/export/xmp_export.dart';
import '../../services/export/xmp_import.dart';
import '../providers.dart';

@immutable
class Preset {
  final String id;
  final String name;
  final AdjustmentParams params;
  final bool isBuiltin;

  const Preset({
    required this.id,
    required this.name,
    required this.params,
    this.isBuiltin = false,
  });
}

class PresetNotifier extends AsyncNotifier<List<Preset>> {
  String? _dir;
  static const _spKey = 'e4pix_deleted_presets';

  Future<String> get _presetsDir async {
    if (_dir != null) return _dir!;
    final appDir = await getApplicationDocumentsDirectory();
    _dir = p.join(appDir.path, 'presets');
    await Directory(_dir!).create(recursive: true);
    return _dir!;
  }

  @override
  Future<List<Preset>> build() async {
    final dir = await _presetsDir;
    // 首次启动将 assets/presets/*.xmp 释放到用户目录
    await _releaseBuiltins(dir);
    return [
      Preset(
        id: 'origin',
        name: tr("origin"),
        params: AdjustmentParams.neutral,
        isBuiltin: true,
      ),
      ...await _loadFromDir(dir),
    ];
  }

  /// 首次启动时将 assets/presets/*.xmp 释放到用户目录（跳过用户已删除的）
  Future<void> _releaseBuiltins(String dir) async {
    final deleted = await _loadDeleted();
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final key in manifest.listAssets()) {
        if (!key.startsWith('assets/presets/') || !key.endsWith('.xmp')) {
          continue;
        }
        final name = p.basenameWithoutExtension(key);
        if (deleted.contains(name)) continue;
        final dest = p.join(dir, '$name.xmp');
        if (await File(dest).exists()) continue;
        try {
          final xmp = await rootBundle.loadString(key);
          await File(dest).writeAsString(xmp);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 从用户目录加载 .xmp
  Future<List<Preset>> _loadFromDir(String dir) async {
    final presets = <Preset>[];
    final entries = Directory(dir).listSync().whereType<File>();
    for (final file in entries) {
      if (!file.path.endsWith('.xmp')) continue;
      try {
        final id = p.basenameWithoutExtension(file.path);
        final content = await file.readAsString();
        final (params, _) = XmpImport.parse(content, AdjustmentParams.neutral);
        presets.add(Preset(id: id, name: id, params: params));
      } catch (_) {}
    }
    presets.sort((a, b) => a.id.compareTo(b.id));
    return presets;
  }

  // ── 操作 ──

  Future<void> saveCurrentAs(String name) async {
    final dir = await _presetsDir;
    final current = ref.read(currentParamsNotifierProvider);
    final clean = current.copyWith(crop: CropParams.identity, locals: const []);
    final xmp = XmpExport.serialize(clean);
    await File(p.join(dir, '$name.xmp')).writeAsString(xmp);
    final list = await future;
    state = AsyncData([...list, Preset(id: name, name: name, params: clean)]);
  }

  Future<void> rename(String oldId, String newName) async {
    if (oldId == 'origin') return;
    final dir = await _presetsDir;
    await File(p.join(dir, '$oldId.xmp')).rename(p.join(dir, '$newName.xmp'));
    final list = await future;
    state = AsyncData([
      for (final p in list)
        if (p.id == oldId)
          Preset(id: newName, name: newName, params: p.params)
        else
          p,
    ]);
  }

  Future<void> delete(String id) async {
    if (id == 'origin') return;
    final dir = await _presetsDir;
    try {
      await File(p.join(dir, '$id.xmp')).delete();
    } catch (_) {}
    await _addDeleted(id);
    final list = await future;
    state = AsyncData(list.where((p) => p.id != id).toList());
  }

  Future<Set<String>> _loadDeleted() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_spKey);
    if (raw == null) return {};
    try {
      return Set<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return {};
    }
  }

  Future<void> _addDeleted(String id) async {
    final set = await _loadDeleted();
    set.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_spKey, jsonEncode(set.toList()));
  }

  void apply(String id) {
    final list = state.value;
    if (list == null) return;
    final preset = list.where((p) => p.id == id).firstOrNull;
    if (preset == null) return;
    final current = ref.read(currentParamsNotifierProvider);
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(
          preset.params.copyWith(crop: current.crop, locals: current.locals),
        );
  }
}

final presetNotifierProvider =
    AsyncNotifierProvider<PresetNotifier, List<Preset>>(PresetNotifier.new);

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
