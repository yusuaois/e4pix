import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/brush_layer.dart';
import '../../core/models/mask_shape.dart';
import 'sponge_model.dart';
import '../../render/brush_layer_provider.dart';
import '../../render/brush_rasterizer.dart';
import '../../render/incremental_render_cache.dart';
import '../shared/brush_hashes.dart';
import '../shared/brush_layer_mixin.dart';
import '../shared/brush_warmup_utils.dart';
import '../../utils/shader_pass_util.dart';

/// 海绵工具输出层
///
/// 每个 mark 冻结绘制时的渲染参数（模式/流量）
/// marks 按 (mode, flow) 分组，分 pass 渲染
/// 后续组叠加在先前组之上
class SpongeLayerProvider with ShaderCacheMixin implements BrushLayerProvider {
  @override
  String get id => 'sponge';

  final _cache = IncrementalRenderCache<SpongeMark>(
    computeKey: hashSpongeMarks,
  );
  @override
  final ui.FragmentProgram brushProgram;

  SpongeLayerProvider({required ui.FragmentProgram program})
    : brushProgram = program;

  @override
  bool isActive(AdjustmentParams params) => params.spongeMarks.isNotEmpty;

  @override
  int computeMarksHash(AdjustmentParams params) =>
      hashSpongeMarks(params.spongeMarks);

  @override
  Future<BrushLayer> render({
    required AdjustmentParams params,
    required ui.Image developOutput,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final marks = params.spongeMarks;
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

  /// mark 渲染参数的整数分组键
  /// flow 量化到 1%（与 UI 滑块步进一致，避免 JSON 反序列化浮点差异导致冗余分组）
  static int _groupKey(SpongeMark m) =>
      Object.hash(m.mode.index, (m.flow * 100).round());

  Future<ui.Image> _renderMask({
    required ui.Image base,
    required List<SpongeMark> marks,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final cached = _cache.getFromMarksCache(developKey, marks);
    if (cached != null) return cached;

    // 按 (mode, flow) 分组 marks
    final groups = <int, List<SpongeMark>>{};
    for (final m in marks) {
      groups.putIfAbsent(_groupKey(m), () => []).add(m);
    }

    // 逐组渲染并链式叠加
    ui.Image current = base;

    for (final entry in groups.entries) {
      final groupMarks = entry.value;
      final first = groupMarks.first;

      final strokes = groupMarks.map((m) {
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

      final modeVal = first.mode == SpongeMode.saturate ? 0.0 : 1.0;

      final groupResult = await runSingleShaderPass(
        shader: brushShader,
        outputWidth: targetWidth,
        outputHeight: targetHeight,
        samplers: [current, maskTex],
        setUniforms: (s) {
          s.setFloat(0, targetWidth.toDouble());
          s.setFloat(1, targetHeight.toDouble());
          s.setFloat(2, modeVal);
          s.setFloat(3, first.flow);
        },
      );

      maskTex.dispose();

      if (current != base) current.dispose();
      current = groupResult;
    }

    _cache.putMarksCache(developKey, marks, current);

    return current;
  }

  @override
  Future<void> warmup(
    ui.Image developOutput,
    int targetWidth,
    int targetHeight,
  ) async {
    final emptyMask = await createEmptyMask();
    try {
      final result = await runSingleShaderPass(
        shader: brushShader,
        outputWidth: targetWidth,
        outputHeight: targetHeight,
        samplers: [developOutput, emptyMask],
        setUniforms: (s) {
          s.setFloat(0, targetWidth.toDouble());
          s.setFloat(1, targetHeight.toDouble());
          s.setFloat(2, 0.0); // 饱和
          s.setFloat(3, 0.5); // 流量
        },
      );
      result.dispose();
    } catch (e) {
      debugPrint('[Warmup] sponge FAILED: $e');
    }
    emptyMask.dispose();
  }

  @override
  void invalidate() => _cache.invalidate();

  @override
  void dispose() => _cache.dispose();
}
