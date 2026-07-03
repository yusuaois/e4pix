import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/models/healing_mark.dart';
import '../params/params_state.dart';

/// Healing brush interaction mode.
enum HealingMode {
  /// Not active.
  inactive,

  /// Active: tap to set source, click/drag to paint.
  active,
}

@immutable
class HealingState {
  final HealingMode mode;

  /// Sample source point (normalized source-image coords [0..1]).
  final ui.Offset? cloneSource;

  /// Brush radius (normalized, relative to source image width).
  final double brushRadius;

  /// Edge hardness 0..1, 1 = hard edge, 0 = soft edge.
  final double brushHardness;

  /// Mobile sampling button toggle.
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

  /// Toggle activation mode.
  void setMode(HealingMode mode) {
    state = state.copyWith(
      mode: mode,
      clearCloneSource: mode == HealingMode.inactive,
    );
  }

  /// Set the sample source point.
  ///
  /// After setting, auto-clears the sampling button flag so the next
  /// tap goes to painting rather than setting the source again.
  void setCloneSource(ui.Offset source) {
    state = state.copyWith(cloneSource: source, samplingButtonOn: false);
  }

  /// Clear the sample source point.
  void clearCloneSource() {
    state = state.copyWith(clearCloneSource: true);
  }

  /// Toggle the mobile sampling button.
  void toggleSamplingButton() {
    state = state.copyWith(samplingButtonOn: !state.samplingButtonOn);
  }

  /// Set brush radius.
  void setBrushRadius(double radius) {
    state = state.copyWith(brushRadius: radius);
  }

  /// Set edge hardness.
  void setBrushHardness(double hardness) {
    state = state.copyWith(brushHardness: hardness);
  }

  /// Add a single healing mark (from cloneSource to target).
  void addMark(ui.Offset target) {
    final source = state.cloneSource;
    if (source == null) return;
    _addMarkRaw(source, target);
  }

  /// Add a healing mark with an explicit source (for drag strokes where
  /// the source moves with the target).
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

  /// Batch-add marks (stroke end — triggers one pipeline re-render).
  void addMarksBatch(List<HealingMark> marks) {
    if (marks.isEmpty) return;
    final params = _ref.read(currentParamsNotifierProvider);
    final updated = List<HealingMark>.from(params.healingMarks)..addAll(marks);
    _ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(healingMarks: updated));
  }

  /// Remove a mark by index.
  void removeMark(int index) {
    final params = _ref.read(currentParamsNotifierProvider);
    if (index < 0 || index >= params.healingMarks.length) return;
    final updated = List<HealingMark>.from(params.healingMarks)
      ..removeAt(index);
    _ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(healingMarks: updated));
  }

  /// Clear all healing marks.
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
