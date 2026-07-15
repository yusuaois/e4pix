import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import '../../state/providers.dart';
import '../shared/stamp/base_stamp_overlay.dart';
import '../shared/stamp/base_stamp_painter.dart';
import '../shared/brush_hashes.dart';
import 'history_brush_model.dart';
import 'history_brush_state.dart';

/// 历史记录画笔——从冻结快照恢复像素，通过按钮激活
class HistoryBrushOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image? sourceImage;

  const HistoryBrushOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    this.sourceImage,
  });

  @override
  ConsumerState<HistoryBrushOverlay> createState() =>
      _HistoryBrushOverlayState();
}

class _HistoryBrushOverlayState
    extends BaseStampOverlayState<HistoryMark, HistoryBrushOverlay> {
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
  void didUpdateWidget(HistoryBrushOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sourceImage != oldWidget.sourceImage) {
      compositor.disposeComposited();
      compositor.compositedCount = 0;
    }
  }

  // ── Brush 配置 ──

  @override
  String get shaderKey => 'history_brush';
  @override
  String get logTag => '[HistoryBrush]';
  @override
  String get renderedHashKey => 'history_brush';

  @override
  HistoryMark createMark({
    required Offset source,
    required Offset target,
    required double radius,
    required double hardness,
    required DateTime createdAt,
  }) => HistoryMark(
    target: target,
    radius: radius,
    hardness: hardness,
    createdAt: createdAt,
  );

  @override
  void commitMarksToPipeline(WidgetRef ref, List<HistoryMark> marks) {
    ref.read(historyBrushStateProvider.notifier).addMarksBatch(marks);
  }

  @override
  int computeCommittedHash(WidgetRef ref) => hashHistoryMarks(
    (ref
            .read(currentParamsNotifierProvider)
            .brushMarks['history_brush']
            ?.cast<HistoryMark>()) ??
        const [],
  );

  @override
  void addSingleMark(WidgetRef ref, Offset target, {required double radius}) {
    ref
        .read(historyBrushStateProvider.notifier)
        .addMark(target, radiusOverride: radius);
  }

  @override
  void updateCloneSource(WidgetRef ref, Offset source) {
    // History Brush 不需要 clone source——no-op
  }

  @override
  double getBrushRadius(WidgetRef ref) =>
      ref.read(historyBrushStateProvider).brushRadius;

  @override
  double getBrushHardness(WidgetRef ref) =>
      ref.read(historyBrushStateProvider).brushHardness;

  /// 返回 Offset.zero 而非 null，允许 onPanStart 进入绘画流程
  /// HistoryMark.createMark 忽略 source 参数（始终 source == target）
  @override
  Offset? getCloneSource(WidgetRef ref) => Offset.zero;

  @override
  bool getIsSampling(WidgetRef ref) => false;

  // ── History snapshot ──

  @override
  void onInitState() {
    super.onInitState();
    // 设置 history snapshot 源到 compositor
    compositor.getHistorySourceImage = () => historyBrushSnapshot.value;
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    listenRenderedHashes();

    ref.listen(currentParamsNotifierProvider, (prev, next) {
      if ((prev?.brushMarks['history_brush']?.isNotEmpty ?? false) &&
          (next.brushMarks['history_brush']?.isEmpty ?? true)) {
        handleMarksCleared();
      }
    });

    final painter = CustomPaint(
      size: widget.imageDisplaySize,
      painter: _HistoryPainter(
        cloneSource: null,
        brushRadius: ref.read(historyBrushStateProvider).brushRadius,
        brushHardness: getBrushHardness(ref),
        imageDisplaySize: widget.imageDisplaySize,
        crop: widget.crop,
        sourceWidth: widget.sourceWidth,
        sourceHeight: widget.sourceHeight,
        cursorPos: cursorPos,
        cursorSrc: cursorSrc,
        isSampling: false,
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

class _HistoryPainter extends BaseStampPainter<HistoryMark> {
  _HistoryPainter({
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
