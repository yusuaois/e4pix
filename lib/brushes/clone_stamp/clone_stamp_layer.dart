import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/brush_layer.dart';
import 'clone_stamp_model.dart';
import '../../render/brush_layer_provider.dart';
import '../../render/incremental_render_cache.dart';
import '../shared/brush_hashes.dart';
import '../shared/brush_layer_mixin.dart';
import '../shared/spot_data_texture.dart';
import '../../utils/brush_preview_utils.dart';
import '../../utils/shader_pass_util.dart';

/// 图章笔刷输出层
///
/// 将 spots 渲染到 develop 输出上，返回 [BrushLayer]
/// 其 alpha 通道标记被修改的像素（1=已修改，0=未修改）
/// Compose pass 用此 alpha 遮罩将输出层混合到基底图像
class SpotRemovalLayerProvider
    with ShaderCacheMixin
    implements BrushLayerProvider {
  @override
  String get id => 'spot_removal';

  final _cache = IncrementalRenderCache<SpotMark>(computeKey: hashSpots);
  @override
  final ui.FragmentProgram brushProgram;

  SpotRemovalLayerProvider({required ui.FragmentProgram program})
    : brushProgram = program;

  static const _kMaxSpots = 128;
  // uniform 总数：3（uSize + uSpotCount），spot 数据通过 uSpotData 纹理传入

  @override
  bool isActive(AdjustmentParams params) =>
      (params.brushMarks['spot_removal']?.isNotEmpty ?? false);

  @override
  int computeMarksHash(AdjustmentParams params) => hashSpots(
    params.brushMarks['spot_removal']?.cast<SpotMark>() ?? const [],
  );

  @override
  Future<BrushLayer> render({
    required AdjustmentParams params,
    required ui.Image developOutput,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final spots =
        (params.brushMarks['spot_removal']?.cast<SpotMark>() ?? const []).where(
          (s) {
            return !isMarkSourceFullyOOB(
              sourceX: s.source.dx,
              sourceY: s.source.dy,
              radius: s.radius,
              imageWidth: developOutput.width.toDouble(),
              imageHeight: developOutput.height.toDouble(),
            );
          },
        ).toList();

    if (spots.isEmpty) {
      return BrushLayer(id: id, active: false);
    }

    final texture = await _renderSpots(
      base: developOutput,
      spots: spots,
      developKey: developKey,
    );

    return BrushLayer(id: id, texture: texture, active: true);
  }

  /// 将 spots 渲染到 [base] 上，返回新纹理
  Future<ui.Image> _renderSpots({
    required ui.Image base,
    required List<SpotMark> spots,
    required int developKey,
  }) async {
    if (spots.isEmpty) return base;

    // 1. 完整哈希缓存
    final cached = _cache.getFromMarksCache(developKey, spots);
    if (cached != null) return cached;

    // 2. 增量缓存
    final incremental = _cache.getIncremental(developKey, spots);

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

    // 3. 分批渲染剩余 spots
    ui.Image? lastResult;
    for (int i = startIdx; i < spots.length; i += _kMaxSpots) {
      final batch = spots.sublist(i, (i + _kMaxSpots).clamp(0, spots.length));
      try {
        final result = await _runSpotRemovePass(
          input: batchInput,
          spots: batch,
        );
        if (batchInputOwned) batchInput.dispose();
        batchInput = result;
        batchInputOwned = true;
        lastResult = result;
      } catch (e) {
        if (batchInputOwned) batchInput.dispose();
        debugPrint('[SpotRemovalLayer] Batch render failed: $e');
        rethrow;
      }
    }

    // 4. 更新缓存
    if (lastResult != null) {
      _cache.putMarksCache(developKey, spots, lastResult);
      _cache.putRolling(developKey, spots.length, lastResult);
    }

    return batchInput;
  }

  Future<ui.Image> _runSpotRemovePass({
    required ui.Image input,
    required List<SpotMark> spots,
  }) async {
    final w = input.width;
    final h = input.height;
    final count = spots.length.clamp(0, _kMaxSpots);

    final spotTex = await encodeMarksToTexture(
      count: count,
      maxSpots: _kMaxSpots,
      getMarkFloats: (i) => [
        spots[i].source.dx,
        spots[i].source.dy,
        spots[i].target.dx,
        spots[i].target.dy,
        spots[i].radius,
        spots[i].hardness,
      ],
    );

    try {
      return await runSingleShaderPass(
        shader: brushShader,
        outputWidth: w,
        outputHeight: h,
        samplers: [input, spotTex],
        setUniforms: (s) {
          s.setFloat(0, w.toDouble());
          s.setFloat(1, h.toDouble());
          s.setFloat(2, count.toDouble());
          s.setFloat(3, spotTex.width.toDouble());
        },
      );
    } finally {
      spotTex.dispose();
    }
  }

  @override
  Future<void> warmup(
    ui.Image developOutput,
    int targetWidth,
    int targetHeight,
  ) async {
    // 用 _kMaxSpots 个 dummy mark 跑一次 shader pass，触发 GPU PSO 创建
    final dummies = List.generate(
      _kMaxSpots,
      (i) => SpotMark(
        source: const ui.Offset(0.0, 0.0),
        target: ui.Offset(i * 0.0001, i * 0.0001),
        radius: 0.0001,
        hardness: 1.0,
      ),
    );
    try {
      final result = await _runSpotRemovePass(
        input: developOutput,
        spots: dummies,
      );
      result.dispose();
    } catch (e) {
      debugPrint('[Warmup] clone_stamp FAILED: $e');
    }
  }

  @override
  void invalidate() => _cache.invalidate();

  @override
  void dispose() => _cache.dispose();
}
