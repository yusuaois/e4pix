import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/models/adjustment_params.dart';
import '../core/models/local_adjustment.dart';
import '../core/models/mask_shape.dart';
import 'brush_rasterizer.dart';
import 'crop_transform.dart';
import 'homography.dart';
import 'mask_cache.dart';
import 'render_engine.dart';
import '../utils/shader_pass_util.dart';

class FullPipelineRenderer {
  // 非 brush mask pass 绑定的 1x1 dummy
  static ui.Image? _dummyMask;

  /// 提取影响 develop pass 的参数指纹
  static (int, int, int, int) _developFingerprint({
    required AdjustmentParams p,
    required ui.Image sourceImage,
    ui.Image? lutTexture,
    int lutSize = 0,
    ui.Image? lutTextureB,
    int lutSizeB = 0,
    ui.Image? curveTexture,
    required int targetWidth,
    required int targetHeight,
  }) {
    final h = p.hsl;
    final g = p.grain;
    final bodyHash = Object.hashAll([
      p.exposure,
      p.temperature,
      p.tint,
      p.contrast,
      p.highlights,
      p.shadows,
      p.whites,
      p.blacks,
      p.saturation,
      p.vibrance,
      Object.hashAll(h.hues),
      Object.hashAll(h.sats),
      Object.hashAll(h.lums),
      p.lutIntensity,
      p.lutIntensityB,
      identityHashCode(lutTexture),
      lutSize,
      identityHashCode(lutTextureB),
      lutSizeB,
      identityHashCode(curveTexture),
      g.amount,
      g.size,
      g.shadowThreshold,
      g.highlightThreshold,
      g.shadowStrength,
      g.highlightStrength,
      g.shadowSize,
      g.highlightSize,
      g.redRatio,
      g.blueRatio,
      g.correlation,
      g.colorPreservation,
      p.lensCorrection.enabled,
      p.lensCorrection.caRed,
      p.lensCorrection.caBlue,
      p.lensCorrection.distortionEnabled,
      p.lensCorrection.distortionK1,
      p.lensCorrection.distortionK2,
      p.lensCorrection.distortionK3,
      p.lensCorrection.vignettingEnabled,
      p.lensCorrection.vignettingK1,
      p.lensCorrection.vignettingK2,
      p.lensCorrection.vignettingK3,
    ]);

    return (bodyHash, identityHashCode(sourceImage), targetWidth, targetHeight);
  }

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
    ui.FragmentProgram? sharpenProgram,
    ui.FragmentProgram? denoiseProgram,
    ui.FragmentProgram? perspectiveProgram,
    ui.FragmentProgram? lensCorrectProgram,
    PerspectiveMatrixCache? perspectiveCache,
    required ui.Image sourceImage,
    required AdjustmentParams params,
    ui.Image? lutTexture,
    int lutSize = 0,
    ui.Image? lutTextureB,
    int lutSizeB = 0,
    ui.Image? curveTexture,
    required int targetWidth,
    required int targetHeight,
    DevelopPassCache? developCache,
    BrushMaskCache? brushCache,
    bool allowStaleAutoMask = false,
  }) async {
    final enabledLocals = params.locals
        .where((l) => l.enabled && !l.params.isNeutral)
        .toList();
    final hasEnabledMasks = enabledLocals.isNotEmpty;
    final useCache = developCache != null && hasEnabledMasks;

    final devFp = _developFingerprint(
      p: params,
      sourceImage: sourceImage,
      lutTexture: lutTexture,
      lutSize: lutSize,
      lutTextureB: lutTextureB,
      lutSizeB: lutSizeB,
      curveTexture: curveTexture,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );

    // Pass -1: 降噪
    ui.Image developInput = sourceImage;
    bool developInputOwned = false;
    final wantDenoise =
        denoiseProgram != null &&
        (params.denoiseLuma > 0.001 || params.denoiseColor > 0.001);
    if (wantDenoise) {
      try {
        final denoised = await _runDenoisePass(
          program: denoiseProgram,
          input: sourceImage,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
          luma: params.denoiseLuma / 100.0,
          color: params.denoiseColor / 100.0,
        );
        developInput = denoised;
        developInputOwned = true;
      } catch (e) {
        debugPrint('[Pipeline] Denoise pass failed: $e');
        developInput = sourceImage;
        developInputOwned = false;
      }
    }

    // Pass 0a: lens correction (distortion + CA + vignetting)
    ui.Image develop;
    bool developOwned;

    final wantLensCorrect =
        lensCorrectProgram != null &&
        (params.lensCorrection.isDistortionActive ||
            params.lensCorrection.isCaActive ||
            params.lensCorrection.isVignettingActive);

    ui.Image developPassInput = developInput;
    bool developPassInputOwned = developInputOwned;

    if (wantLensCorrect) {
      try {
        final corrected = await _runLensCorrectPass(
          program: lensCorrectProgram,
          input: developPassInput,
          params: params,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
        developPassInput = corrected;
        developPassInputOwned = true;
      } catch (e) {
        debugPrint('[Pipeline] Lens correct pass failed: $e');
      }
    }

    // Pass 0: global develop
    if (useCache) {
      develop = await developCache.getOrCompute(
        devFp,
        () => RenderEngine.renderToImage(
          program: developProgram,
          sourceImage: developPassInput,
          params: params,
          lutTexture: lutTexture,
          lutSize: lutSize,
          lutTextureB: lutTextureB,
          lutSizeB: lutSizeB,
          curveTexture: curveTexture,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        ),
      );
      developOwned = false; // 缓存持有
    } else {
      develop = await RenderEngine.renderToImage(
        program: developProgram,
        sourceImage: developPassInput,
        params: params,
        lutTexture: lutTexture,
        lutSize: lutSize,
        lutTextureB: lutTextureB,
        lutSizeB: lutSizeB,
        curveTexture: curveTexture,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      developOwned = true;
    }

    if (developPassInputOwned) {
      developPassInput.dispose();
      developPassInputOwned = false;
    }

    ui.Image current = develop;
    bool currentOwned = developOwned;

    // perspective (after develop, before crop)
    if (!params.perspective.isIdentity && perspectiveProgram != null) {
      try {
        final warped = await _runPerspectivePass(
          program: perspectiveProgram,
          input: current,
          params: params,
          cache: perspectiveCache,
        );
        if (currentOwned) current.dispose();
        current = warped;
        currentOwned = true;
      } catch (e) {
        debugPrint('[Pipeline] Perspective pass failed: $e');
      }
    }

    // crop
    if (!params.crop.isIdentity) {
      try {
        final cropped = await applyCropTransform(current, params.crop);
        if (currentOwned) current.dispose();
        current = cropped;
        currentOwned = true;
      } catch (e) {
        debugPrint('[Pipeline] Crop transform failed: $e');
      }
    }

    // 自动蒙版引导图：develop+crop 输出像素，仅当存在 auto 笔画时读一次
    // 降采样到 ≤512px
    const kMaxGuideEdge = 512;
    Uint8List? guideBytes;
    int guideW = current.width;
    int guideH = current.height;
    int guideEpoch = 0;
    final needGuide = enabledLocals.any((l) {
      final m = l.mask;
      return m is BrushMask && m.strokes.any((s) => s.autoMask);
    });
    if (needGuide) {
      try {
        final longestSide = math.max(current.width, current.height).toDouble();
        late final ui.Image readSrc;
        if (longestSide <= kMaxGuideEdge) {
          readSrc = current;
        } else {
          readSrc = await _downscaleForGuide(current, kMaxGuideEdge);
        }
        try {
          final bd = await readSrc.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          guideBytes = bd?.buffer.asUint8List();
          guideW = readSrc.width;
          guideH = readSrc.height;
          guideEpoch = Object.hash(devFp, params.crop);
        } finally {
          if (longestSide > kMaxGuideEdge) readSrc.dispose();
        }
      } catch (e) {
        debugPrint('[Pipeline] Guide readback failed: $e');
        guideBytes = null;
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
              guideBytes: guideBytes,
              guideWidth: guideW,
              guideHeight: guideH,
              guideEpoch: guideEpoch,
              allowStaleGuide: allowStaleAutoMask,
              crop: params.crop,
              srcW: sourceImage.width,
              srcH: sourceImage.height,
            );
            maskTexOwned = false;
          } else {
            maskTex = await rasterizeBrushMask(
              shape,
              current.width,
              current.height,
              guideBytes: guideBytes,
              guideWidth: guideW,
              guideHeight: guideH,
              crop: params.crop,
              srcW: sourceImage.width,
              srcH: sourceImage.height,
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
        debugPrint('[Pipeline] Mask pass failed for ${local.id}: $e');
      }
    }

    if (sharpenProgram != null && params.sharpenAmount > 0.001) {
      try {
        final sharpened = await _runSharpenPass(
          program: sharpenProgram,
          input: current,
          amount: params.sharpenAmount / 100.0,
          radius: params.sharpenRadius,
          masking: params.sharpenMasking / 100.0,
        );
        if (currentOwned) current.dispose();
        current = sharpened;
        currentOwned = true;
      } catch (e) {
        debugPrint('[Pipeline] Sharpen pass failed: $e');
      }
    }

    if (!currentOwned) return current.clone();
    return current;
  }

  /// 将图片降采样到最长边不超过 [maxEdge] 的版本，用于引导图快速回读
  static Future<ui.Image> _downscaleForGuide(ui.Image src, int maxEdge) async {
    final s = maxEdge / math.max(src.width, src.height);
    final tw = (src.width * s).round();
    final th = (src.height * s).round();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final pic = recorder.endRecording();
    final result = await pic.toImage(tw, th);
    pic.dispose();
    return result;
  }

  static Future<ui.Image> _runDenoisePass({
    required ui.FragmentProgram program,
    required ui.Image input,
    required int targetWidth,
    required int targetHeight,
    required double luma,
    required double color,
  }) async {
    return runSingleShaderPass(
      shader: program.fragmentShader(),
      outputWidth: targetWidth,
      outputHeight: targetHeight,
      samplers: [input],
      setUniforms: (s) {
        int i = 0;
        s.setFloat(i++, targetWidth.toDouble());
        s.setFloat(i++, targetHeight.toDouble());
        s.setFloat(i++, luma);
        s.setFloat(i++, color);
      },
    );
  }

  static Future<ui.Image> _runMaskPass({
    required ui.FragmentProgram program,
    required ui.Image input,
    required LocalAdjustment local,
    required ui.Image maskTexture,
  }) async {
    final w = input.width;
    final h = input.height;
    return runSingleShaderPass(
      shader: program.fragmentShader(),
      outputWidth: w,
      outputHeight: h,
      samplers: [input, maskTexture],
      setUniforms: (s) =>
          _setMaskUniforms(s, local, w.toDouble(), h.toDouble()),
    );
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

    // Debug: 确保 mask uniform 总数与 shader 定义一致（24 个 float）
    assert(i == 24, 'Mask uniform count mismatch: expected 24, got $i');
  }

  static Future<ui.Image> _runLensCorrectPass({
    required ui.FragmentProgram program,
    required ui.Image input,
    required AdjustmentParams params,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final lens = params.lensCorrection;
    return runSingleShaderPass(
      shader: program.fragmentShader(),
      outputWidth: targetWidth,
      outputHeight: targetHeight,
      samplers: [input],
      setUniforms: (s) {
        int i = 0;
        // uK1..uK5
        s.setFloat(i++, lens.distortionEnabled ? lens.distortionK1 : 0.0);
        s.setFloat(i++, lens.distortionEnabled ? lens.distortionK2 : 0.0);
        s.setFloat(i++, lens.distortionEnabled ? lens.distortionK3 : 0.0);
        s.setFloat(i++, lens.distortionEnabled ? lens.distortionK4 : 0.0);
        s.setFloat(i++, lens.distortionEnabled ? lens.distortionK5 : 0.0);
        // uOpticalCenter
        s.setFloat(i++, lens.opticalCenterX);
        s.setFloat(i++, lens.opticalCenterY);
        // uDistortionEnabled
        s.setFloat(i++, lens.distortionEnabled ? 1.0 : 0.0);
        // uCARed, uCABlue
        s.setFloat(i++, lens.enabled ? lens.caRed : 1.0);
        s.setFloat(i++, lens.enabled ? lens.caBlue : 1.0);
        // uCAEnabled
        s.setFloat(i++, lens.isCaActive ? 1.0 : 0.0);
        // uVK1..uVK3
        s.setFloat(i++, lens.vignettingEnabled ? lens.vignettingK1 : 0.0);
        s.setFloat(i++, lens.vignettingEnabled ? lens.vignettingK2 : 0.0);
        s.setFloat(i++, lens.vignettingEnabled ? lens.vignettingK3 : 0.0);
        // uVignettingEnabled
        s.setFloat(i++, lens.vignettingEnabled ? 1.0 : 0.0);
        // uSize
        s.setFloat(i++, targetWidth.toDouble());
        s.setFloat(i++, targetHeight.toDouble());
      },
    );
  }

  static Future<ui.Image> _runPerspectivePass({
    required ui.FragmentProgram program,
    required ui.Image input,
    required AdjustmentParams params,
    PerspectiveMatrixCache? cache,
  }) async {
    final w = input.width;
    final h = input.height;
    final matrixCache = cache ?? PerspectiveMatrixCache();

    final invH = matrixCache.get(params.perspective, w, h);

    return runSingleShaderPass(
      shader: program.fragmentShader(),
      outputWidth: w,
      outputHeight: h,
      samplers: [input],
      setUniforms: (s) {
        int i = 0;
        s.setFloat(i++, w.toDouble());
        s.setFloat(i++, h.toDouble());
        for (int j = 0; j < 9; j++) {
          s.setFloat(i++, invH[j]);
        }
      },
    );
  }

  static Future<ui.Image> _runSharpenPass({
    required ui.FragmentProgram program,
    required ui.Image input,
    required double amount,
    required double radius,
    required double masking,
  }) async {
    final w = input.width, h = input.height;
    return runSingleShaderPass(
      shader: program.fragmentShader(),
      outputWidth: w,
      outputHeight: h,
      samplers: [input],
      setUniforms: (s) {
        int i = 0;
        s.setFloat(i++, w.toDouble());
        s.setFloat(i++, h.toDouble());
        s.setFloat(i++, amount);
        s.setFloat(i++, radius);
        s.setFloat(i++, masking);
      },
    );
  }
}
