import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../render/develop_uniforms.dart';
import '../../state/providers.dart';

class SplitCompareView extends ConsumerStatefulWidget {
  final ui.Image image;
  final AdjustmentParams params;
  final ui.Image? lutA;
  final int lutSizeA;
  final ui.Image? lutB;
  final int lutSizeB;
  final ui.Image? curve;

  const SplitCompareView({
    super.key,
    required this.image,
    required this.params,
    this.lutA,
    this.lutSizeA = 0,
    this.lutB,
    this.lutSizeB = 0,
    this.curve,
  });

  @override
  ConsumerState<SplitCompareView> createState() => _SplitCompareViewState();
}

class _SplitCompareViewState extends ConsumerState<SplitCompareView> {
  ui.FragmentShader? _shader;
  late final ValueNotifier<double> _dividerNotifier;

  @override
  void initState() {
    super.initState();
    _dividerNotifier = ValueNotifier(ref.read(splitDividerProvider));
    _loadShader();
  }

  @override
  void dispose() {
    _dividerNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'assets/shaders/develop.shader',
      );
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (_) {}
  }

  void _exitSplit() {
    ref.read(compareViewModeProvider.notifier).turnOff();
  }

  @override
  Widget build(BuildContext context) {
    if (_shader == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

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
              Center(
                child: SizedBox.fromSize(
                  size: displaySize,
                  child: ClipRect(
                    child: CustomPaint(
                      painter: _SplitPainter(
                        shader: _shader!,
                        image: widget.image,
                        params: widget.params,
                        lutA: widget.lutA,
                        lutSizeA: widget.lutSizeA,
                        lutB: widget.lutB,
                        lutSizeB: widget.lutSizeB,
                        curve: widget.curve,
                        dividerNotifier: _dividerNotifier, // 传入 Notifier
                      ),
                      size: displaySize,
                    ),
                  ),
                ),
              ),

              ValueListenableBuilder<double>(
                valueListenable: _dividerNotifier,
                builder: (context, divider, child) {
                  return Stack(
                    children: [
                      // 分隔线手柄
                      Center(
                        child: SizedBox.fromSize(
                          size: displaySize,
                          child: Stack(
                            children: [
                              Positioned(
                                left: displaySize.width * divider - 1,
                                top: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 2,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: displaySize.width * divider - 20,
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
                                            .state =
                                        _dividerNotifier.value;
                                  },
                                  child: Container(
                                    width: 40,
                                    height: double.infinity,
                                    color: Colors.transparent,
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: 32,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.unfold_more,
                                            size: 14,
                                            color: Colors.black87,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _Label(
                          text: 'Original',
                          alpha: divider > 0.3 ? 0.7 : 0.2,
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: _Label(
                          text: 'Edited',
                          alpha: divider < 0.7 ? 0.7 : 0.2,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final double alpha;
  const _Label({required this.text, required this.alpha});
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: Colors.white.withValues(alpha: alpha),
      ),
    ),
  );
}

class _SplitPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image image;
  final AdjustmentParams params;
  final ui.Image? lutA;
  final int lutSizeA;
  final ui.Image? lutB;
  final int lutSizeB;
  final ui.Image? curve;
  final ValueNotifier<double> dividerNotifier;

  _SplitPainter({
    required this.shader,
    required this.image,
    required this.params,
    this.lutA,
    this.lutSizeA = 0,
    this.lutB,
    this.lutSizeB = 0,
    this.curve,
    required this.dividerNotifier,
  }) : super(repaint: dividerNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    final splitX = size.width * dividerNotifier.value.clamp(0.0, 1.0);

    // 左侧：原片
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, splitX, size.height));
    applyDevelopUniforms(
      shader: shader,
      renderSize: size,
      params: AdjustmentParams.neutral,
      image: image,
      lutTexture: null,
      curveTexture: null,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    canvas.restore();

    // 右侧：当前参数
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(splitX, 0, size.width - splitX, size.height));
    applyDevelopUniforms(
      shader: shader,
      renderSize: size,
      params: params,
      image: image,
      lutTexture: lutA,
      lutSize: lutSizeA,
      lutTextureB: lutB,
      lutSizeB: lutSizeB,
      curveTexture: curve,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SplitPainter old) =>
      shader != old.shader ||
      image != old.image ||
      params != old.params ||
      lutA != old.lutA ||
      lutB != old.lutB ||
      curve != old.curve;
}
