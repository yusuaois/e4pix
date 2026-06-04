import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/raw_formats.dart';

enum ImportMode { rawPriority, rawOnly, all }

class ImportModeNotifier extends Notifier<ImportMode> {
  @override
  ImportMode build() {
    _load();
    return ImportMode.rawPriority; // 默认 RAW 优先
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('import_mode');
    if (v != null) {
      state = ImportMode.values.firstWhere(
        (e) => e.name == v,
        orElse: () => ImportMode.rawPriority,
      );
    }
  }

  Future<void> set(ImportMode m) async {
    state = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('import_mode', m.name);
  }
}

final importModeProvider =
    NotifierProvider<ImportModeNotifier, ImportMode>(ImportModeNotifier.new);

/// 按导入模式过滤 + 去重文件列表
List<String> filterByImportMode(List<String> paths, ImportMode mode) {
  switch (mode) {
    case ImportMode.rawOnly:
      return paths.where(RawFormats.isRaw).toList();
    case ImportMode.all:
      return paths.where(RawFormats.isSupported).toList();
    case ImportMode.rawPriority:
      final supported = paths.where(RawFormats.isSupported).toList();
      final rawBases = <String>{};
      for (final pth in supported) {
        if (RawFormats.isRaw(pth)) rawBases.add(RawFormats.baseKey(pth));
      }
      return supported.where((pth) {
        if (RawFormats.isRaw(pth)) return true;
        return !rawBases.contains(RawFormats.baseKey(pth)); // 标准图与RAW同名→丢弃
      }).toList();
  }
}