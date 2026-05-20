import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/models/adjustment_params.dart';
import '../core/models/crop_params.dart';
import '../core/models/local_adjustment.dart';
import '../core/models/mask_shape.dart';
import 'crop_transform.dart';
import 'mask_cache.dart';
import 'render_engine.dart';

class FullPipelineRenderer {
  // 非 brush mask pass 绑定的 1x1 dummy
  static ui.Image? _dummyMask;

  static Future<ui.Image> _getDummyMask() async {
    if (_dummyMask != null) return _dummyMask!;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
    final pic = recorder.endRecording();
    _dummyMask = await pic.toImage(1, 1);
    pic.dispose();
    return _dummyMask!;
  }

  /// global develop → crop → 所有 local 返回的 ui.Image 已含所有变换
  static Future<ui.Image> render({
    required ui.FragmentProgram developProgram,
    required ui.FragmentProgram maskProgram,
    required ui.Image sourceImage,
    required AdjustmentParams params,
    ui.Image? lutTexture,
    int lutSize = 0,
    required int targetWidth,
    required int targetHeight,
    DevelopPassCache? developCache,
    BrushMaskCache? brushCache,
  }) async {
    final enabledLocals = params.locals
        .where((l) => l.enabled && !l.params.isNeutral)
        .toList();
    final hasEnabledMasks = enabledLocals.isNotEmpty;
    final useCache = developCache != null && hasEnabledMasks;

    // Pass 0: global develop
    ui.Image develop;
    bool developOwned;
    if (useCache) {
      final key = (
        identityHashCode(sourceImage),
        params.copyWith(crop: CropParams.identity, locals: const []),
        identityHashCode(lutTexture),
        lutSize,
        targetWidth,
        targetHeight,
      );
      develop = await developCache.getOrCompute(
        key,
        () => RenderEngine.renderToImage(
          program: developProgram,
          sourceImage: sourceImage,
          params: params,
          lutTexture: lutTexture,
          lutSize: lutSize,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        ),
      );
      developOwned = false; // 缓存持有
    } else {
      develop = await RenderEngine.renderToImage(
        program: developProgram,
        sourceImage: sourceImage,
        params: params,
        lutTexture: lutTexture,
        lutSize: lutSize,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      developOwned = true;
    }

    ui.Image current = develop;
    bool currentOwned = developOwned;

    // crop
    if (!params.crop.isIdentity) {
      try {
        final cropped = await applyCropTransform(current, params.crop);
        if (currentOwned) current.dispose();
        current = cropped;
        currentOwned = true;
      } catch (e) {
        debugPrint('Crop transform failed: $e');
      }
    }

    // mask passes
    for (final local in enabledLocals) {
      try {
        final shape = local.mask;
        ui.Image maskTex;
        bool maskTexOwned = false;

        if (shape is BrushMask) {
          if (brushCache != null) {
            maskTex = await brushCache.getOrRasterize(
              local.id,
              shape,
              current.width,
              current.height,
            );
            maskTexOwned = false;
          } else {
            maskTex = await rasterizeBrushMask(
              shape,
              current.width,
              current.height,
            );
            maskTexOwned = true;
          }
        } else {
          maskTex = await _getDummyMask();
          maskTexOwned = false;
        }

        final next = await _runMaskPass(
          program: maskProgram,
          input: current,
          local: local,
          maskTexture: maskTex,
        );
        if (currentOwned) current.dispose();
        current = next;
        currentOwned = true;
        if (maskTexOwned) maskTex.dispose();
      } catch (e) {
        debugPrint('Mask pass failed for ${local.id}: $e');
      }
    }

    if (!currentOwned) {
      return _copyImage(current);
    }

    return current;
  }

  static Future<ui.Image> _copyImage(ui.Image src) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(src, ui.Offset.zero, ui.Paint());
    final pic = recorder.endRecording();
    final out = await pic.toImage(src.width, src.height);
    pic.dispose();
    return out;
  }

  static Future<ui.Image> _runMaskPass({
    required ui.FragmentProgram program,
    required ui.Image input,
    required LocalAdjustment local,
    required ui.Image maskTexture,
  }) async {
    final shader = program.fragmentShader();
    final w = input.width;
    final h = input.height;

    _setMaskUniforms(shader, local, w.toDouble(), h.toDouble());
    shader.setImageSampler(0, input);
    shader.setImageSampler(1, maskTexture);

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

    // uMaskType: 0=linear, 1=radial, 2=brush
    final double maskType;
    if (mask is LinearGradientMask) {
      maskType = 0.0;
    } else if (mask is RadialGradientMask) {
      maskType = 1.0;
    } else {
      maskType = 2.0;
    }
    shader.setFloat(i++, maskType);

    // Linear params
    if (mask is LinearGradientMask) {
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

    // Radial params
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
