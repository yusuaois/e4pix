import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/stamp/stamp_mark.dart';
import '../../state/params/params_state.dart';
import 'history_brush_model.dart';

/// 历史画笔激活模式
enum HistoryBrushMode { inactive, active }

@immutable
class HistoryBrushState {
  final HistoryBrushMode mode;
  final double brushRadius;
  final double brushHardness;

  const HistoryBrushState({
    this.mode = HistoryBrushMode.inactive,
    this.brushRadius = 0.02,
    this.brushHardness = 1.0,
  });

  HistoryBrushState copyWith({
    HistoryBrushMode? mode,
    double? brushRadius,
    double? brushHardness,
  }) => HistoryBrushState(
    mode: mode ?? this.mode,
    brushRadius: brushRadius ?? this.brushRadius,
    brushHardness: brushHardness ?? this.brushHardness,
  );
}

class HistoryBrushNotifier extends Notifier<HistoryBrushState> {
  @override
  HistoryBrushState build() => const HistoryBrushState();

  void setMode(HistoryBrushMode mode) => state = state.copyWith(mode: mode);

  List<T> _marks<T extends StampMark>() =>
      ref
          .read(currentParamsNotifierProvider)
          .brushMarks['history_brush']
          ?.cast<T>() ??
      const [];

  void _setMarks(List<StampMark> marks) {
    final params = ref.read(currentParamsNotifierProvider);
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(
          params.copyWith(
            brushMarks: {...params.brushMarks, 'history_brush': marks},
          ),
        );
  }

  void setBrushRadius(double radius) {
    state = state.copyWith(brushRadius: radius);
  }

  void setBrushHardness(double hardness) {
    state = state.copyWith(brushHardness: hardness);
  }

  void addMark(Offset target) {
    final updated = <StampMark>[
      ..._marks<HistoryMark>(),
      HistoryMark(
        target: target,
        radius: state.brushRadius,
        hardness: state.brushHardness,
        createdAt: DateTime.now(),
      ),
    ];
    _setMarks(updated);
  }

  void addMarksBatch(List<HistoryMark> marks) {
    if (marks.isEmpty) return;
    final updated = <StampMark>[..._marks<HistoryMark>(), ...marks];
    _setMarks(updated);
  }

  void clearAll() {
    _setMarks(const []);
  }
}

final historyBrushStateProvider =
    NotifierProvider<HistoryBrushNotifier, HistoryBrushState>(
      HistoryBrushNotifier.new,
    );
