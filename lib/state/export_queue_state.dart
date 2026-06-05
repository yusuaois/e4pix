import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/export_job.dart';
import '../render/exporter.dart';
import '../render/lut_texture_cache.dart';
import '../services/notifications/export_notification_service.dart';
import 'providers.dart';

/// 导出队列：串行执行，后台运行，可取消
/// - enqueue 后立即返回，任务在后台串行跑
/// - 取消：排队中的直接标记 cancelled；正在跑的靠 exporter 的阶段检查点中止
/// - programs 执行时 ref.read（全局不变）；LUT 从 job.config 取（enqueue 快照）
class ExportQueueNotifier extends Notifier<List<ExportJob>> {
  bool _running = false;
  final Set<String> _cancelled = {};
  final Set<String> _usedNames = {}; // 跨队列文件名去重

  @override
  List<ExportJob> build() => const [];

  /// 入队一批任务并启动执行（若未在运行）
  void enqueue(List<ExportJob> jobs) {
    if (jobs.isEmpty) return;
    state = [...state, ...jobs];
    _pump();
  }

  /// 取消单个任务
  void cancel(String id) {
    _cancelled.add(id);
    final job = _find(id);
    if (job == null) return;
    if (job.status == ExportJobStatus.queued) {
      _patch(id, status: ExportJobStatus.cancelled); // 排队中立即取消
    } else if (job.status == ExportJobStatus.running) {
      _patch(id, status: ExportJobStatus.cancelling); // 运行中：标记取消中，等检查点
    }
  }

  /// 取消所有未完成任务
  void cancelAll() {
    for (final j in state) {
      if (!j.isFinished) _cancelled.add(j.id);
    }
    state = [
      for (final j in state)
        if (j.status == ExportJobStatus.queued)
          j.copyWith(status: ExportJobStatus.cancelled)
        else if (j.status == ExportJobStatus.running)
          j.copyWith(status: ExportJobStatus.cancelling)
        else
          j,
    ];
  }

  /// 移除已结束（done/failed/cancelled）的任务
  void clearFinished() {
    state = state.where((j) => !j.isFinished).toList();
    // 清理已结束的取消标记
    _cancelled.removeWhere((id) => _find(id) == null);
  }

  /// 全部清空（保留正在跑的——它会自然结束）
  void clearAll() {
    cancelAll();
    state = state.where((j) => j.status == ExportJobStatus.running).toList();
  }

  // —— 内部 ——

  ExportJob? _find(String id) {
    for (final j in state) {
      if (j.id == id) return j;
    }
    return null;
  }

  void _patch(
    String id, {
    ExportJobStatus? status,
    double? progress,
    String? stage,
    String? error,
    String? outputPath,
  }) {
    state = [
      for (final j in state)
        if (j.id == id)
          j.copyWith(
            status: status,
            progress: progress,
            stage: stage,
            error: error,
            outputPath: outputPath,
          )
        else
          j,
    ];
  }

  ExportJob? _nextQueued() {
    for (final j in state) {
      if (j.status == ExportJobStatus.queued) return j;
    }
    return null;
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = _nextQueued();
        if (next == null) break;

        // 入队后、执行前被取消
        if (_cancelled.contains(next.id)) {
          _patch(next.id, status: ExportJobStatus.cancelled);
          continue;
        }

        await _runJob(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runJob(ExportJob job) async {
    _patch(job.id, status: ExportJobStatus.running, progress: 0, stage: null);

    final program = ref.read(shaderProgramProvider).value;
    final maskProgram = ref.read(maskShaderProgramProvider).value;
    if (program == null || maskProgram == null) {
      _patch(
        job.id,
        status: ExportJobStatus.failed,
        error: 'Shader not loaded',
      );
      return;
    }

    final sharpenProgram = ref.read(sharpenShaderProgramProvider).value;
    final denoiseProgram = ref.read(denoiseShaderProgramProvider).value;
    final cfg = job.config;

    // per-image LUT：按本 job 的 params.lutNameA/B 从缓存加载 texture
    final cache = LutTextureCache.instance;
    LutTexture? lutA;
    LutTexture? lutB;
    try {
      if (job.params.lutNameA.isNotEmpty) {
        lutA = await cache.load(job.params.lutNameA);
      }
      if (job.params.lutNameB.isNotEmpty) {
        lutB = await cache.load(job.params.lutNameB);
      }
    } catch (_) {}

    try {
      final file = await Exporter.exportFullRes(
        inputPath: job.inputPath,
        outputDir: cfg.outputDir,
        filenameTemplate: cfg.filenameTemplate,
        seq: job.seq,
        usedNames: _usedNames,
        format: cfg.format,
        shaderProgram: program,
        maskProgram: maskProgram,
        params: job.params,
        lutTexture: lutA?.texture,
        lutSize: lutA?.size ?? 0,
        lutTextureB: lutB?.texture,
        lutSizeB: lutB?.size ?? 0,
        sharpenProgram: sharpenProgram,
        denoiseProgram: denoiseProgram,
        denoiseEngine: cfg.denoiseEngine,
        denoiseParallelism: cfg.denoiseParallelism,
        jpegQuality: cfg.jpegQuality,
        writeExif: cfg.writeExif,
        onProgress: (f, s) => _patch(job.id, progress: f, stage: s),
        isCancelled: () => _cancelled.contains(job.id),
      );
      _patch(
        job.id,
        status: ExportJobStatus.done,
        progress: 1.0,
        outputPath: file.path,
      );

      final remaining = state
          .where((j) => !j.isFinished && j.id != job.id)
          .length;
      if (remaining == 0) {
        final doneCount = state
            .where((j) => j.status == ExportJobStatus.done || j.id == job.id)
            .length;
        if (doneCount == 1) {
          ExportNotificationService.instance.notifyDone(
            filename: job.displayName,
            outputPath: file.path,
          );
        } else {
          ExportNotificationService.instance.notifyBatchDone(
            count: doneCount,
            outputDir: job.config.outputDir,
          );
        }
      }
    } on ExportCancelledException {
      _patch(job.id, status: ExportJobStatus.cancelled);
    } catch (e) {
      _patch(job.id, status: ExportJobStatus.failed, error: e.toString());

      ExportNotificationService.instance.notifyFailed(
        filename: job.displayName,
        error: e.toString(),
        outputDir: job.config.outputDir,
      );
    }
  }
}

final exportQueueProvider =
    NotifierProvider<ExportQueueNotifier, List<ExportJob>>(
      ExportQueueNotifier.new,
    );

/// 未完成任务数
final exportQueuePendingCountProvider = Provider<int>((ref) {
  final jobs = ref.watch(exportQueueProvider);
  return jobs.where((j) => !j.isFinished).length;
});

/// 是否有正在运行的任务
final exportQueueRunningProvider = Provider<bool>((ref) {
  final jobs = ref.watch(exportQueueProvider);
  return jobs.any((j) => j.status == ExportJobStatus.running);
});
