import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'healing_model.dart';
import '../../state/params/params_state.dart';

/// 修复画笔交互模式
enum HealingMode {
  /// 非激活状态
  inactive,

  /// 激活状态：点击设置源点，拖拽涂抹
  active,
}

@immutable
class HealingState {
  final HealingMode mode;

  /// 采样源点（归一化源图坐标 [0..1]）
  final ui.Offset? cloneSource;

  /// 笔刷半径（归一化，相对源图宽度）
  final double brushRadius;

  /// 边缘硬度 0..1，1=硬边，0=柔边
  final double brushHardness;

  /// 手机取样按钮开关
  final bool samplingButtonOn;

  const HealingState({
    this.mode = HealingMode.inactive,
    this.cloneSource,
    this.brushRadius = 0.02,
    this.brushHardness = 1.0,
    this.samplingButtonOn = false,
  });

  HealingState copyWith({
    HealingMode? mode,
    ui.Offset? cloneSource,
    bool clearCloneSource = false,
    double? brushRadius,
    double? brushHardness,
    bool? samplingButtonOn,
  }) => HealingState(
    mode: mode ?? this.mode,
    cloneSource: clearCloneSource ? null : (cloneSource ?? this.cloneSource),
    brushRadius: brushRadius ?? this.brushRadius,
    brushHardness: brushHardness ?? this.brushHardness,
    samplingButtonOn: samplingButtonOn ?? this.samplingButtonOn,
  );
}

class HealingNotifier extends StateNotifier<HealingState> {
  final Ref _ref;

  HealingNotifier(this._ref) : super(const HealingState());

  void setMode(HealingMode mode) {
    state = state.copyWith(
      mode: mode,
      clearCloneSource: mode == HealingMode.inactive,
    );
  }

  /// 设置采样源点，自动清除取样按钮标记
  void setCloneSource(ui.Offset source) {
    state = state.copyWith(cloneSource: source, samplingButtonOn: false);
  }

  void clearCloneSource() {
    state = state.copyWith(clearCloneSource: true);
  }

  void toggleSamplingButton() {
    state = state.copyWith(samplingButtonOn: !state.samplingButtonOn);
  }

  void setBrushRadius(double radius) {
    state = state.copyWith(brushRadius: radius);
  }

  void setBrushHardness(double hardness) {
    state = state.copyWith(brushHardness: hardness);
  }

  /// 添加单个修复 mark（从 cloneSource 到 target）
  void addMark(ui.Offset target) {
    final source = state.cloneSource;
    if (source == null) return;
    _addMarkRaw(source, target);
  }

  /// 添加带显式源的修复 mark（拖拽时源随目标同步移动）
  void addMarkWithSource(ui.Offset source, ui.Offset target) {
    _addMarkRaw(source, target);
  }

  void _addMarkRaw(ui.Offset source, ui.Offset target) {
    final params = _ref.read(currentParamsNotifierProvider);
    final updated = List<HealingMark>.from(params.healingMarks)
      ..add(
        HealingMark(
          source: source,
          target: target,
          radius: state.brushRadius,
          hardness: state.brushHardness,
        ),
      );
    _ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(healingMarks: updated));
  }

  /// 批量添加 marks（笔画结束，触发一次管线重渲染）
  void addMarksBatch(List<HealingMark> marks) {
    if (marks.isEmpty) return;
    final params = _ref.read(currentParamsNotifierProvider);
    final updated = List<HealingMark>.from(params.healingMarks)..addAll(marks);
    _ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(healingMarks: updated));
  }

  void removeMark(int index) {
    final params = _ref.read(currentParamsNotifierProvider);
    if (index < 0 || index >= params.healingMarks.length) return;
    final updated = List<HealingMark>.from(params.healingMarks)
      ..removeAt(index);
    _ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(healingMarks: updated));
  }

  void clearAll() {
    final params = _ref.read(currentParamsNotifierProvider);
    _ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(healingMarks: const []));
  }
}

final healingStateProvider =
    StateNotifierProvider<HealingNotifier, HealingState>(
      (ref) => HealingNotifier(ref),
    );
