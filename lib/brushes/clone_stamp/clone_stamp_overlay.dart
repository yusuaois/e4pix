import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import 'clone_stamp_model.dart';
import 'clone_stamp_state.dart';
import '../shared/brush_hashes.dart';
import '../shared/stamp/base_stamp_painter.dart';
import '../shared/stamp/base_stamp_overlay.dart';
import '../../state/providers.dart';

/// 图章交互覆盖层
///
/// 点击或拖拽绘制图章 marks，源点通过取样按钮设置
/// 拖拽期间在 Canvas 上绘制硬边预览，松手后提交管线做柔边混合
class SpotRemoveOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image? sourceImage;

  const SpotRemoveOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    this.sourceImage,
  });

  @override
  ConsumerState<SpotRemoveOverlay> createState() => _SpotRemoveOverlayState();
}

class _SpotRemoveOverlayState
    extends BaseStampOverlayState<SpotMark, SpotRemoveOverlay> {
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

  @override
  void didUpdateWidget(SpotRemoveOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sourceImage != oldWidget.sourceImage) {
      compositor.disposeComposited();
      compositor.compositedCount = 0;
    }
  }

  @override
  void onInitState() {
    super.onInitState();
    final persisted = ref.read(persistedStampProvider);
    if (persisted.isCommitting &&
        persisted.brushId == 'spot_removal' &&
        persisted.marks.isNotEmpty) {
      gestureHandler.committedMarks.addAll(persisted.marks.cast<SpotMark>());
      gestureHandler.committedHash = persisted.hash;
      gestureHandler.isCommitting = true;
      ref.read(persistedStampProvider.notifier).clear();
    }
  }

  // Brush 配置
  @override
  String get shaderKey => 'spot_removal';
  @override
  String get logTag => '[SpotOverlay]';
  @override
  String get renderedHashKey => 'spot_removal';

  @override
  SpotMark createMark({
    required Offset source,
    required Offset target,
    required double radius,
    required double hardness,
    required DateTime createdAt,
  }) => SpotMark(
    source: source,
    target: target,
    radius: radius,
    hardness: hardness,
    createdAt: createdAt,
  );

  @override
  void commitMarksToPipeline(WidgetRef ref, List<SpotMark> marks) {
    ref.read(spotRemoveStateProvider.notifier).addSpotsBatch(marks);
  }

  @override
  int computeCommittedHash(WidgetRef ref) => hashSpots(
    (ref
            .read(currentParamsNotifierProvider)
            .brushMarks['spot_removal']
            ?.cast<SpotMark>()) ??
        const [],
  );

  @override
  void addSingleMark(WidgetRef ref, Offset target) {
    ref.read(spotRemoveStateProvider.notifier).addSpot(target);
  }

  @override
  void updateCloneSource(WidgetRef ref, Offset source) {
    ref.read(spotRemoveStateProvider.notifier).setCloneSource(source);
  }

  @override
  double getBrushRadius(WidgetRef ref) =>
      ref.read(spotRemoveStateProvider).brushRadius;

  @override
  double getBrushHardness(WidgetRef ref) =>
      ref.read(spotRemoveStateProvider).brushHardness;

  @override
  Offset? getCloneSource(WidgetRef ref) =>
      ref.read(spotRemoveStateProvider).cloneSource;

  @override
  bool getIsSampling(WidgetRef ref) =>
      ref.read(spotRemoveStateProvider).samplingButtonOn;

  // build
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spotRemoveStateProvider);
    final isSampling = state.samplingButtonOn;

    listenRenderedHashes();

    ref.listen(currentParamsNotifierProvider, (prev, next) {
      if ((prev?.brushMarks['spot_removal']?.isNotEmpty ?? false) &&
          (next.brushMarks['spot_removal']?.isEmpty ?? true)) {
        handleMarksCleared();
      }
    });

    final painter = CustomPaint(
      size: widget.imageDisplaySize,
      painter: _SpotPainter(
        cloneSource: state.cloneSource,
        brushRadius: state.brushRadius,
        brushHardness: state.brushHardness,
        imageDisplaySize: widget.imageDisplaySize,
        crop: widget.crop,
        sourceWidth: widget.sourceWidth,
        sourceHeight: widget.sourceHeight,
        cursorPos: cursorPos,
        cursorSrc: cursorSrc,
        isSampling: isSampling,
        paintOffset: gestureHandler.paintOffset,
        isPainting: gestureHandler.strokeTracker != null,
        sourceImage: widget.sourceImage,
        compositedImage: compositor.compositedImage,
        compositedCount: compositor.compositedCount,
        strokeMarks: gestureHandler.strokeMarks,
        committedMarks: gestureHandler.committedMarks,
      ),
    );

    return buildInteractionWrapper(painter: painter, ref: ref);
  }
}

class _SpotPainter extends BaseStampPainter<SpotMark> {
  _SpotPainter({
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
