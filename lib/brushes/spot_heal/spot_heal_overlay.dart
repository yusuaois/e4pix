import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import '../shared/effect/base_effect_overlay.dart';
import 'spot_heal_state.dart';

/// 污点修复覆盖层——IDW 采样填充缺陷，笔画转为密集重叠圆形 marks
class SpotHealOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image sourceImage;

  const SpotHealOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceImage,
  });

  @override
  ConsumerState<SpotHealOverlay> createState() => _SpotHealOverlayState();
}

class _SpotHealOverlayState extends BaseEffectOverlayState<SpotHealOverlay> {
  static const _kCursorColor = Color(0xFFFFFFFF);

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
  double get brushNorm => ref.read(spotHealStateProvider).brushRadius / 1000.0;
  @override
  double get hardness => ref.read(spotHealStateProvider).brushHardness;
  @override
  Color get cursorColor => _kCursorColor;
  @override
  bool get isActive =>
      ref.watch(spotHealStateProvider).mode == SpotHealMode.active;

  // 回调
  @override
  void onAddMarkAt(Offset target, double radius, double hardness) {
    ref
        .read(spotHealStateProvider.notifier)
        .addMarkAt(target, radius, hardness);
  }

  @override
  void onAddStrokesBatch(List<Offset> targets, double radius, double hardness) {
    ref
        .read(spotHealStateProvider.notifier)
        .addStrokesBatch(targets, radius, hardness);
  }
}
