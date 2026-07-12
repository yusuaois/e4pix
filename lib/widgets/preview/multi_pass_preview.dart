import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brushes/brush_manifest.dart';
import '../../core/models/adjustment_params.dart';
import '../../render/brush_layer_provider.dart';
import '../../render/brush_layer_registry.dart';
import '../../render/full_pipeline_renderer.dart';
import '../../render/gpu_warmup.dart';
import '../../render/homography.dart';
import '../../render/mask_cache.dart';
import '../../state/providers.dart';
import '../../utils/shader_pass_util.dart';

/// 离屏多 pass 预览
class MultiPassPreview extends ConsumerStatefulWidget {
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
  final ui.FragmentProgram? perspectiveProgram;
  final ui.FragmentProgram? lensCorrectProgram;
  final int idleMaxEdge;
  final int draggingMaxEdge;

  const MultiPassPreview({
    super.key,
    required this.developProgram,
    required this.maskProgram,
    required this.sourceImage,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
    this.lutTextureB,
    this.lutSizeB = 0,
    this.curveTexture,
    this.sharpenProgram,
    this.denoiseProgram,
    this.perspectiveProgram,
    this.lensCorrectProgram,
    this.idleMaxEdge = 2400,
    this.draggingMaxEdge = 800,
  });

  @override
  ConsumerState<MultiPassPreview> createState() => _MultiPassPreviewState();
}

class _MultiPassPreviewState extends ConsumerState<MultiPassPreview> {
  ui.Image? _rendered;
  int _generation = 0;

  bool _isRendering = false;
  bool _pendingRender = false;

  bool _hasWarmedUpProviders = false;

  final _developCache = DevelopPassCache();
  final _brushCache = BrushMaskCache();
  final _perspectiveCache = PerspectiveMatrixCache();

  // Compose pass：layer provider（shader 就绪后惰性创建）
  final _brushLayers = <String, BrushLayerProvider>{};
  BrushLayerRegistry? _layerRegistry;

  @override
  void initState() {
    super.initState();
    _runRender();
  }

  @override
  void didUpdateWidget(MultiPassPreview old) {
    super.didUpdateWidget(old);
    if (old.sourceImage != widget.sourceImage) {
      _perspectiveCache.invalidate();
      _layerRegistry?.invalidateAll();
      _hasWarmedUpProviders = false;
    }
    if (old.sourceImage != widget.sourceImage ||
        old.lutTexture != widget.lutTexture ||
        old.lutSize != widget.lutSize ||
        old.lutTextureB != widget.lutTextureB ||
        old.lutSizeB != widget.lutSizeB ||
        old.curveTexture != widget.curveTexture ||
        old.sharpenProgram != widget.sharpenProgram ||
        old.denoiseProgram != widget.denoiseProgram ||
        old.perspectiveProgram != widget.perspectiveProgram ||
        old.lensCorrectProgram != widget.lensCorrectProgram ||
        old.idleMaxEdge != widget.idleMaxEdge ||
        old.draggingMaxEdge != widget.draggingMaxEdge ||
        old.params != widget.params) {
      _runRender();
    }
  }

  @override
  void dispose() {
    _rendered?.dispose();
    _developCache.dispose();
    _brushCache.dispose();
    _layerRegistry?.dispose();
    super.dispose();
  }

