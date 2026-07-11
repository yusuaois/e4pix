import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import '../../state/providers.dart';
import 'sponge_model.dart';
import '../shared/effect/base_effect_overlay.dart';

/// 海绵工具覆盖层——自由绘制饱和/去饱和
class SpongeOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image sourceImage;

  const SpongeOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceImage,
  });

  @override
  ConsumerState<SpongeOverlay> createState() => _SpongeOverlayState();
}

class _SpongeOverlayState extends BaseEffectOverlayState<SpongeOverlay> {
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
  double get brushNorm => ref.read(spongeStateProvider).brushRadius / 1000.0;
  @override
  double get hardness => ref.read(spongeStateProvider).brushHardness;
  @override
  Color get cursorColor {
    return ref.watch(spongeStateProvider).mode == SpongeMode.saturate
        ? const Color(0x8066DD66) // warm green for saturate
        : const Color(0x80AAAAAA); // cool grey for desaturate
  }

  @override
  bool get isActive =>
      ref.watch(spongeStateProvider).brushMode == SpongeBrushMode.active;

  // 回调
  @override
  void onAddMarkAt(Offset target, double radius, double hardness) {
    ref.read(spongeStateProvider.notifier).addMarkAt(target, radius, hardness);
  }

  @override
  void onAddStrokesBatch(List<Offset> targets, double radius, double hardness) {
    ref
        .read(spongeStateProvider.notifier)
        .addStrokesBatch(targets, radius, hardness);
  }
}
