import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../render/thumbnail_renderer.dart';
import '../../utils/debouncer.dart';
import '../providers.dart';
import 'history_entry.dart';

@immutable
class HistoryState {
  final List<AdjustmentParams> undoStack;
  final List<AdjustmentParams> redoStack;

  /// 面板条目，与 undoStack 合并排序展示，供 [HistoryPanelNotifier] 读取
  final List<HistoryEntry> panelEntries;

  /// 每次 panelEntries 发生变化时递增，面板监听此值来同步
  /// 注意：加载已有历史（从 [_filePanelEntries] map）时也递增，跨图切换触发同步
  final int panelVersion;

  const HistoryState({
    this.undoStack = const [],
    this.redoStack = const [],
    this.panelEntries = const [],
    this.panelVersion = 0,
  });

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  HistoryState copyWith({
    List<AdjustmentParams>? undoStack,
    List<AdjustmentParams>? redoStack,
    List<HistoryEntry>? panelEntries,
    int? panelVersion,
  }) => HistoryState(
    undoStack: undoStack ?? this.undoStack,
    redoStack: redoStack ?? this.redoStack,
    panelEntries: panelEntries ?? this.panelEntries,
    panelVersion: panelVersion ?? this.panelVersion,
  );
}

class HistoryNotifier extends Notifier<HistoryState> {
  static const int _maxStack = 50;
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  final _debouncer = Debouncer();

  final Map<String, List<HistoryEntry>> _filePanelEntries = {};

  /// Undo 时从 panel 尾部裁剪的条目，redo 时恢复；新 commit 时清空
  final List<HistoryEntry> _prunedEntries = [];

  late AdjustmentParams _pendingBaseline;
  int _panelCounter = 0;

  @override
  HistoryState build() {
    ref.onDispose(() => _debouncer.dispose());

    _pendingBaseline = ref.read(currentParamsNotifierProvider);

    // 切换文件：清栈 + 保留/丢弃面板条目
    ref.listen<String?>(activeFilePathProvider, (prev, next) {
      if (prev == next) return;
      _debouncer.cancel();

      final preserve = ref.read(preserveHistoryProvider);

      if (preserve && prev != null) {
        _filePanelEntries[prev] = List.of(state.panelEntries);
      }

      final loaded = preserve && next != null
          ? (_filePanelEntries[next] ?? const [])
          : const <HistoryEntry>[];

      // 同步 counter 避免与已有条目 ID 冲突
      _panelCounter = loaded.length;
      _prunedEntries.clear();
      _pendingBaseline = ref.read(currentParamsNotifierProvider);
      state = state.copyWith(
        undoStack: const [],
        redoStack: const [],
        panelEntries: loaded,
        panelVersion: state.panelVersion + 1,
      );
    });

    ref.listen<int>(userEditVersionProvider, (prev, next) {
      if (prev == next) return;
      final params = ref.read(currentParamsNotifierProvider);
      if (_pendingBaseline == params) return;
      _scheduleSnapshot(params);
    });

    return const HistoryState();
  }

  void _scheduleSnapshot(AdjustmentParams next) {
    _debouncer.run(_debounceDelay, () => _commit(next));
  }

  void _commit(AdjustmentParams committed) {
    if (_pendingBaseline == committed) return;

    final baseline = _pendingBaseline;
    final newUndo = [...state.undoStack, baseline];
    if (newUndo.length > _maxStack) {
      newUndo.removeRange(0, newUndo.length - _maxStack);
    }

    // 放弃被裁剪的未来分支
    _prunedEntries.clear();

    final label = _diffLabel(baseline, committed);
    final id =
        'param_${_panelCounter++}_${DateTime.now().millisecondsSinceEpoch}';
    final entry = HistoryEntry(
      id: id,
      label: label,
      params: committed,
      timestamp: DateTime.now(),
    );
    final newEntries = [...state.panelEntries, entry];
    while (newEntries.length > _maxStack) {
      newEntries.removeAt(0);
    }

    state = state.copyWith(
      undoStack: newUndo,
      redoStack: const [],
      panelEntries: newEntries,
      panelVersion: state.panelVersion + 1,
    );
    _pendingBaseline = committed;

    ref
        .read(thumbnailRendererProvider.notifier)
        .requestFull('history', entry.id, entry.params);
  }