  Future<void> _runRender() async {
    if (_isRendering) {
      _pendingRender = true;
      return;
    }
    _isRendering = true;
    _pendingRender = false;

    try {
      final gen = ++_generation;
      final src = widget.sourceImage;

      final isDragging = ref.read(isUserDraggingSliderProvider);
      final maxEdge = isDragging ? widget.draggingMaxEdge : widget.idleMaxEdge;

      final longest = math.max(src.width, src.height);
      final scale = longest > maxEdge ? maxEdge / longest : 1.0;
      final tw = (src.width * scale).round();
      final th = (src.height * scale).round();

      // 从可用画笔 shader 构建 layer registry
      // provider 惰性初始化，每次渲染重建 registry
      final brushPrograms = ref.read(brushShaderProgramsProvider).value ?? {};
      BrushLayerRegistry? layerReg;
      final providers = <BrushLayerProvider>[];
      final layerOrder = ref.read(brushLayerOrderProvider);
      for (final m in orderedManifests(layerOrder)) {
        final prog = brushPrograms[m.id];
        if (prog != null) {
          _brushLayers.putIfAbsent(m.id, () => m.layerFactory(prog));
          providers.add(_brushLayers[m.id]!);
        }
      }
      if (providers.isNotEmpty) {
        _layerRegistry = BrushLayerRegistry(providers: providers);
        layerReg = _layerRegistry;
      }

      final result = await FullPipelineRenderer.render(
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
        perspectiveProgram: widget.perspectiveProgram,
        lensCorrectProgram: widget.lensCorrectProgram,
        brushLayerRegistry: layerReg,
        perspectiveCache: _perspectiveCache,
        targetWidth: tw,
        targetHeight: th,
        developCache: _developCache,
        brushCache: _brushCache,
        allowStaleAutoMask: isDragging,
      );

      if (gen != _generation || !mounted) {
        result.finalImage.dispose();
        // developOutput 由下一次 update() 调用回收，此处不 dispose
        return;
      }
      final old = _rendered;
      setState(() => _rendered = result.finalImage);
      old?.dispose();

      // 遍历活跃 provider 收集所有 brush marks hash
      // overlay 按 provider.id 订阅，hash 匹配时清除 committed preview
      final hashes = <String, int>{};
      for (final p
          in layerReg?.activeProviders(widget.params) ??
              <BrushLayerProvider>[]) {
        hashes[p.id] = p.computeMarksHash(widget.params);
      }
      ref.read(renderedBrushHashesProvider.notifier).set(hashes);

      // 更新 Develop 输出供 spot removal overlay 笔画预览
      ref.read(developOutputProvider.notifier).update(result.developOutput);

      // 捕获 compose guide 供选区服务
      final devOut = result.developOutput;
      if (devOut != null) {
        final hasPixelMarks = brushManifests.any(
          (m) => m.hasMarks(widget.params),
        );
        if (hasPixelMarks) {
          _captureComposeGuide(devOut);
        }
      }

      // 递增渲染代数，通知 preview_area 刷新 develop 输出
      ref.read(renderedPreviewGenerationProvider.notifier).increment();

      // 首次渲染后，用真实 developOutput 后台预热所有 brush provider
      // 首帧 developOutput 通常为 null（无 mask 无 compose marks）
      // 此时用 finalImage 替代——预热只需纹理作 sampler 占位，内容不重要
      final warmupImage = result.developOutput ?? result.finalImage;
      if (!_hasWarmedUpProviders) {
        _hasWarmedUpProviders = true;
        _runProviderWarmup(warmupImage, tw, th);
      }
    } on DisposedImageException {
      // 纹理已 dispose，跳过本帧，等待下次渲染
      debugPrint('[MultiPassPreview] Skipped render: source image disposed');
    } finally {
      _isRendering = false;
      if (_pendingRender && mounted) {
        _pendingRender = false;
        _runRender();
      }
    }
  }

  void _runProviderWarmup(ui.Image? developOutput, int tw, int th) {
    if (developOutput == null || !mounted) return;

    ui.Image devClone;
    try {
      devClone = developOutput.clone();
    } catch (_) {
      return;
    }

    ref.read(shaderWarmupProvider.future).then((_) {
      if (!mounted) {
        devClone.dispose();
        return;
      }

      final brushProgs = ref.read(brushShaderProgramsProvider).value ?? {};

      final tasks = buildWarmupTasks(
        brushPrograms: brushProgs,
        developOutput: devClone,
        targetWidth: tw,
        targetHeight: th,
      );

      if (tasks.isEmpty) {
        devClone.dispose();
        return;
      }
      runWarmupChain(tasks, devClone, isMounted: () => mounted);
    });
  }

  /// 降采样 compose 结果供主体/智能选区作 guide
  Future<void> _captureComposeGuide(ui.Image src) async {
    const maxEdge = 1280;
    final longest = math.max(src.width, src.height);
    if (longest <= maxEdge) {
      try {
        if (!mounted) return;
        ref.read(composeGuideProvider.notifier).update(src.clone());
      } catch (e) {
        debugPrint('[MultiPassPreview] Failed to capture compose guide: $e');
      }
      return;
    }
    final scale = maxEdge / longest;
    final tw = (src.width * scale).round();
    final th = (src.height * scale).round();
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        src,
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
        Paint(),
      );
      final picture = recorder.endRecording();
      final result = await picture.toImage(tw, th);
      picture.dispose();
      if (!mounted) {
        result.dispose();
        return;
      }
      ref.read(composeGuideProvider.notifier).update(result);
    } catch (e) {
      debugPrint('[MultiPassPreview] Failed to capture compose guide: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(throttledParamsProvider, (prev, next) {
      if (prev != next) _runRender();
    });
    ref.listen(isUserDraggingSliderProvider, (prev, next) {
      if (prev == true && next == false) {
        // 拖动结束：通过 layer provider 失效缓存再重算
        for (final p in _brushLayers.values) {
          p.invalidate();
        }
        _runRender();
      }
    });
    // 画笔图层顺序变化时触发重渲染
    ref.listen(brushLayerOrderProvider, (prev, next) {
      if (prev != next) _runRender();
    });
    // 任意画笔 marks 数量变化时立即置空 developOutput，关闭旧烘焙图残留窗口
    ref.listen(currentParamsNotifierProvider, (prev, next) {
      if (prev == null) {
        ref.read(developOutputProvider.notifier).update(null);
        return;
      }
      for (final m in brushManifests) {
        final nextLen = next.brushMarks[m.id]?.length ?? 0;
        final prevLen = prev.brushMarks[m.id]?.length ?? 0;
        if (nextLen != prevLen) {
          ref.read(developOutputProvider.notifier).update(null);
          return;
        }
      }
    });

    if (_rendered == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return SizedBox.expand(
      child: RawImage(image: _rendered, fit: BoxFit.fill),
    );
  }
}
