import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import 'healing_model.dart';
import 'healing_state.dart';
import '../shared/brush_hashes.dart';
import '../shared/stamp/base_stamp_painter.dart';
import '../shared/stamp/base_stamp_overlay.dart';
import '../../state/providers.dart';

/// 修复画笔交互覆盖层
///
/// 交互方式与 [SpotRemoveOverlay] 相同：点击或拖拽绘制修复 marks
/// 区别在于 shader 用频域分离混合而非直接像素复制
///
/// 拖拽期间在 Canvas 上绘制硬边预览，松手后提交管线做柔边混合
class HealingOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image? sourceImage;

  /// 为 false 时不处理手势和光标，但仍绘制已提交预览并监听管线完成
  final bool interactive;

  const HealingOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    this.sourceImage,
    this.interactive = true,
  });

  @override
  ConsumerState<HealingOverlay> createState() => HealingOverlayState();
}

class HealingOverlayState
    extends BaseStampOverlayState<HealingMark, HealingOverlay> {
  // Widget 参数

  @override
  Size get imageDisplaySize => widget.imageDisplaySize;
  @override
  CropParams get crop => widget.crop;
  @override
  int get sourceWidth => widget.sourceWidth;
  @override
  int get sourceHeight => widget.sourceHeight;
  @override
  ui.Image? get sourceImage => widget.sourceImage;

  // 可选覆写

  @override
  bool get interactive => widget.interactive;

  @override
  void onInitState() {
    super.onInitState();
    final persisted = ref.read(persistedStampProvider);
    if (persisted.isCommitting &&
        persisted.brushId == 'healing' &&
        persisted.marks.isNotEmpty) {
      gestureHandler.committedMarks.addAll(persisted.marks.cast<HealingMark>());
      gestureHandler.committedHash = persisted.hash;
      gestureHandler.isCommitting = true;
      ref.read(persistedStampProvider.notifier).clear();
    }
  }

  @override
  void didUpdateWidget(HealingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sourceImage != oldWidget.sourceImage) {
      compositor.disposeComposited();
      compositor.compositedCount = 0;
    }
    if (oldWidget.interactive && !widget.interactive) {
      gestureHandler.paintOffset = null;
      gestureHandler.strokeTracker = null;
      gestureHandler.strokeMarks.clear();
    }
  }

  // Brush 配置

  @override
  String get shaderKey => 'healing';
  @override
  String get logTag => '[HealingOverlay]';
  @override
  String get renderedHashKey => 'healing';

  @override
  HealingMark createMark({
    required Offset source,
    required Offset target,
    required double radius,
    required double hardness,
    required DateTime createdAt,
  }) => HealingMark(
    source: source,
    target: target,
    radius: radius,
    hardness: hardness,
    createdAt: createdAt,
  );

  @override
  void commitMarksToPipeline(WidgetRef ref, List<HealingMark> marks) {
    ref.read(healingStateProvider.notifier).addMarksBatch(marks);
  }

  @override
  int computeCommittedHash(WidgetRef ref) => hashHealingMarks(
    (ref
            .read(currentParamsNotifierProvider)
            .brushMarks['healing']
            ?.cast<HealingMark>()) ??
        const [],
  );

  @override
  void addSingleMark(WidgetRef ref, Offset target) {
    ref.read(healingStateProvider.notifier).addMark(target);
  }

  @override
  void updateCloneSource(WidgetRef ref, Offset source) {
    ref.read(healingStateProvider.notifier).setCloneSource(source);
  }

  @override
  double getBrushRadius(WidgetRef ref) =>
      ref.read(healingStateProvider).brushRadius;

  @override
  double getBrushHardness(WidgetRef ref) =>
      ref.read(healingStateProvider).brushHardness;

  @override
  Offset? getCloneSource(WidgetRef ref) =>
      ref.read(healingStateProvider).cloneSource;

  @override
  bool getIsSampling(WidgetRef ref) =>
      ref.read(healingStateProvider).samplingButtonOn;

  // build

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(healingStateProvider);
    final isSampling = state.samplingButtonOn;

    listenRenderedHashes();

    ref.listen(currentParamsNotifierProvider, (prev, next) {
      if ((prev?.brushMarks['healing']?.isNotEmpty ?? false) &&
          (next.brushMarks['healing']?.isEmpty ?? true)) {
        handleMarksCleared();
      }
    });

    final painter = CustomPaint(
      size: widget.imageDisplaySize,
      painter: _HealingPainter(
        cloneSource: state.cloneSource,
        brushRadius: state.brushRadius,
        brushHardness: state.brushHardness,
        imageDisplaySize: widget.imageDisplaySize,
        crop: widget.crop,
        sourceWidth: widget.sourceWidth,
        sourceHeight: widget.sourceHeight,
        cursorPos: interactive ? cursorPos : null,
        cursorSrc: interactive ? cursorSrc : null,
        isSampling: interactive && isSampling,
        paintOffset: interactive ? gestureHandler.paintOffset : null,
        isPainting: interactive && gestureHandler.strokeTracker != null,
        sourceImage: widget.sourceImage,
        compositedImage: compositor.compositedImage,
        compositedCount: compositor.compositedCount,
        strokeMarks: gestureHandler.strokeMarks,
        committedMarks: gestureHandler.committedMarks,
      ),
    );

    return buildInteractionWrapper(
      painter: painter,
      ref: ref,
      interactiveOverride: interactive,
    );
  }
}

class _HealingPainter extends BaseStampPainter<HealingMark> {
  _HealingPainter({
    required super.cloneSource,
    required super.brushRadius,
    required super.brushHardness,
    required super.imageDisplaySize,
    required super.crop,
    required super.sourceWidth,
    required super.sourceHeight,
    required super.cursorPos,
    required super.cursorSrc,
    required super.isSampling,
    super.paintOffset,
    super.isPainting = false,
    super.sourceImage,
    super.compositedImage,
    super.compositedCount = 0,
    super.strokeMarks = const [],
    super.committedMarks = const [],
  });
}
