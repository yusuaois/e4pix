import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/adjustment_params.dart';
import 'image_state.dart';
import 'params_state.dart';

@immutable
class HistoryState {
  final List<AdjustmentParams> undoStack;
  final List<AdjustmentParams> redoStack;

  const HistoryState({
    this.undoStack = const [],
    this.redoStack = const [],
  });

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  HistoryState copyWith({
    List<AdjustmentParams>? undoStack,
    List<AdjustmentParams>? redoStack,
  }) =>
      HistoryState(
        undoStack: undoStack ?? this.undoStack,
        redoStack: redoStack ?? this.redoStack,
      );
}

class HistoryNotifier extends Notifier<HistoryState> {
  static const int _maxStack = 50;
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  Timer? _debounceTimer;

  // 最近一次提交进栈基线 下一次变化时，把这个基线推到 undo
  AdjustmentParams? _pendingBaseline;

  /// 标记当前正在通过 undo/redo/preset 主动应用
  bool _isApplying = false;

  @override
  HistoryState build() {
    // 切换文件清栈
    ref.listen<String?>(activeFilePathProvider, (prev, next) {
      if (prev == next) return;
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _pendingBaseline = null;
      _isApplying = false;
      state = const HistoryState();
    });

    // 参数变化时调度防抖
    ref.listen<AdjustmentParams>(currentParamsNotifierProvider, (prev, next) {
      if (_isApplying) return;
      if (_pendingBaseline == next) return;
      _scheduleSnapshot(next);
    });

    return const HistoryState();
  }

  void _scheduleSnapshot(AdjustmentParams next) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () => _commit(next));
  }

  void _commit(AdjustmentParams committed) {
    // 第一次只记录基线，不入栈
    if (_pendingBaseline == null) {
      _pendingBaseline = committed;
      return;
    }
    if (_pendingBaseline == committed) return;

    final newUndo = [...state.undoStack, _pendingBaseline!];
    if (newUndo.length > _maxStack) {
      newUndo.removeRange(0, newUndo.length - _maxStack);
    }
    state = state.copyWith(undoStack: newUndo, redoStack: const []);
    _pendingBaseline = committed;
  }

  void undo() {
    if (!state.canUndo) return;
    _debounceTimer?.cancel();

    final newUndo = [...state.undoStack];
    final restored = newUndo.removeLast();
    final current = ref.read(currentParamsNotifierProvider);

    state = state.copyWith(
      undoStack: newUndo,
      redoStack: [...state.redoStack, current],
    );
    _applyInternal(restored);
  }

  void redo() {
    if (!state.canRedo) return;
    _debounceTimer?.cancel();

    final newRedo = [...state.redoStack];
    final restored = newRedo.removeLast();
    final current = ref.read(currentParamsNotifierProvider);

    state = state.copyWith(
      undoStack: [...state.undoStack, current],
      redoStack: newRedo,
    );
    _applyInternal(restored);
  }

  /// 手动 reset 到中性值；产生一次撤销点
  void resetToNeutral() {
    final neutral = AdjustmentParams.neutral;
    if (_pendingBaseline == neutral) return;
    // 先把当前推进 undo 栈
    final current = ref.read(currentParamsNotifierProvider);
    if (current != neutral) {
      _debounceTimer?.cancel();
      final newUndo = [...state.undoStack, current];
      if (newUndo.length > _maxStack) {
        newUndo.removeRange(0, newUndo.length - _maxStack);
      }
      state = state.copyWith(undoStack: newUndo, redoStack: const []);
    }
    _applyInternal(neutral);
  }

  /// 套用 AdjustmentParams，不触发历史 push
  void _applyInternal(AdjustmentParams next) {
    _isApplying = true;
    _pendingBaseline = next;
    ref.read(currentParamsNotifierProvider.notifier).update(next);
    //跑完之后释放 flag
    Future.microtask(() {
      _isApplying = false;
    });
  }
}

final historyNotifierProvider =
    NotifierProvider<HistoryNotifier, HistoryState>(HistoryNotifier.new);