import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/stamp/stamp_mark.dart';
import 'sponge_model.dart';
import '../../state/providers.dart';

/// 海绵工具的交互模式
enum SpongeBrushMode {
  /// 未激活（不处理手势）
  inactive,

  /// 激活（用户可以绘画）
  active,
}

/// 海绵工具的交互状态
@immutable
class SpongeState {
  final SpongeBrushMode brushMode;
  final SpongeMode mode;
  final double flow; // 0..1
  final double brushRadius; // UI 显示值（= 归一化值 × 1000）
  final double brushHardness; // 0..1

  const SpongeState({
    this.brushMode = SpongeBrushMode.inactive,
    this.mode = SpongeMode.saturate,
    this.flow = 0.5,
    this.brushRadius = 20.0,
    this.brushHardness = 1.0,
  });

  SpongeState copyWith({
    SpongeBrushMode? brushMode,
    SpongeMode? mode,
    double? flow,
    double? brushRadius,
    double? brushHardness,
  }) {
    return SpongeState(
      brushMode: brushMode ?? this.brushMode,
      mode: mode ?? this.mode,
      flow: flow ?? this.flow,
      brushRadius: brushRadius ?? this.brushRadius,
      brushHardness: brushHardness ?? this.brushHardness,
    );
  }
}

class SpongeNotifier extends Notifier<SpongeState> {
  @override
  SpongeState build() => const SpongeState();

  List<T> _marks<T extends StampMark>() =>
      ref.read(currentParamsNotifierProvider).brushMarks['sponge']?.cast<T>() ??
      const [];

  void _setMarks(List<StampMark> marks) {
    final params = ref.read(currentParamsNotifierProvider);
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(
          params.copyWith(brushMarks: {...params.brushMarks, 'sponge': marks}),
        );
  }

  void setBrushMode(SpongeBrushMode m) => state = state.copyWith(brushMode: m);
  void setMode(SpongeMode m) => state = state.copyWith(mode: m);
  void setFlow(double f) => state = state.copyWith(flow: f);
  void setBrushRadius(double r) => state = state.copyWith(brushRadius: r);
  void setBrushHardness(double h) => state = state.copyWith(brushHardness: h);

  /// 归一化半径（供 shader 和坐标变换使用）
  double get radiusNorm => state.brushRadius / 1000.0;

  /// Add a single mark at tap position.
  /// Freezes current tool settings (mode/flow) into the mark.
  void addMarkAt(Offset target, double radiusNorm, double hardness) {
    final s = state;
    final mark = SpongeMark(
      target: target,
      radius: radiusNorm,
      hardness: hardness,
      mode: s.mode,
      flow: s.flow,
    );
    _addMarkRaw(mark);
  }

  /// Batch-commit marks from a brush stroke.
  /// Freezes current tool settings (mode/flow) into each mark.
  void addStrokesBatch(
    List<Offset> targets,
    double radiusNorm,
    double hardness,
  ) {
    if (targets.isEmpty) return;
    final s = state;
    final updated = <StampMark>[..._marks<SpongeMark>()];
    for (final t in targets) {
      updated.add(
        SpongeMark(
          target: t,
          radius: radiusNorm,
          hardness: hardness,
          mode: s.mode,
          flow: s.flow,
        ),
      );
    }
    _setMarks(updated);
  }

  void removeMark(int index) {
    final marks = _marks<SpongeMark>();
    if (index >= 0 && index < marks.length) {
      final updated = <StampMark>[...marks]..removeAt(index);
      _setMarks(updated);
    }
  }

  void clearAll() {
    _setMarks(const []);
  }

  void _addMarkRaw(SpongeMark mark) {
    final updated = <StampMark>[..._marks<SpongeMark>(), mark];
    _setMarks(updated);
  }
}

final spongeStateProvider = NotifierProvider<SpongeNotifier, SpongeState>(
  SpongeNotifier.new,
);
