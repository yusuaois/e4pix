import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'spot_heal_model.dart';
import '../../state/providers.dart';

/// 污点修复的交互模式
enum SpotHealMode {
  /// 未激活（不处理手势）
  inactive,

  /// 激活（用户可以画圈）
  active,
}

/// 污点修复的交互状态
@immutable
class SpotHealState {
  final SpotHealMode mode;
  final double brushRadius;   // UI 显示值 (= 归一化值 × 1000)
  final double brushHardness; // 0..1

  const SpotHealState({
    this.mode = SpotHealMode.inactive,
    this.brushRadius = 20.0,
    this.brushHardness = 1.0,
  });

  SpotHealState copyWith({
    SpotHealMode? mode,
    double? brushRadius,
    double? brushHardness,
  }) {
    return SpotHealState(
      mode: mode ?? this.mode,
      brushRadius: brushRadius ?? this.brushRadius,
      brushHardness: brushHardness ?? this.brushHardness,
    );
  }
}

class SpotHealNotifier extends Notifier<SpotHealState> {
  @override
  SpotHealState build() => const SpotHealState();

  void setMode(SpotHealMode mode) => state = state.copyWith(mode: mode);
  void setBrushRadius(double r) => state = state.copyWith(brushRadius: r);
  void setBrushHardness(double h) => state = state.copyWith(brushHardness: h);

  /// 归一化半径（供 shader 和坐标变换使用）
  double get radiusNorm => state.brushRadius / 1000.0;

  /// Add a single mark with explicit radius and hardness (free-form brush).
  void addMarkAt(Offset target, double radiusNorm, double hardness) {
    final mark = SpotHealMark(target: target, radius: radiusNorm, hardness: hardness);
    _addMarkRaw(mark);
  }

  /// Batch-commit marks from a free-form brush stroke.
  void addStrokesBatch(List<Offset> targets, double radiusNorm, double hardness) {
    if (targets.isEmpty) return;
    final params = ref.read(currentParamsNotifierProvider);
    final updated = List<SpotHealMark>.from(params.spotHealMarks);
    for (final t in targets) {
      updated.add(SpotHealMark(target: t, radius: radiusNorm, hardness: hardness));
    }
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(spotHealMarks: updated));
  }

  void removeMark(int index) {
    final params = ref.read(currentParamsNotifierProvider);
    final updated = List<SpotHealMark>.from(params.spotHealMarks);
    if (index >= 0 && index < updated.length) {
      updated.removeAt(index);
      ref
          .read(currentParamsNotifierProvider.notifier)
          .update(params.copyWith(spotHealMarks: updated));
    }
  }

  void clearAll() {
    final params = ref.read(currentParamsNotifierProvider);
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(spotHealMarks: const []));
  }

  void _addMarkRaw(SpotHealMark mark) {
    final params = ref.read(currentParamsNotifierProvider);
    final updated = List<SpotHealMark>.from(params.spotHealMarks)..add(mark);
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(spotHealMarks: updated));
  }
}

final spotHealStateProvider =
    NotifierProvider<SpotHealNotifier, SpotHealState>(SpotHealNotifier.new);
