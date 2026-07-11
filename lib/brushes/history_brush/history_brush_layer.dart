import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/brush_layer.dart';
import '../../render/brush_layer_provider.dart';
import '../../render/incremental_render_cache.dart';
import '../../state/params/history_panel_state.dart';
import '../shared/brush_hashes.dart';
import '../shared/brush_layer_mixin.dart';
import '../shared/stamp/spot_data_texture.dart';
import '../../utils/shader_pass_util.dart';
import 'history_brush_model.dart';

class HistoryBrushLayerProvider
    with ShaderCacheMixin
    implements BrushLayerProvider {
  @override
  String get id => 'history_brush';

  final _cache = IncrementalRenderCache<HistoryMark>(
    computeKey: hashHistoryMarks,
  );
  @override
  final ui.FragmentProgram brushProgram;

  HistoryBrushLayerProvider({required ui.FragmentProgram program})
    : brushProgram = program;

  static const _kMaxSpots = 128;

  @override
  bool isActive(AdjustmentParams params) =>
      (params.brushMarks['history_brush']?.isNotEmpty ?? false);

  @override
  int computeMarksHash(AdjustmentParams params) => hashHistoryMarks(
    params.brushMarks['history_brush']?.cast<HistoryMark>() ?? const [],
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
        params.brushMarks['history_brush']?.cast<HistoryMark>() ?? const [];
    if (marks.isEmpty) {
      return BrushLayer(id: id, active: false);
    }

    // 读取 history snapshot（全局 ValueNotifier）
    final historySnapshot = historyBrushSnapshot.value;
    if (historySnapshot == null) {
      return BrushLayer(id: id, active: false);
    }

    final texture = await _renderMarks(
      base: developOutput,
      historySrc: historySnapshot,
      marks: marks,
      developKey: developKey,
    );

    return BrushLayer(id: id, texture: texture, active: true);
  }

  Future<ui.Image> _renderMarks({
    required ui.Image base,
    required ui.Image historySrc,
    required List<HistoryMark> marks,
    required int developKey,
  }) async {
    if (marks.isEmpty) return base;

    final cached = _cache.getFromMarksCache(developKey, marks);
    if (cached != null) return cached;

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

    ui.Image? lastResult;
    for (int i = startIdx; i < marks.length; i += _kMaxSpots) {
      final batch = marks.sublist(i, (i + _kMaxSpots).clamp(0, marks.length));
      try {
        final result = await _runHistoryPass(
          input: batchInput,
          historySrc: historySrc,
          marks: batch,
        );
        if (batchInputOwned) batchInput.dispose();
        batchInput = result;
        batchInputOwned = true;
        lastResult = result;
      } catch (e) {
        if (batchInputOwned) batchInput.dispose();
        debugPrint('[HistoryBrushLayer] Batch render failed: $e');
        rethrow;
      }
    }

    if (lastResult != null) {
      _cache.putMarksCache(developKey, marks, lastResult);
      _cache.putRolling(developKey, marks.length, lastResult);
    }

    return batchInput;
  }

  Future<ui.Image> _runHistoryPass({
    required ui.Image input,
    required ui.Image historySrc,
    required List<HistoryMark> marks,
  }) async {
    final w = input.width;
    final h = input.height;
    final count = marks.length.clamp(0, _kMaxSpots);

    final spotTex = await encodeMarksToTexture(
      count: count,
      maxSpots: _kMaxSpots,
      getMarkFloats: (i) => [
        marks[i].target.dx,
        marks[i].target.dy,
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
        samplers: [input, historySrc, spotTex],
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
    // History Brush needs a history snapshot for warmup — skip if none
    final historySrc = historyBrushSnapshot.value;
    if (historySrc == null) return;

    final dummies = List.generate(
      _kMaxSpots,
      (i) => HistoryMark(
        target: ui.Offset(i * 0.0001, i * 0.0001),
        radius: 0.0001,
        hardness: 1.0,
      ),
    );
    try {
      final result = await _runHistoryPass(
        input: developOutput,
        historySrc: historySrc,
        marks: dummies,
      );
      result.dispose();
    } catch (e) {
      debugPrint('[Warmup] history_brush FAILED: $e');
    }
  }

  @override
  void invalidate() => _cache.invalidate();

  @override
  void dispose() => _cache.dispose();
}
