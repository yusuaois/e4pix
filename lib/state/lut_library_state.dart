import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/lut_formats.dart';
import '../services/lut_library.dart';

class LutLibraryNotifier extends AsyncNotifier<List<LutEntry>> {
  @override
  Future<List<LutEntry>> build() => LutLibrary.listAll();

  /// 弹文件选择对话框，把选中的 .cube 复制到 app 私有目录
  /// 成功返回新条目，失败返回 null
  Future<LutEntry?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final src = result?.files.firstOrNull?.path;
    if (src == null) return null;

    if (!LutFormats.isLut(src)) {
      debugPrint('选中的文件不是 .cube / .vlt 格式');
      return null;
    }

    try {
      final entry = await LutLibrary.importFrom(src);
      final current = await future;
      final next = [...current, entry]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      state = AsyncData(next);
      return entry;
    } catch (e) {
      debugPrint('Import LUT failed: $e');
      return null;
    }
  }

  Future<void> delete(LutEntry entry) async {
    try {
      await LutLibrary.delete(entry);
      final current = await future;
      state = AsyncData(
        current.where((e) => e.filePath != entry.filePath).toList(),
      );
    } catch (e) {
      debugPrint('Delete LUT failed: $e');
    }
  }
}

final lutLibraryNotifierProvider =
    AsyncNotifierProvider<LutLibraryNotifier, List<LutEntry>>(
      LutLibraryNotifier.new,
    );
