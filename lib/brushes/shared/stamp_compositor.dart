import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import '../../state/providers.dart';
import '../../utils/brush_coord_utils.dart';
import '../../utils/brush_preview_utils.dart';
import '../../utils/shader_pass_util.dart';
import 'spot_data_texture.dart';
import 'stamp_mark.dart';

/// GPU 增量合成预览管理器
///
/// 独立于 [State] 生命周期，通过构造函数注入依赖，
/// 所有需要 [WidgetRef] 的方法接受 [ref] 参数
class StampCompositor<T extends StampMark> {
  StampCompositor({
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.getSourceImage,
    required this.logTag,
    required this.shaderKey,
    required this.isMounted,
    required this.onNeedsRebuild,
  });

  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image? Function() getSourceImage;
  final String logTag;
  final String shaderKey;
  final bool Function() isMounted;
  final VoidCallback onNeedsRebuild;

  ui.Image? compositedImage;
  int compositedCount = 0;
  bool compositing = false;
  static const _kCompositeBatchSize = 8;

  /// 屏幕坐标 → 源图归一化坐标
  Offset screenToSource(Offset screen) => screenToSourceNorm(
    screen: screen,
    imageDisplaySize: imageDisplaySize,
    crop: crop,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
  );

  /// 释放 compositedImage
  void disposeComposited() {
    compositedImage?.dispose();
    compositedImage = null;
  }

  /// 重置合成状态（新笔画开始时调用）
  void reset() {
    disposeComposited();
    compositedCount = 0;
  }

  /// 异步触发增量合成，带并发守卫
  ///
  /// [force] 为 true 时忽略 batch 阈值，强制全量合成
  /// [strokeMarks] 当前笔画中的所有 marks
  Future<void> triggerComposite(
    WidgetRef ref, {
    required List<T> strokeMarks,
    bool force = false,
  }) async {
    if (compositing) return;
    final newCount = strokeMarks.length - compositedCount;
    if (!force && newCount < _kCompositeBatchSize) return;
    compositing = true;

    final allNew = strokeMarks.sublist(compositedCount);
    final validMarks = allNew.where((m) {
      return !isMarkSourceFullyOOB(
        sourceX: m.source.dx,
        sourceY: m.source.dy,
        radius: m.radius,
        imageWidth: sourceWidth.toDouble(),
        imageHeight: sourceHeight.toDouble(),
      );
    }).toList();

    if (validMarks.isNotEmpty) {
      final prog = ref.read(brushShaderProgramsProvider).value?[shaderKey];
      final shader = prog?.fragmentShader();
      final base = compositedImage ?? getSourceImage();
      if (shader != null && base != null) {
        try {
          final result = await _runCompositePass(
            base: base,
            marks: validMarks,
            shader: shader,
          );
          if (!isMounted()) {
            result.dispose();
            compositedCount += allNew.length;
            compositing = false;
            return;
          }
          disposeComposited();
          compositedImage = result;
          compositedCount += allNew.length;
        } catch (e) {
          debugPrint('$logTag composite failed: $e');
          disposeComposited();
        }
      }
    } else {
      compositedCount += allNew.length;
    }
    compositing = false;
    onNeedsRebuild();
  }

  Future<ui.Image> _runCompositePass({
    required ui.Image base,
    required List<T> marks,
    required ui.FragmentShader shader,
  }) async {
    final count = marks.length.clamp(0, 128);
    final tex = await encodeMarksToTexture(
      count: count,
      maxSpots: 128,
      getMarkFloats: (i) => [
        marks[i].source.dx,
        marks[i].source.dy,
        marks[i].target.dx,
        marks[i].target.dy,
        marks[i].radius,
        marks[i].hardness,
      ],
    );
    try {
      return await runSingleShaderPass(
        shader: shader,
        outputWidth: base.width,
        outputHeight: base.height,
        samplers: [base, tex],
        setUniforms: (s) {
          s.setFloat(0, base.width.toDouble());
          s.setFloat(1, base.height.toDouble());
          s.setFloat(2, count.toDouble());
          s.setFloat(3, tex.width.toDouble());
        },
      );
    } finally {
      tex.dispose();
    }
  }
}
