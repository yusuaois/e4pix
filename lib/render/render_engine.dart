import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../core/models/adjustment_params.dart';
import 'develop_uniforms.dart';
import '../utils/shader_pass_util.dart';

class RenderEngine {
  static Future<ui.Image> renderToImage({
    required ui.FragmentProgram program,
    required ui.Image sourceImage,
    required AdjustmentParams params,
    ui.Image? lutTexture,
    int lutSize = 0,
    ui.Image? lutTextureB,
    int lutSizeB = 0,
    ui.Image? curveTexture,
    int? targetWidth,
    int? targetHeight,
  }) async {
    final w = targetWidth ?? sourceImage.width;
    final h = targetHeight ?? sourceImage.height;
    final shader = program.fragmentShader();

    return runSingleShaderPass(
      shader: shader,
      outputWidth: w,
      outputHeight: h,
      samplers: [
        sourceImage,
        lutTexture ?? sourceImage,
        lutTextureB ?? sourceImage,
        curveTexture ?? sourceImage,
      ],
      setUniforms: (s) => applyDevelopUniforms(
        shader: s,
        renderSize: Size(w.toDouble(), h.toDouble()),
        params: params,
        image: sourceImage,
        lutTexture: lutTexture,
        lutSize: lutSize,
        lutTextureB: lutTextureB,
        lutSizeB: lutSizeB,
        curveTexture: curveTexture,
      ),
    );
  }
}
