import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'hdr_fusion_service.dart';

class HdrIsolateParams {
  final SendPort sendPort;
  final List<Uint8List> images;
  final int width;
  final int height;
  final int levels;
  final SendPort? progressPort;
  const HdrIsolateParams({
    required this.sendPort,
    required this.images,
    required this.width,
    required this.height,
    this.levels = 5,
    this.progressPort,
  });
}

/// Isolate 入口：执行 Mertens 曝光融合
/// 成功发送 Uint8List，失败发送 String（错误信息）
/// 通过 progressPort 发送 0.0~1.0 进度
void hdrFuseIsolate(HdrIsolateParams p) {
  try {
    debugPrint(
      '[HDR:isolate] Starting fusion: '
      '${p.images.length} images, ${p.width}x${p.height}',
    );
    final result = HdrFusionService.fuse(
      p.images,
      p.width,
      p.height,
      levels: p.levels,
      onProgress: (progress) {
        p.progressPort?.send(progress);
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
