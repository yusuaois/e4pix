import 'package:flutter/foundation.dart';

import '../models/adjustment_params.dart';
import 'export_config.dart';

enum ExportJobStatus { queued, running, cancelling, done, failed, cancelled }

/// 队列中的单个导出任务（一张图）
///
/// [params] 是 enqueue 时的参数快照（含 crop/locals/curves/lutIntensity）
/// 即使之后用户继续编辑该图，队列仍用入队时的参数
/// [config] 是该批次共享的导出配置（格式/目录/LUT 引用等）
@immutable
class ExportJob {
  final String id;
  final String inputPath;
  final String displayName;
  final AdjustmentParams params;
  final ExportConfig config;
  final int seq;

  final ExportJobStatus status;
  final double progress; // 0-1
  final String? stage;
  final String? error;
  final String? outputPath;

  const ExportJob({
    required this.id,
    required this.inputPath,
    required this.displayName,
    required this.params,
    required this.config,
    required this.seq,
    this.status = ExportJobStatus.queued,
    this.progress = 0.0,
    this.stage,
    this.error,
    this.outputPath,
  });

  bool get isFinished =>
      status == ExportJobStatus.done ||
      status == ExportJobStatus.failed ||
      status == ExportJobStatus.cancelled;

  ExportJob copyWith({
    ExportJobStatus? status,
    double? progress,
    String? stage,
    String? error,
    String? outputPath,
  }) => ExportJob(
    id: id,
    inputPath: inputPath,
    displayName: displayName,
    params: params,
    config: config,
    seq: seq,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    stage: stage ?? this.stage,
    error: error ?? this.error,
    outputPath: outputPath ?? this.outputPath,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ExportJob && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
