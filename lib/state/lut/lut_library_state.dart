import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/lut_formats.dart';
import '../../services/lut/lut_library.dart';

class LutLibraryNotifier extends AsyncNotifier<List<LutEntry>> {
  @override
  Future<List<LutEntry>> build() => LutLibrary.listAll();

  /// 弹文件选择对话框，支持多选 .cube 文件导入
  /// 返回成功导入的条目列表
  Future<List<LutEntry>> importFromFiles() async {
    final result = await FilePicker.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return const [];

    final imported = <LutEntry>[];
    for (final file in result.files) {
      final src = file.path;
      if (src == null || !LutFormats.isLut(src)) continue;
      try {
        final entry = await LutLibrary.importFrom(src);
        imported.add(entry);
      } catch (_) {}
    }

    if (imported.isEmpty) return const [];

    final current = await future;
    final next = [...current, ...imported]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = AsyncData(next);
    return imported;
  }

  Future<void> delete(LutEntry entry) async {
    try {
      await LutLibrary.delete(entry);
      final current = await future;
      state = AsyncData(
        current.where((e) => e.filePath != entry.filePath).toList(),
      );
    } finally {}
  }
}

final lutLibraryNotifierProvider =
    AsyncNotifierProvider<LutLibraryNotifier, List<LutEntry>>(
      LutLibraryNotifier.new,
    );
