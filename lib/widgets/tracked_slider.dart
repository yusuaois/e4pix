import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/interaction_state.dart';

/// 跟系统 Slider 用法完全一样，多做一件事：拖动期间自动更新
/// `isUserDraggingSliderProvider` —— 让 preview / histogram 据此降级渲染
class TrackedSlider extends ConsumerWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;

  const TrackedSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      onChangeStart: (_) =>
          ref.read(isUserDraggingSliderProvider.notifier).state = true,
      onChangeEnd: (_) =>
          ref.read(isUserDraggingSliderProvider.notifier).state = false,
    );
  }
}