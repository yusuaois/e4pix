import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/brush_layer.dart';
import '../../core/models/mask_shape.dart';
import 'dodge_burn_model.dart';
import '../../render/brush_layer_provider.dart';
import '../../render/brush_rasterizer.dart';
import '../../render/incremental_render_cache.dart';
import 'dodge_burn_cache.dart';
import '../../utils/shader_pass_util.dart';

/// Dodge/Burn brush layer — tonal range targeted lighten/darken.
///
/// Each mark stores its own rendering params (mode/range/exposure),
/// frozen at paint time. Marks are grouped by (mode, range, exposure)
/// and rendered in separate shader passes, chained so that later
/// groups layer on top of earlier ones.
class DodgeBurnLayerProvider implements BrushLayerProvider {
  @override
  String get id => 'dodge_burn';

  final _cache = IncrementalRenderCache<DodgeBurnMark>(
    computeKey: hashDodgeBurnMarks,
  );
  final ui.FragmentProgram _program;
  ui.FragmentShader? _cachedShader;

  DodgeBurnLayerProvider({required ui.FragmentProgram program})
    : _program = program;

  ui.FragmentShader get _shader => _cachedShader ??= _program.fragmentShader();

  @override
  bool isActive(AdjustmentParams params) => params.dodgeBurnMarks.isNotEmpty;

  /// Marks hash now includes per-mark mode/range/exposure, so switching
  /// tool params does not change this hash — only painting new marks does.
  @override
  int computeMarksHash(AdjustmentParams params) =>
      hashDodgeBurnMarks(params.dodgeBurnMarks);

  @override
  Future<BrushLayer> render({
    required AdjustmentParams params,
    required ui.Image developOutput,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final marks = params.dodgeBurnMarks;
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

  /// Integer group key for a mark's rendering params.
  static int _groupKey(DodgeBurnMark m) =>
      Object.hash(m.mode.index, m.range.index, (m.exposure * 1000).round());

  Future<ui.Image> _renderMask({
    required ui.Image base,
    required List<DodgeBurnMark> marks,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    // 1. Cache check — marks hash now includes per-mark params,
    //    so changing tool settings no longer invalidates the cache.
    final cached = _cache.getFromMarksCache(developKey, marks);
    if (cached != null) return cached;

    // 2. Group marks by (mode, range, exposure)
    final groups = <int, List<DodgeBurnMark>>{};
    for (final m in marks) {
      groups.putIfAbsent(_groupKey(m), () => []).add(m);
    }

    // 3. Render each group, chaining outputs
    //    Group N+1 renders on top of group N's result.
    //    Dispose intermediate images promptly to avoid GPU memory bloat.
    ui.Image current = base;

    for (final entry in groups.entries) {
      final groupMarks = entry.value;
      final first = groupMarks.first;

      // Rasterize this group's marks to a feathered mask
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
        shader: _shader,
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

      // Dispose previous intermediate before advancing
      // (base is owned by the caller — never dispose it)
      if (current != base) current.dispose();
      current = groupResult;
    }

    // 4. Cache
    _cache.putMarksCache(developKey, marks, current);

    return current;
  }

  @override
  Future<void> warmup(
    ui.Image developOutput,
    int targetWidth,
    int targetHeight,
  ) async {
    final emptyMask = await _createEmptyMask();
    try {
      final result = await runSingleShaderPass(
        shader: _shader,
        outputWidth: targetWidth,
        outputHeight: targetHeight,
        samplers: [developOutput, emptyMask],
        setUniforms: (s) {
          s.setFloat(0, targetWidth.toDouble());
          s.setFloat(1, targetHeight.toDouble());
          s.setFloat(2, 0.0); // dodge
          s.setFloat(3, 0.5); // exposure
          s.setFloat(4, 0.5); // midtones
        },
      );
      result.dispose();
    } catch (e) {
      debugPrint('[Warmup] dodge_burn FAILED: $e');
    }
    emptyMask.dispose();
  }

  Future<ui.Image> _createEmptyMask() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()..color = const ui.Color(0x00000000),
    );
    final picture = recorder.endRecording();
    return picture.toImage(1, 1);
  }

  @override
  void invalidate() => _cache.invalidate();

  @override
  void dispose() => _cache.dispose();
}
