import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import 'dodge_burn_model.dart';
import '../shared/effect/base_effect_overlay.dart';
import 'dodge_burn_state.dart';

/// 加深减淡覆盖层——Screen/Multiply 混合 + 三色调范围
class DodgeBurnOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image sourceImage;

  const DodgeBurnOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceImage,
  });

  @override
  ConsumerState<DodgeBurnOverlay> createState() => _DodgeBurnOverlayState();
}

class _DodgeBurnOverlayState extends BaseEffectOverlayState<DodgeBurnOverlay> {
  // Widget 属性
  @override
  Size get imageDisplaySize => widget.imageDisplaySize;
  @override
  CropParams get crop => widget.crop;
  @override
  int get sourceWidth => widget.sourceWidth;
  @override
  int get sourceHeight => widget.sourceHeight;

  // 画笔配置
  @override
  double get brushNorm => ref.read(dodgeBurnStateProvider).brushRadius / 1000.0;
  @override
  double get hardness => ref.read(dodgeBurnStateProvider).brushHardness;
  @override
  Color get cursorColor {
    return ref.watch(dodgeBurnStateProvider).mode == DodgeBurnMode.dodge
        ? const Color(0x80FFCC00) // warm gold for dodge
        : const Color(0x800088FF); // cool blue for burn
  }

  @override
  bool get isActive =>
      ref.watch(dodgeBurnStateProvider).brushMode == DodgeBurnBrushMode.active;

  // 回调
  @override
  void onAddMarkAt(Offset target, double radius, double hardness) {
    ref
        .read(dodgeBurnStateProvider.notifier)
        .addMarkAt(target, radius, hardness);
  }

  @override
  void onAddStrokesBatch(List<Offset> targets, double radius, double hardness) {
    ref
        .read(dodgeBurnStateProvider.notifier)
        .addStrokesBatch(targets, radius, hardness);
  }
}
