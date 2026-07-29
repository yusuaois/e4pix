import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/theme/app_colors.dart';
import '../../state/providers.dart';
import 'multi_pass_preview.dart';

class SplitCompareView extends ConsumerStatefulWidget {
  final ui.Image image;
  final AdjustmentParams params;
  final ui.FragmentProgram developProgram;
  final ui.FragmentProgram maskProgram;
  final ui.Image? lutA;
  final int lutSizeA;
  final ui.Image? lutB;
  final int lutSizeB;
  final ui.Image? curve;
  final ui.FragmentProgram? sharpenProgram;
  final ui.FragmentProgram? denoiseProgram;
  final ui.FragmentProgram? perspectiveProgram;
  final ui.FragmentProgram? lensCorrectProgram;

  const SplitCompareView({
    super.key,
    required this.image,
    required this.params,
    required this.developProgram,
    required this.maskProgram,
    this.lutA,
    this.lutSizeA = 0,
    this.lutB,
    this.lutSizeB = 0,
    this.curve,
    this.sharpenProgram,
    this.denoiseProgram,
    this.perspectiveProgram,
    this.lensCorrectProgram,
  });

  @override
  ConsumerState<SplitCompareView> createState() => _SplitCompareViewState();
}

class _SplitCompareViewState extends ConsumerState<SplitCompareView> {
  late final ValueNotifier<double> _dividerNotifier;

  @override
  void initState() {
    super.initState();
    _dividerNotifier = ValueNotifier(ref.read(splitDividerProvider));
  }

  @override
  void dispose() {
    _dividerNotifier.dispose();
    super.dispose();
  }

  void _exitSplit() {
    ref.read(compareViewModeProvider.notifier).turnOff();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final imgW = widget.image.width.toDouble();
        final imgH = widget.image.height.toDouble();
        final fit = applyBoxFit(
          BoxFit.contain,
          Size(imgW, imgH),
          constraints.biggest,
        );
        final displaySize = fit.destination;

        return GestureDetector(
          onDoubleTap: _exitSplit,
          child: Stack(
            children: [
              Center(child: _buildImageStack(displaySize)),
              _buildDividerOverlay(displaySize),
              _buildLabelOverlay(displaySize),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageStack(Size displaySize) {
    return SizedBox.fromSize(
      size: displaySize,
      child: Stack(
        children: [
          Positioned.fill(child: RepaintBoundary(child: _buildEditedPreview())),
          ValueListenableBuilder<double>(
            valueListenable: _dividerNotifier,
            builder: (context, divider, _) {
              return ClipRect(
                clipper: _LeftClipper(divider),
                child: RepaintBoundary(child: _buildOriginalPreview()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEditedPreview() {
    return MultiPassPreview(
      developProgram: widget.developProgram,
      maskProgram: widget.maskProgram,
      sourceImage: widget.image,
      params: widget.params,
      lutTexture: widget.lutA,
      lutSize: widget.lutSizeA,
      lutTextureB: widget.lutB,
      lutSizeB: widget.lutSizeB,
      curveTexture: widget.curve,
      sharpenProgram: widget.sharpenProgram,
      denoiseProgram: widget.denoiseProgram,
      perspectiveProgram: widget.perspectiveProgram,
      lensCorrectProgram: widget.lensCorrectProgram,
    );
  }

  Widget _buildOriginalPreview() {
    return MultiPassPreview(
      developProgram: widget.developProgram,
      maskProgram: widget.maskProgram,
      sourceImage: widget.image,
      params: AdjustmentParams.neutral,
      lutTexture: null,
      lutSize: 0,
      lutTextureB: null,
      lutSizeB: 0,
      curveTexture: null,
      sharpenProgram: null,
      denoiseProgram: null,
    );
  }

  Widget _buildDividerOverlay(Size displaySize) {
    return Center(
      child: SizedBox.fromSize(
        size: displaySize,
        child: ValueListenableBuilder<double>(
          valueListenable: _dividerNotifier,
          builder: (context, divider, child) {
            return Stack(
              children: [
                // 分隔线
                Positioned(
                  left: displaySize.width * divider - 1,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(width: 2, color: AppColors.activeValue),
                  ),
                ),
                // 拖拽手柄
                Positioned(
                  left: displaySize.width * divider - 32,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      _dividerNotifier.value =
                          (_dividerNotifier.value +
                                  d.delta.dx / displaySize.width)
                              .clamp(0.02, 0.98);
                    },
                    onHorizontalDragEnd: (_) {
                      ref
                          .read(splitDividerProvider.notifier)
                          .set(_dividerNotifier.value);
                    },
                    child: Container(
                      width: 64,
                      height: double.infinity,
                      color: Colors.transparent,
                      alignment: Alignment.center,
                      child: Container(
                        width: 32,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.activeValue,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: RotatedBox(
                            quarterTurns: 1,
                            child: Icon(
                              Icons.unfold_more,
                              size: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLabelOverlay(Size displaySize) {
    return Center(
      child: SizedBox.fromSize(
        size: displaySize,
        child: ValueListenableBuilder<double>(
          valueListenable: _dividerNotifier,
          builder: (context, divider, _) {
            final labelScale = (displaySize.width / 250).clamp(0.55, 1.0);
            return Stack(
              children: [
                Positioned(
                  left: 8 * labelScale,
                  top: 8 * labelScale,
                  child: _Label(
                    text: 'Original',
                    alpha: divider > 0.3 ? 0.7 : 0.2,
                    scale: labelScale,
                  ),
                ),
                Positioned(
                  right: 8 * labelScale,
                  top: 8 * labelScale,
                  child: _Label(
                    text: 'Edited',
                    alpha: divider < 0.7 ? 0.7 : 0.2,
                    scale: labelScale,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  final double divider;
  const _LeftClipper(this.divider);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * divider, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.divider != divider;
}

class _Label extends StatelessWidget {
  final String text;
  final double alpha;
  final double scale;
  const _Label({required this.text, required this.alpha, this.scale = 1.0});

  @override
  Widget build(BuildContext c) => Container(
    padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(3 * scale),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10 * scale,
        color: AppColors.textPrimary.withValues(alpha: alpha),
      ),
    ),
  );
}
