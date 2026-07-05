import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dodge_burn_model.dart';
import '../../state/providers.dart';

/// Dodge/Burn 的交互模式
enum DodgeBurnBrushMode {
  /// 未激活（不处理手势）
  inactive,

  /// 激活（用户可以绘画）
  active,
}

/// Dodge/Burn 的交互状态
@immutable
class DodgeBurnState {
  final DodgeBurnBrushMode brushMode;
  final DodgeBurnMode mode; // dodge or burn
  final DodgeBurnRange range; // shadows / midtones / highlights
  final double exposure; // 0..1
  final double brushRadius; // UI 显示值 (= 归一化值 × 1000)
  final double brushHardness; // 0..1

  const DodgeBurnState({
    this.brushMode = DodgeBurnBrushMode.inactive,
    this.mode = DodgeBurnMode.dodge,
    this.range = DodgeBurnRange.midtones,
    this.exposure = 0.5,
    this.brushRadius = 20.0,
    this.brushHardness = 1.0,
  });

  DodgeBurnState copyWith({
    DodgeBurnBrushMode? brushMode,
    DodgeBurnMode? mode,
    DodgeBurnRange? range,
    double? exposure,
    double? brushRadius,
    double? brushHardness,
  }) {
    return DodgeBurnState(
      brushMode: brushMode ?? this.brushMode,
      mode: mode ?? this.mode,
      range: range ?? this.range,
      exposure: exposure ?? this.exposure,
      brushRadius: brushRadius ?? this.brushRadius,
      brushHardness: brushHardness ?? this.brushHardness,
    );
  }
}

class DodgeBurnNotifier extends Notifier<DodgeBurnState> {
  @override
  DodgeBurnState build() => const DodgeBurnState();

  void setBrushMode(DodgeBurnBrushMode m) =>
      state = state.copyWith(brushMode: m);
  void setMode(DodgeBurnMode m) => state = state.copyWith(mode: m);
  void setRange(DodgeBurnRange r) => state = state.copyWith(range: r);
  void setExposure(double e) => state = state.copyWith(exposure: e);
  void setBrushRadius(double r) => state = state.copyWith(brushRadius: r);
  void setBrushHardness(double h) => state = state.copyWith(brushHardness: h);

  /// 归一化半径（供 shader 和坐标变换使用）
  double get radiusNorm => state.brushRadius / 1000.0;

  /// Add a single mark at tap position.
  /// Freezes current tool settings (mode/range/exposure) into the mark.
  void addMarkAt(Offset target, double radiusNorm, double hardness) {
    final s = state;
    final mark = DodgeBurnMark(
      target: target,
      radius: radiusNorm,
      hardness: hardness,
      mode: s.mode,
      range: s.range,
      exposure: s.exposure,
    );
    _addMarkRaw(mark);
  }

  /// Batch-commit marks from a brush stroke.
  /// Freezes current tool settings (mode/range/exposure) into each mark.
  void addStrokesBatch(
    List<Offset> targets,
    double radiusNorm,
    double hardness,
  ) {
    if (targets.isEmpty) return;
    final s = state;
    final params = ref.read(currentParamsNotifierProvider);
    final updated = List<DodgeBurnMark>.from(params.dodgeBurnMarks);
    for (final t in targets) {
      updated.add(
        DodgeBurnMark(
          target: t,
          radius: radiusNorm,
          hardness: hardness,
          mode: s.mode,
          range: s.range,
          exposure: s.exposure,
        ),
      );
    }
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(dodgeBurnMarks: updated));
  }

  void removeMark(int index) {
    final params = ref.read(currentParamsNotifierProvider);
    final updated = List<DodgeBurnMark>.from(params.dodgeBurnMarks);
    if (index >= 0 && index < updated.length) {
      updated.removeAt(index);
      ref
          .read(currentParamsNotifierProvider.notifier)
          .update(params.copyWith(dodgeBurnMarks: updated));
    }
  }

  void clearAll() {
    final params = ref.read(currentParamsNotifierProvider);
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(dodgeBurnMarks: const []));
  }

  void _addMarkRaw(DodgeBurnMark mark) {
    final params = ref.read(currentParamsNotifierProvider);
    final updated = List<DodgeBurnMark>.from(params.dodgeBurnMarks)..add(mark);
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(dodgeBurnMarks: updated));
  }
}

final dodgeBurnStateProvider =
    NotifierProvider<DodgeBurnNotifier, DodgeBurnState>(DodgeBurnNotifier.new);
