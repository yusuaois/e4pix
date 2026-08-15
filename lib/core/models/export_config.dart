import 'package:flutter/foundation.dart';

import '../../render/cpu_denoise.dart';
import '../../render/export/exporter.dart';

/// 一次导出（一个批次）共享配置
///
/// LUT 纹理引用在 enqueue 时快照当前全局 LUT（[lutTexture] 等）
/// 因为 LUT 是全局可变的，延迟执行时全局 LUT 可能已变
/// curve 不在此处——每张图执行时从自身 params.curves 现生成（见 Exporter）
@immutable
class ExportConfig {
  final ExportFormat format;
  final int jpegQuality;
  final String filenameTemplate;
  final String outputDir;
  final bool writeExif;
  final DenoiseEngine denoiseEngine;
  final int denoiseParallelism;

  const ExportConfig({
    required this.format,
    required this.jpegQuality,
    required this.filenameTemplate,
    required this.outputDir,
    required this.writeExif,
    required this.denoiseEngine,
    required this.denoiseParallelism,
  });
}
