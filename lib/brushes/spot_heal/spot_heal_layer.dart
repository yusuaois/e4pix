import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/brush_layer.dart';
import '../../core/models/mask_shape.dart';
import 'spot_heal_model.dart';
import '../../render/brush_layer_provider.dart';
import '../../render/brush_rasterizer.dart';
import '../../render/incremental_render_cache.dart';
import '../shared/brush_hashes.dart';
import '../shared/brush_layer_mixin.dart';
import '../shared/brush_warmup_utils.dart';
import '../../utils/shader_pass_util.dart';

/// 污点修复输出层
///
/// 通过 [rasterizeBrushMask] 将 marks 转为二值遮罩
/// shader 沿 16 个射线方向采样边界像素，用 IDW 混合填充遮罩区域
class SpotHealLayerProvider
    with ShaderCacheMixin
    implements BrushLayerProvider {
  @override
  String get id => 'spot_heal';

  final _cache = IncrementalRenderCache<SpotHealMark>(
    computeKey: hashSpotHealMarks,
  );
  @override
  final ui.FragmentProgram brushProgram;

  SpotHealLayerProvider({required ui.FragmentProgram program})
    : brushProgram = program;

  @override
  bool isActive(AdjustmentParams params) =>
      (params.brushMarks['spot_heal']?.isNotEmpty ?? false);

  @override
  int computeMarksHash(AdjustmentParams params) => hashSpotHealMarks(
    params.brushMarks['spot_heal']?.cast<SpotHealMark>() ?? const [],
  );

  @override
  Future<BrushLayer> render({
    required AdjustmentParams params,
    required ui.Image developOutput,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final marks =
        params.brushMarks['spot_heal']?.cast<SpotHealMark>() ?? const [];
    if (marks.isEmpty) return BrushLayer(id: id, active: false);

    final texture = await _renderMask(
      base: developOutput,
      marks: marks,
      developKey: developKey,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    return BrushLayer(id: id, texture: texture, active: true);
  }

  Future<ui.Image> _renderMask({
    required ui.Image base,
    required List<SpotHealMark> marks,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    // 1. 缓存检查
    final cached = _cache.getFromMarksCache(developKey, marks);
    if (cached != null) return cached;

    // 2. 将 marks 转为笔触并光栅化遮罩
    // 每个 mark 成为带半径的单点笔触，限制半径上限 0.5 避免 GPU 开销过大
    final strokes = marks.map((m) {
      return BrushStroke(
        points: [m.target],
        radius: m.radius.clamp(0.001, 0.5),
        hardness: m.hardness,
        flow: 1.0,
      );
    }).toList();

    final maskTex = await rasterizeBrushMask(
      BrushMask(strokes: strokes),
      targetWidth,
      targetHeight,
    );

    // 3. Shader pass：从边界采样填充遮罩区域
    final avgHardness = marks.isEmpty
        ? 0.0
        : marks.map((m) => m.hardness).reduce((a, b) => a + b) / marks.length;

    final result = await runSingleShaderPass(
      shader: brushShader,
      outputWidth: targetWidth,
      outputHeight: targetHeight,
      samplers: [base, maskTex],
      setUniforms: (s) {
        s.setFloat(0, targetWidth.toDouble());
        s.setFloat(1, targetHeight.toDouble());
        s.setFloat(2, avgHardness);
      },
    );

    maskTex.dispose();

    // 4. 更新缓存（spot_heal 不使用增量渲染
    //    marks 一次性光栅化为遮罩，仅完整 marks 哈希缓存有效）
    _cache.putMarksCache(developKey, marks, result);

    return result;
  }

  @override
  Future<void> warmup(
    ui.Image developOutput,
    int targetWidth,
    int targetHeight,
  ) async {
    final warmupMask = await createWarmupMask();
    try {
      final result = await runSingleShaderPass(
        shader: brushShader,
        outputWidth: targetWidth,
        outputHeight: targetHeight,
        samplers: [developOutput, warmupMask],
        setUniforms: (s) {
          s.setFloat(0, targetWidth.toDouble());
          s.setFloat(1, targetHeight.toDouble());
          s.setFloat(2, 0.0);
        },
      );
      result.dispose();
    } catch (e) {
      debugPrint('[Warmup] spot_heal FAILED: $e');
    }
    warmupMask.dispose();
  }

  @override
  void invalidate() => _cache.invalidate();

  @override
  void dispose() => _cache.dispose();
}