  String _diffLabel(AdjustmentParams prev, AdjustmentParams next) {
    final changes = <String>[];
    if (prev.exposure != next.exposure) changes.add('Exposure');
    if (prev.contrast != next.contrast) changes.add('Contrast');
    if (prev.highlights != next.highlights) changes.add('Highlights');
    if (prev.shadows != next.shadows) changes.add('Shadows');
    if (prev.whites != next.whites) changes.add('Whites');
    if (prev.blacks != next.blacks) changes.add('Blacks');
    if (prev.temperature != next.temperature) changes.add('Temperature');
    if (prev.vibrance != next.vibrance) changes.add('Vibrance');
    if (prev.saturation != next.saturation) changes.add('Saturation');
    if (prev.sharpenAmount != next.sharpenAmount) changes.add('Sharpen');
    if (prev.denoiseLuma != next.denoiseLuma ||
        prev.denoiseColor != next.denoiseColor) {
      changes.add('Denoise');
    }
    return changes.isEmpty ? 'Adjustment' : changes.join(', ');
  }

  // ── undo / redo ──

  void undo() {
    if (!state.canUndo) return;
    _debouncer.cancel();

    final newUndo = [...state.undoStack];
    final restored = newUndo.removeLast();
    final current = ref.read(currentParamsNotifierProvider);

    // 裁剪 panel：保持与 undoStack 等长；截掉的部分保存用于 redo
    final targetLen = newUndo.length.clamp(0, state.panelEntries.length);
    final keep = state.panelEntries.sublist(0, targetLen);
    final pruned = state.panelEntries.sublist(targetLen);
    _prunedEntries.insertAll(0, pruned);

    state = state.copyWith(
      undoStack: newUndo,
      redoStack: [...state.redoStack, current],
      panelEntries: keep,
      panelVersion: state.panelVersion + 1,
    );
    _applyInternal(restored);
  }

  void redo() {
    if (!state.canRedo) return;
    _debouncer.cancel();

    final newRedo = [...state.redoStack];
    final restored = newRedo.removeLast();
    final current = ref.read(currentParamsNotifierProvider);

    // 恢复一个 pruned 条目到面板尾部
    final restoredEntry = _prunedEntries.isNotEmpty
        ? _prunedEntries.removeAt(0)
        : null;
    final newEntries = restoredEntry != null
        ? [...state.panelEntries, restoredEntry]
        : state.panelEntries;

    state = state.copyWith(
      undoStack: [...state.undoStack, current],
      redoStack: newRedo,
      panelEntries: newEntries,
      panelVersion: state.panelVersion + 1,
    );
    _applyInternal(restored);
  }

  /// WARNING: [_pendingBaseline] MUST be set BEFORE calling [update()]
  /// on [currentParamsNotifierProvider].
  /// [update()] → `userEditVersion++` → listener fires →
  /// `_pendingBaseline == params` guard skips the re-commit.
  /// Reversing these two lines causes an infinite `_commit` loop.
  void _applyInternal(AdjustmentParams next) {
    _pendingBaseline = next;
    ref.read(currentParamsNotifierProvider.notifier).update(next);
  }

  void applyWithoutHistory(AdjustmentParams params) {
    _debouncer.cancel();
    _applyInternal(params);
  }

  /// 清空当前图片的面板历史（由 [HistoryPanelNotifier.clear] 调用）
  void clearPanel() {
    final current = ref.read(activeFilePathProvider);
    if (current != null) _filePanelEntries.remove(current);
    state = state.copyWith(panelEntries: const [], panelVersion: 0);
  }

  // 笔画结束捕获（外部调用）

  void captureStroke(String label) {
    // 新编辑 → 放弃 undo 裁剪的未来分支
    _prunedEntries.clear();

    final params = ref.read(currentParamsNotifierProvider);
    final id =
        'stroke_${_panelCounter++}_${DateTime.now().millisecondsSinceEpoch}';
    final entry = HistoryEntry(
      id: id,
      label: label,
      params: params,
      timestamp: DateTime.now(),
    );
    final newEntries = [...state.panelEntries, entry];
    while (newEntries.length > _maxStack) {
      newEntries.removeAt(0);
    }
    state = state.copyWith(
      panelEntries: newEntries,
      panelVersion: state.panelVersion + 1,
    );
    ref
        .read(thumbnailRendererProvider.notifier)
        .requestFull('history', entry.id, entry.params);
  }
}

final historyNotifierProvider = NotifierProvider<HistoryNotifier, HistoryState>(
  HistoryNotifier.new,
);
