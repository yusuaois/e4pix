import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/adjustment_params.dart';
import '../render/full_pipeline_renderer.dart';
import '../state/interaction_state.dart';

/// 离屏多 pass 预览。当 params.locals 包含启用的局部调整时使用。
class MultiPassPreview extends ConsumerStatefulWidget {
  final ui.FragmentProgram developProgram;
  final ui.FragmentProgram maskProgram;
  final ui.Image sourceImage;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;

  /// 闲置时（用户没在拖滑块）渲染的最大长边。
  /// 桌面建议 2400；手机建议 1600。调用方决定。
  final int idleMaxEdge;

  /// 拖滑块期间使用的最大长边。
  final int draggingMaxEdge;

  const MultiPassPreview({
    super.key,
    required this.developProgram,
    required this.maskProgram,
    required this.sourceImage,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
    this.idleMaxEdge = 2400,
    this.draggingMaxEdge = 800,
  });

  @override
  ConsumerState<MultiPassPreview> createState() => _MultiPassPreviewState();
}

class _MultiPassPreviewState extends ConsumerState<MultiPassPreview> {
  ui.Image? _rendered;
  int _generation = 0;
  Timer? _debounce;
  ProviderSubscription<bool>? _dragSub;

  @override
  void initState() {
    super.initState();
    // 监听拖动结束 → 触发一次高质量重渲
    _dragSub = ref.listenManual<bool>(
      isUserDraggingSliderProvider,
      (prev, next) {
        if (prev == true && next == false) {
          _scheduleRender(highQualityDelay: const Duration(milliseconds: 80));
        }
      },
    );
    _scheduleRender();
  }

  @override
  void didUpdateWidget(MultiPassPreview old) {
    super.didUpdateWidget(old);
    if (old.sourceImage != widget.sourceImage ||
        old.params != widget.params ||
        old.lutTexture != widget.lutTexture ||
        old.lutSize != widget.lutSize) {
      _scheduleRender();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dragSub?.close();
    _rendered?.dispose();
    super.dispose();
  }

  /// 普通调度：33ms debounce。
  /// 拖动刚结束时可以传一个稍长的 delay，等 final value 稳定。
  void _scheduleRender({Duration? highQualityDelay}) {
    _debounce?.cancel();
    _debounce = Timer(
      highQualityDelay ?? const Duration(milliseconds: 33),
      _runRender,
    );
  }

  Future<void> _runRender() async {
    final gen = ++_generation;
    final src = widget.sourceImage;

    // 根据当前是否在拖动决定 maxEdge
    final isDragging = ref.read(isUserDraggingSliderProvider);
    final maxEdge =
        isDragging ? widget.draggingMaxEdge : widget.idleMaxEdge;

    final longest = math.max(src.width, src.height);
    final scale = longest > maxEdge ? maxEdge / longest : 1.0;
    final tw = (src.width * scale).round();
    final th = (src.height * scale).round();

    try {
      final result = await FullPipelineRenderer.render(
        developProgram: widget.developProgram,
        maskProgram: widget.maskProgram,
        sourceImage: src,
        params: widget.params,
        lutTexture: widget.lutTexture,
        lutSize: widget.lutSize,
        targetWidth: tw,
        targetHeight: th,
      );
      if (gen != _generation || !mounted) {
        result.dispose();
        return;
      }
      final old = _rendered;
      setState(() => _rendered = result);
      old?.dispose();
    } catch (e) {
      debugPrint('MultiPassPreview render failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rendered == null) {
      return const Stack(
        alignment: Alignment.center,
        children: [CircularProgressIndicator(strokeWidth: 2)],
      );
    }
    return RawImage(image: _rendered, fit: BoxFit.contain);
  }
}