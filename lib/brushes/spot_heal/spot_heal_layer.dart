import 'dart:ui' as ui;

import '../../core/models/adjustment_params.dart';
import '../../core/models/brush_layer.dart';
import '../../core/models/mask_shape.dart';
import 'spot_heal_model.dart';
import '../../render/brush_layer_provider.dart';
import '../../render/brush_rasterizer.dart';
import 'spot_heal_cache.dart';
import '../../utils/shader_pass_util.dart';

/// Spot Heal brush layer — mask-based fill from boundary.
///
/// Converts brush marks to a binary mask via [rasterizeBrushMask],
/// then the shader fills the mask region by sampling boundary pixels
/// along 16 ray directions with IDW blending.
class SpotHealLayerProvider implements BrushLayerProvider {
  @override
  String get id => 'spot_heal';

  final SpotHealCache _cache = SpotHealCache();
  final ui.FragmentProgram _program;

  SpotHealLayerProvider({required ui.FragmentProgram program})
    : _program = program;

  @override
  bool isActive(AdjustmentParams params) => params.spotHealMarks.isNotEmpty;

  @override
  Future<BrushLayer> render({
    required AdjustmentParams params,
    required ui.Image developOutput,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final marks = params.spotHealMarks;
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
    // 1. Cache check
    final cached = _cache.getFromMarksCache(developKey, marks);
    if (cached != null) return cached;

    // 2. Convert marks to brush strokes and rasterize mask
    // Each mark becomes a single-point stroke with its radius.
    // Clamp radius to at most 0.5 to avoid unreasonable GPU cost.
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

    // 3. Shader pass: fill mask region from boundary
    final avgHardness = marks.isEmpty
        ? 0.0
        : marks.map((m) => m.hardness).reduce((a, b) => a + b) / marks.length;

    final result = await runSingleShaderPass(
      shader: _program.fragmentShader(),
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

    // 4. Update cache
    _cache.putMarksCache(developKey, marks, result);
    _cache.putRolling(developKey, marks.length, result);

    return result;
  }

  @override
  void invalidate() => _cache.invalidate();

  @override
  void dispose() => _cache.dispose();
}
