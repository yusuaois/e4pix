import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/brush_layer.dart';
import 'healing_model.dart';
import '../../render/brush_layer_provider.dart';
import '../../render/incremental_render_cache.dart';
import '../shared/brush_hashes.dart';
import '../shared/brush_layer_mixin.dart';
import '../shared/spot_data_texture.dart';
import '../../utils/brush_preview_utils.dart';
import '../../utils/shader_pass_util.dart';

/// 修复画笔输出层
///
/// 将修复 marks 渲染到 develop 输出上，返回 [BrushLayer]
/// 其 alpha 通道标记被修改的像素
class HealingLayerProvider with ShaderCacheMixin implements BrushLayerProvider {
  @override
  String get id => 'healing';

  final _cache = IncrementalRenderCache<HealingMark>(
    computeKey: hashHealingMarks,
  );
  @override
  final ui.FragmentProgram brushProgram;

  HealingLayerProvider({required ui.FragmentProgram program})
    : brushProgram = program;

  static const _kMaxMarks = 128;
  // uniform 总数：3（uSize + uMarkCount），mark 数据通过 uMarkData 纹理传入

  @override
  bool isActive(AdjustmentParams params) => params.healingMarks.isNotEmpty;

  @override
  int computeMarksHash(AdjustmentParams params) =>
      hashHealingMarks(params.healingMarks);

  @override
  Future<BrushLayer> render({
    required AdjustmentParams params,
    required ui.Image developOutput,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final marks = params.healingMarks.where((m) {
      return !isMarkSourceFullyOOB(
        sourceX: m.source.dx,
        sourceY: m.source.dy,
        radius: m.radius,
        imageWidth: developOutput.width.toDouble(),
        imageHeight: developOutput.height.toDouble(),
      );
    }).toList();

    if (marks.isEmpty) {
      return BrushLayer(id: id, active: false);
    }

    final texture = await _renderMarks(
      base: developOutput,
      marks: marks,
      developKey: developKey,
    );

    return BrushLayer(id: id, texture: texture, active: true);
  }

  Future<ui.Image> _renderMarks({
    required ui.Image base,
    required List<HealingMark> marks,
    required int developKey,
  }) async {
    if (marks.isEmpty) return base;

    // 1. 完整哈希缓存
    final cached = _cache.getFromMarksCache(developKey, marks);
    if (cached != null) return cached;

    // 2. 增量缓存
    final incremental = _cache.getIncremental(developKey, marks);

    ui.Image batchInput;
    int startIdx;
    bool batchInputOwned;

    if (incremental != null) {
      batchInput = incremental.$1;
      startIdx = incremental.$2;
      batchInputOwned = true;
    } else {
      batchInput = base;
      startIdx = 0;
      batchInputOwned = false;
    }

    // 3. 分批渲染剩余 marks
    ui.Image? lastResult;
    for (int i = startIdx; i < marks.length; i += _kMaxMarks) {
      final batch = marks.sublist(i, (i + _kMaxMarks).clamp(0, marks.length));
      try {
        final result = await _runHealingPass(input: batchInput, marks: batch);
        if (batchInputOwned) batchInput.dispose();
        batchInput = result;
        batchInputOwned = true;
        lastResult = result;
      } catch (e) {
        if (batchInputOwned) batchInput.dispose();
        debugPrint('[HealingLayer] Batch render failed: $e');
        rethrow;
      }
    }

    // 4. 更新缓存
    if (lastResult != null) {
      _cache.putMarksCache(developKey, marks, lastResult);
      _cache.putRolling(developKey, marks.length, lastResult);
    }

    return batchInput;
  }

  Future<ui.Image> _runHealingPass({
    required ui.Image input,
    required List<HealingMark> marks,
  }) async {
    final w = input.width;
    final h = input.height;
    final count = marks.length.clamp(0, _kMaxMarks);

    final markTex = await encodeMarksToTexture(
      count: count,
      maxSpots: _kMaxMarks,
      getMarkFloats: (i) => [
        marks[i].source.dx,
        marks[i].source.dy,
        marks[i].target.dx,
        marks[i].target.dy,
        marks[i].radius,
        marks[i].hardness,
      ],
    );

    try {
      return await runSingleShaderPass(
        shader: brushShader,
        outputWidth: w,
        outputHeight: h,
        samplers: [input, markTex],
        setUniforms: (s) {
          s.setFloat(0, w.toDouble());
          s.setFloat(1, h.toDouble());
          s.setFloat(2, count.toDouble());
          s.setFloat(3, markTex.width.toDouble());
        },
      );
    } finally {
      markTex.dispose();
    }
  }

  @override
  Future<void> warmup(
    ui.Image developOutput,
    int targetWidth,
    int targetHeight,
  ) async {
    // 用 _kMaxMarks 个 dummy mark 跑一次 shader pass，触发 GPU PSO 创建
    final dummies = List.generate(
      _kMaxMarks,
      (i) => HealingMark(
        source: const ui.Offset(0.0, 0.0),
        target: ui.Offset(i * 0.0001, i * 0.0001),
        radius: 0.0001,
        hardness: 1.0,
      ),
    );
    try {
      final result = await _runHealingPass(
        input: developOutput,
        marks: dummies,
      );
      result.dispose();
    } catch (e) {
      debugPrint('[Warmup] healing FAILED: $e');
    }
  }

  @override
  void invalidate() => _cache.invalidate();

  @override
  void dispose() => _cache.dispose();
}
