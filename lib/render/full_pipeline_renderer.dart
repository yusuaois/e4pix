import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/models/adjustment_params.dart';
import '../core/models/local_adjustment.dart';
import '../core/models/mask_shape.dart';
import 'crop_transform.dart';
import 'render_engine.dart';

class FullPipelineRenderer {
  /// global develop → crop → 所有 local
  /// ui.Image 已经包含所有变换
  static Future<ui.Image> render({
    required ui.FragmentProgram developProgram,
    required ui.FragmentProgram maskProgram,
    required ui.Image sourceImage,
    required AdjustmentParams params,
    ui.Image? lutTexture,
    int lutSize = 0,
    required int targetWidth,
    required int targetHeight,
  }) async {
    // global develop ─
    ui.Image current = await RenderEngine.renderToImage(
      program: developProgram,
      sourceImage: sourceImage,
      params: params,
      lutTexture: lutTexture,
      lutSize: lutSize,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );

    // 应用 crop
    if (!params.crop.isIdentity) {
      try {
        final cropped = await applyCropTransform(current, params.crop);
        current.dispose();
        current = cropped;
      } catch (e) {
        debugPrint('Crop transform failed: $e');
      }
    }

    // Mask passes
    for (final local in params.locals) {
      if (!local.enabled || local.params.isNeutral) continue;
      try {
        final next = await _runMaskPass(
          program: maskProgram,
          input: current,
          local: local,
        );
        current.dispose();
        current = next;
      } catch (e) {
        debugPrint('Mask pass failed for ${local.id}: $e');
      }
    }

    return current;
  }

  static Future<ui.Image> _runMaskPass({
    required ui.FragmentProgram program,
    required ui.Image input,
    required LocalAdjustment local,
  }) async {
    final shader = program.fragmentShader();
    final w = input.width;
    final h = input.height;

    _setMaskUniforms(shader, local, w.toDouble(), h.toDouble());
    shader.setImageSampler(0, input);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..shader = shader,
    );
    final picture = recorder.endRecording();
    final result = await picture.toImage(w, h);
    picture.dispose();
    return result;
  }

  static void _setMaskUniforms(
    ui.FragmentShader shader,
    LocalAdjustment local,
    double resW,
    double resH,
  ) {
    int i = 0;

    // uResolution (vec2)
    shader.setFloat(i++, resW);
    shader.setFloat(i++, resH);

    final mask = local.mask;
    final isLinear = mask is LinearGradientMask;

    // uMaskType
    shader.setFloat(i++, isLinear ? 0.0 : 1.0);

    // Linear params (Start XY / End XY)
    if (isLinear) {
      shader.setFloat(i++, mask.startX);
      shader.setFloat(i++, mask.startY);
      shader.setFloat(i++, mask.endX);
      shader.setFloat(i++, mask.endY);
    } else {
      shader.setFloat(i++, 0.0);
      shader.setFloat(i++, 0.0);
      shader.setFloat(i++, 0.0);
      shader.setFloat(i++, 0.0);
    }

    // Radial params (Center XY / Radius XY / Rotation / Feather / Inverted)
    if (mask is RadialGradientMask) {
      shader.setFloat(i++, mask.centerX);
      shader.setFloat(i++, mask.centerY);
      shader.setFloat(i++, mask.radiusX);
      shader.setFloat(i++, mask.radiusY);
      shader.setFloat(i++, mask.rotation);
      shader.setFloat(i++, mask.feather);
      shader.setFloat(i++, mask.inverted ? 1.0 : 0.0);
    } else {
      shader.setFloat(i++, 0.5);
      shader.setFloat(i++, 0.5);
      shader.setFloat(i++, 0.5);
      shader.setFloat(i++, 0.5);
      shader.setFloat(i++, 0.0);
      shader.setFloat(i++, 0.5);
      shader.setFloat(i++, 0.0);
    }

    // Local params
    final p = local.params;
    shader.setFloat(i++, p.exposure);
    shader.setFloat(i++, p.contrast);
    shader.setFloat(i++, p.highlights);
    shader.setFloat(i++, p.shadows);
    shader.setFloat(i++, p.whites);
    shader.setFloat(i++, p.blacks);
    shader.setFloat(i++, p.temperatureShift.toDouble());
    shader.setFloat(i++, p.tint);
    shader.setFloat(i++, p.saturation);
    shader.setFloat(i++, p.vibrance);
  }
}