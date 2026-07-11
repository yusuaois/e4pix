import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/brush_layer.dart';
import '../../core/models/mask_shape.dart';
import 'dodge_burn_model.dart';
import '../../render/brush_layer_provider.dart';
import '../../render/brush_rasterizer.dart';
import '../../render/incremental_render_cache.dart';
import '../shared/brush_hashes.dart';
import '../shared/brush_layer_mixin.dart';
import '../shared/brush_warmup_utils.dart';
import '../../utils/shader_pass_util.dart';

/// 加深减淡笔刷输出层
///
/// 每个 mark 冻结绘制时的渲染参数（模式/范围/曝光）
/// marks 按 (mode, range, exposure) 分组，分 pass 渲染
/// 后续组叠加在先前组之上
class DodgeBurnLayerProvider
    with ShaderCacheMixin
    implements BrushLayerProvider {
  @override
  String get id => 'dodge_burn';

  final _cache = IncrementalRenderCache<DodgeBurnMark>(
    computeKey: hashDodgeBurnMarks,
  );
  @override
  final ui.FragmentProgram brushProgram;

  DodgeBurnLayerProvider({required ui.FragmentProgram program})
    : brushProgram = program;

  @override
  bool isActive(AdjustmentParams params) =>
      (params.brushMarks['dodge_burn']?.isNotEmpty ?? false);

  /// marks 哈希已包含每个 mark 的 mode/range/exposure
  /// 切换工具参数不改变哈希，仅绘制新 mark 才会
  @override
  int computeMarksHash(AdjustmentParams params) => hashDodgeBurnMarks(
    params.brushMarks['dodge_burn']?.cast<DodgeBurnMark>() ?? const [],
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
        params.brushMarks['dodge_burn']?.cast<DodgeBurnMark>() ?? const [];
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
  static int _groupKey(DodgeBurnMark m) =>
      Object.hash(m.mode.index, m.range.index, (m.exposure * 1000).round());

  Future<ui.Image> _renderMask({
    required ui.Image base,
    required List<DodgeBurnMark> marks,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    // 1. 缓存检查 — marks 哈希已包含 per-mark 参数
    //    切换工具设置不再使缓存失效
    final cached = _cache.getFromMarksCache(developKey, marks);
    if (cached != null) return cached;

    // 2. 按 (mode, range, exposure) 分组 marks
    final groups = <int, List<DodgeBurnMark>>{};
    for (final m in marks) {
      groups.putIfAbsent(_groupKey(m), () => []).add(m);
    }

    // 3. 逐组渲染并链式叠加，及时释放中间纹理避免 GPU 内存膨胀
    ui.Image current = base;

    for (final entry in groups.entries) {
      final groupMarks = entry.value;
      final first = groupMarks.first;

      // 将本组 marks 光栅化为羽化遮罩
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

      final modeVal = first.mode == DodgeBurnMode.dodge ? 0.0 : 1.0;
      final rangeVal = first.range == DodgeBurnRange.shadows
          ? 0.0
          : first.range == DodgeBurnRange.midtones
          ? 0.5
          : 1.0;

      final groupResult = await runSingleShaderPass(
        shader: brushShader,
        outputWidth: targetWidth,
        outputHeight: targetHeight,
        samplers: [current, maskTex],
        setUniforms: (s) {
          s.setFloat(0, targetWidth.toDouble());
          s.setFloat(1, targetHeight.toDouble());
          s.setFloat(2, modeVal);
          s.setFloat(3, first.exposure);
          s.setFloat(4, rangeVal);
        },
      );

      maskTex.dispose();

      // 前进前释放上一个中间结果（base 由调用方持有，不释放）
      if (current != base) current.dispose();
      current = groupResult;
    }

    // 4. 缓存
    _cache.putMarksCache(developKey, marks, current);

    return current;
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
          s.setFloat(2, 0.0); // 减淡
          s.setFloat(3, 0.5); // 曝光
          s.setFloat(4, 0.5); // 中间调
        },
      );
      result.dispose();
    } catch (e) {
      debugPrint('[Warmup] dodge_burn FAILED: $e');
    }
    warmupMask.dispose();
  }

  @override
  void invalidate() => _cache.invalidate();

  @override
  void dispose() => _cache.dispose();
}
