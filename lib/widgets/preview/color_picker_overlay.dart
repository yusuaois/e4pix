import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../render/full_pipeline_renderer.dart';
import '../../state/providers.dart';

/// 取色 readback 层：覆盖在预览上，捕获鼠标位置，从渲染后的小图取色
///
/// 仅在取色模式开启时挂载，渲染当前预览到 [_readbackEdge]px，readback 一次缓存；
/// 鼠标移动从缓存取点（不重渲染）；参数变化时重渲染
class ColorPickerOverlay extends ConsumerStatefulWidget {
  final ui.FragmentProgram developProgram;
  final ui.FragmentProgram maskProgram;
  final ui.Image sourceImage;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;
  final ui.Image? lutTextureB;
  final int lutSizeB;
  final ui.Image? curveTexture;
  final ui.FragmentProgram? sharpenProgram;
  final ui.FragmentProgram? denoiseProgram;
  final Size displaySize;

  const ColorPickerOverlay({
    super.key,
    required this.developProgram,
    required this.maskProgram,
    required this.sourceImage,
    required this.params,
    required this.displaySize,
    this.lutTexture,
    this.lutSize = 0,
    this.lutTextureB,
    this.lutSizeB = 0,
    this.curveTexture,
    this.sharpenProgram,
    this.denoiseProgram,
  });

  @override
  ConsumerState<ColorPickerOverlay> createState() => _ColorPickerOverlayState();
}

class _ColorPickerOverlayState extends ConsumerState<ColorPickerOverlay> {
  static const _readbackEdge = 512;

  Uint8List? _rgba; // 渲染后小图的像素
  int _rbW = 0, _rbH = 0;
  bool _rendering = false;
  Offset? _cursor; // 当前光标位置

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(ColorPickerOverlay old) {
    super.didUpdateWidget(old);
    if (old.params != widget.params ||
        old.sourceImage != widget.sourceImage ||
        old.lutTexture != widget.lutTexture ||
        old.lutTextureB != widget.lutTextureB ||
        old.curveTexture != widget.curveTexture ||
        old.sharpenProgram != widget.sharpenProgram ||
        old.denoiseProgram != widget.denoiseProgram) {
      _render();
    }
  }

  Future<void> _render() async {
    if (_rendering) return;
    _rendering = true;
    try {
      final src = widget.sourceImage;
      final longest = src.width > src.height ? src.width : src.height;
      final scale = _readbackEdge / longest;
      final dw = (src.width * scale).round().clamp(16, _readbackEdge);
      final dh = (src.height * scale).round().clamp(16, _readbackEdge);

      final rendered = await FullPipelineRenderer.render(
        developProgram: widget.developProgram,
        maskProgram: widget.maskProgram,
        sourceImage: src,
        params: widget.params,
        lutTexture: widget.lutTexture,
        lutSize: widget.lutSize,
        lutTextureB: widget.lutTextureB,
        lutSizeB: widget.lutSizeB,
        curveTexture: widget.curveTexture,
        sharpenProgram: widget.sharpenProgram,
        denoiseProgram: widget.denoiseProgram,
        targetWidth: dw,
        targetHeight: dh,
      );
      try {
        final bd = await rendered.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (!mounted) return;
        _rgba = bd?.buffer.asUint8List();
        _rbW = rendered.width;
        _rbH = rendered.height;

        setState(() {});
        if (_cursor != null) _updateReadingAt(_cursor!);
      } finally {
        rendered.dispose();
      }
    } catch (_) {
    } finally {
      _rendering = false;
    }
  }

  void _updateReadingAt(Offset localPos) {
    final rgba = _rgba;
    if (rgba == null || _rbW == 0 || _rbH == 0) return;

    final nx = (localPos.dx / widget.displaySize.width).clamp(0.0, 1.0);
    final ny = (localPos.dy / widget.displaySize.height).clamp(0.0, 1.0);
    final px = (nx * (_rbW - 1)).round();
    final py = (ny * (_rbH - 1)).round();

    final idx = (py * _rbW + px) * 4;
    if (idx < 0 || idx + 3 >= rgba.length) return;
    ref
        .read(pickedColorProvider.notifier)
        .set(PickedColor(rgba[idx], rgba[idx + 1], rgba[idx + 2], nx, ny));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.precise,
          // 处理电脑端鼠标悬停
          onHover: (e) {
            _cursor = e.localPosition;
            _updateReadingAt(e.localPosition);
          },
          // 处理鼠标移出区域
          onExit: (_) {
            _cursor = null;
            ref.read(pickedColorProvider.notifier).set(null);
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            // 处理手机端手指按下 / 电脑端鼠标点击
            onPointerDown: (e) {
              _cursor = e.localPosition;
              _updateReadingAt(e.localPosition);
            },
            // 处理手机端手指拖拽滑动 / 电脑端鼠标点击拖拽
            onPointerMove: (e) {
              _cursor = e.localPosition;
              _updateReadingAt(e.localPosition);
            },
            // 处理手指抬起
            onPointerUp: (_) {
              // _cursor = null;
              // ref.read(pickedColorProvider.notifier).set(null);
            },
            // 处理触摸被系统取消
            onPointerCancel: (_) {
              // _cursor = null;
              // ref.read(pickedColorProvider.notifier).set(null);
            },
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}
