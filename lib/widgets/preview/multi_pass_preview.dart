import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../render/brush_layer_provider.dart';
import '../../render/brush_layer_registry.dart';
import '../../render/full_pipeline_renderer.dart';
import '../../render/incremental_render_cache.dart';
import '../../brushes/healing/healing_cache.dart';
import '../../render/gpu_warmup.dart';
import '../../render/homography.dart';
import '../../../brushes/healing/healing_layer.dart';
import '../../../brushes/spot_heal/spot_heal_layer.dart';
import '../../../brushes/clone_stamp/clone_stamp_layer.dart';
import '../../render/mask_cache.dart';
import '../../../brushes/clone_stamp/clone_stamp_cache.dart';
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
  final ui.FragmentProgram? spotRemoveProgram;
  final ui.FragmentProgram? healingProgram;
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
    this.spotRemoveProgram,
    this.healingProgram,
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
  final _spotRemovalCache = IncrementalRenderCache(computeKey: hashSpots);
  final _healingCache = IncrementalRenderCache(computeKey: hashMarks);

  // Compose pass: layer providers (created lazily when shaders are ready)
  SpotRemovalLayerProvider? _spotLayer;
  HealingLayerProvider? _healLayer;
  SpotHealLayerProvider? _spotHealLayer;
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
      _spotRemovalCache.invalidate();
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
        old.spotRemoveProgram != widget.spotRemoveProgram ||
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
    _spotRemovalCache.dispose();
    _healingCache.dispose();
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

      // Compose pass: build layer registry from available brush shaders.
      // Lazy-init providers; rebuild registry each render for freshness.
      final composeProgram = ref.read(composeShaderProgramProvider).value;
      BrushLayerRegistry? layerReg;
      if (composeProgram != null) {
        final providers = <BrushLayerProvider>[];
        final spotRemoveProgram = ref
            .read(spotRemoveShaderProgramProvider)
            .value;
        if (spotRemoveProgram != null) {
          _spotLayer ??= SpotRemovalLayerProvider(program: spotRemoveProgram);
          providers.add(_spotLayer!);
        }
        final healingProgram = ref.read(healingShaderProgramProvider).value;
        if (healingProgram != null) {
          _healLayer ??= HealingLayerProvider(program: healingProgram);
          providers.add(_healLayer!);
        }
        final spotHealProgram = ref.read(spotHealShaderProgramProvider).value;
        if (spotHealProgram != null) {
          _spotHealLayer ??= SpotHealLayerProvider(program: spotHealProgram);
          providers.add(_spotHealLayer!);
        }
        if (providers.isNotEmpty) {
          _layerRegistry = BrushLayerRegistry(providers: providers);
          layerReg = _layerRegistry;
        }
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
        spotRemoveProgram: widget.spotRemoveProgram,
        healingProgram: widget.healingProgram,
        composeProgram: composeProgram,
        brushLayerRegistry: layerReg,
        perspectiveCache: _perspectiveCache,
        targetWidth: tw,
        targetHeight: th,
        developCache: _developCache,
        brushCache: _brushCache,
        allowStaleAutoMask: isDragging,
        spotRemovalCache: _spotRemovalCache,
        healingCache: _healingCache,
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
      ref.read(renderedBrushHashesProvider.notifier).state = hashes;

      // 更新 Develop 输出供 spot removal overlay 笔画预览
      ref.read(developOutputProvider.notifier).update(result.developOutput);

      // 递增渲染代数，通知 preview_area 刷新 develop 输出
      ref.read(renderedPreviewGenerationProvider.notifier).state++;

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

      final spotProg = ref.read(spotRemoveShaderProgramProvider).value;
      final healProg = ref.read(healingShaderProgramProvider).value;
      final spotHealProg = ref.read(spotHealShaderProgramProvider).value;
      final composeProg = ref.read(composeShaderProgramProvider).value;

      final tasks = buildWarmupTasks(
        spotRemoveProgram: spotProg,
        healingProgram: healProg,
        spotHealProgram: spotHealProg,
        composeProgram: composeProg,
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

  @override
  Widget build(BuildContext context) {
    ref.listen(throttledParamsProvider, (prev, next) {
      if (prev != next) _runRender();
    });
    ref.listen(isUserDraggingSliderProvider, (prev, next) {
      if (prev == true && next == false) {
        // 拖动结束：失效 Level-1 hash 缓存强制重算，保留增量缓存
        _spotRemovalCache.invalidateMarksCache();
        _healingCache.invalidateMarksCache();
        _runRender();
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
