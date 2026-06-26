import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../core/constants/hdr_constants.dart';
import '../debug/debug_log_service.dart';
import 'hdr_fusion_service.dart';
import 'image_alignment_service.dart';

/// HDR 融合 Isolate 参数
class HdrIsolateParams {
  final SendPort sendPort;
  final List<Uint8List> images;
  final int width;
  final int height;
  final int levels;
  final bool align;
  final SendPort? progressPort;
  final String? logFilePath;
  HdrIsolateParams({
    required this.sendPort,
    required this.images,
    required this.width,
    required this.height,
    this.levels = 5,
    this.align = true,
    this.progressPort,
    this.logFilePath,
  });
}

/// Isolate 入口：执行图像对齐 + Mertens 曝光融合
/// 成功发送 Uint8List，失败发送 String（错误信息）
/// 通过 progressPort 发送 0.0~1.0 进度（0~0.3 对齐，0.3~0.9 融合）
void hdrFuseIsolate(HdrIsolateParams p) {
  DebugLogService.setupIsolateLogging(logFilePath: p.logFilePath);
  try {
    debugPrint(
      '[HDR:isolate] Starting: '
      '${p.images.length} images, ${p.width}x${p.height}, '
      'align=${p.align}',
    );

    // 进度分配（对话框绝对进度）：
    // decode 0~kProgressDecodeEnd → 对齐 ~kProgressAlignEnd → 融合 ~kProgressFusionEnd → save kProgressSaveStart~1.0
    // align=false 时：decode 0~kProgressDecodeEnd → 融合 kProgressDecodeEnd~kProgressFusionEnd（无缝衔接）

    // 阶段 1：图像对齐
    List<Uint8List> images = p.images;
    int w = p.width;
    int h = p.height;
    final bool didAlign = p.align && images.length > 1;

    if (didAlign) {
      debugPrint('[HDR:isolate] Aligning images...');
      final alignResult = ImageAlignmentService.align(
        images: images,
        width: w,
        height: h,
        onProgress: (progress) {
          // 对齐占对话框 kProgressDecodeEnd~kProgressAlignEnd
          p.progressPort?.send(
            kProgressDecodeEnd +
                progress * (kProgressAlignEnd - kProgressDecodeEnd),
          );
        },
      );
      images = alignResult.images;
      w = alignResult.width;
      h = alignResult.height;
      debugPrint('[HDR:isolate] Alignment done: ${w}x$h');
    } else {
      // 通知 screen：无对齐阶段，直接进入融合
      p.progressPort?.send(-1.0);
    }

    // 阶段 2：曝光融合
    final fusionStart = didAlign ? kProgressAlignEnd : kProgressDecodeEnd;
    debugPrint('[HDR:isolate] Starting fusion: ${w}x$h');
    final result = HdrFusionService.fuse(
      images,
      w,
      h,
      levels: p.levels,
      onProgress: (progress) {
        // 融合从 fusionStart 到 kProgressFusionEnd
        p.progressPort?.send(
          fusionStart + progress * (kProgressFusionEnd - fusionStart),
        );
      },
    );
    debugPrint('[HDR:isolate] Fusion complete: ${result.length} bytes');
    p.sendPort.send(result);
  } catch (e, st) {
    debugPrint('[HDR:isolate] Failed: $e');
    debugPrint('[HDR:isolate] Stack: $st');
    p.sendPort.send('HDR fusion failed: $e');
  }
}
