import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../core/models/adjustment_params.dart';
import 'develop_uniforms.dart';

class RenderEngine {
  // 渲染输出
  static Future<ui.Image> renderToImage({
    required ui.FragmentProgram program,
    required ui.Image sourceImage,
    required AdjustmentParams params,
    ui.Image? lutTexture,
    int lutSize = 0,
    int? targetWidth,
    int? targetHeight,
  }) async {
    final w = targetWidth ?? sourceImage.width;
    final h = targetHeight ?? sourceImage.height;
    final shader = program.fragmentShader();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    applyDevelopUniforms(
      shader: shader,
      renderSize: Size(w.toDouble(), h.toDouble()),
      params: params,
      image: sourceImage,
      lutTexture: lutTexture,
      lutSize: lutSize,
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..shader = shader,
    );

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(w, h);
    } finally {
      picture.dispose();
    }
  }
}