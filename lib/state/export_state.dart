import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/models/adjustment_params.dart';
import 'image_state.dart';
import 'params_state.dart';
import 'tether_state.dart';

@immutable
class ExportSelection {
  final bool multiSelectMode;
  final Set<String> selectedPaths;

  const ExportSelection({
    this.multiSelectMode = false,
    this.selectedPaths = const {},
  });

  ExportSelection copyWith({bool? multiSelectMode, Set<String>? selectedPaths}) =>
      ExportSelection(
        multiSelectMode: multiSelectMode ?? this.multiSelectMode,
        selectedPaths: selectedPaths ?? this.selectedPaths,
      );
}

class ExportSelectionNotifier extends Notifier<ExportSelection> {
  @override
  ExportSelection build() => const ExportSelection();

  void toggleMode() {
    if (state.multiSelectMode) {
      state = const ExportSelection(); // 退出清空
    } else {
      state = state.copyWith(multiSelectMode: true);
    }
  }

  void toggleShot(String path) {
    final set = Set<String>.from(state.selectedPaths);
    if (set.contains(path)) {
      set.remove(path);
    } else {
      set.add(path);
    }
    state = state.copyWith(selectedPaths: set);
  }

  void selectAll(Iterable<String> paths) {
    state = state.copyWith(selectedPaths: paths.toSet());
  }

  void clearSelection() {
    state = state.copyWith(selectedPaths: const {});
  }
}

final exportSelectionNotifierProvider =
    NotifierProvider<ExportSelectionNotifier, ExportSelection>(
  ExportSelectionNotifier.new,
);

// 导出任务
@immutable
class ExportTask {
  final String path;
  final AdjustmentParams params;
  final String filename;
  const ExportTask({required this.path, required this.params, required this.filename});
}

final exportTasksProvider = Provider<List<ExportTask>>((ref) {
  final selection = ref.watch(exportSelectionNotifierProvider);
  final shots = ref.watch(shotsNotifierProvider);

  if (selection.multiSelectMode && selection.selectedPaths.isNotEmpty) {
    return [
      for (final s in shots)
        if (selection.selectedPaths.contains(s.path))
          ExportTask(path: s.path, params: s.params, filename: s.filename),
    ];
  }

  // 单张
  final path = ref.watch(activeFilePathProvider);
  if (path == null) return const [];
  final params = ref.watch(currentParamsNotifierProvider);
  return [
    ExportTask(path: path, params: params, filename: p.basename(path)),
  ];
});