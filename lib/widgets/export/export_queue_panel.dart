import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/export_job.dart';
import '../../state/providers.dart';

/// 导出队列面板（底部弹出） 实时显示每个任务的状态/进度，可取消
class ExportQueuePanel extends ConsumerWidget {
  const ExportQueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(exportQueueProvider);
    final notifier = ref.read(exportQueueProvider.notifier);
    final pending = jobs.where((j) => !j.isFinished).length;
    final hasFinished = jobs.any((j) => j.isFinished);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                const Icon(Icons.ios_share_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  tr('exportQueueTitle'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (pending > 0)
                  Text(
                    tr('exportQueueRemaining', args: ['$pending']),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (jobs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    tr('exportQueueEmpty'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  itemBuilder: (_, i) => _JobRow(
                    job: jobs[i],
                    onCancel: () => notifier.cancel(jobs[i].id),
                  ),
                ),
              ),

            const SizedBox(height: 8),
            // 底部操作
            Row(
              children: [
                if (hasFinished)
                  TextButton.icon(
                    onPressed: notifier.clearFinished,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: Text(
                      tr('exportQueueClearFinished'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                const Spacer(),
                if (pending > 0)
                  TextButton.icon(
                    onPressed: notifier.cancelAll,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: Text(
                      tr('exportQueueCancelAll'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  final ExportJob job;
  final VoidCallback onCancel;
  const _JobRow({required this.job, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _statusIcon(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.displayName,
                  style: const TextStyle(fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (job.status == ExportJobStatus.running ||
                    job.status == ExportJobStatus.cancelling) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: job.status == ExportJobStatus.cancelling
                          ? null // 取消中：不确定进度（来回动）
                          : job.progress,
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      color: job.status == ExportJobStatus.cancelling
                          ? Colors.orangeAccent.withValues(alpha: 0.7)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    job.status == ExportJobStatus.cancelling
                        ? tr('exportCancelling') // "正在取消…"
                        : (job.stage ?? ''),
                    style: TextStyle(
                      fontSize: 9.5,
                      color: job.status == ExportJobStatus.cancelling
                          ? Colors.orangeAccent.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.45),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else if (job.status == ExportJobStatus.failed &&
                    job.error != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    job.error!,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: Colors.redAccent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else if (job.status == ExportJobStatus.done &&
                    job.outputPath != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    job.outputPath!,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontFamily: 'monospace',
                      color: Colors.greenAccent.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // 取消按钮（未完成且非取消中）
          if (!job.isFinished && job.status != ExportJobStatus.cancelling)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: tr('cancel'),
              visualDensity: VisualDensity.compact,
              onPressed: onCancel,
            ),
        ],
      ),
    );
  }

  Widget _statusIcon() {
    switch (job.status) {
      case ExportJobStatus.queued:
        return Icon(
          Icons.schedule,
          size: 18,
          color: Colors.white.withValues(alpha: 0.4),
        );
      case ExportJobStatus.running:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ExportJobStatus.cancelling:
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.orangeAccent.withValues(alpha: 0.8),
          ),
        );
      case ExportJobStatus.done:
        return const Icon(
          Icons.check_circle,
          size: 18,
          color: Colors.greenAccent,
        );
      case ExportJobStatus.failed:
        return const Icon(
          Icons.error_outline,
          size: 18,
          color: Colors.redAccent,
        );
      case ExportJobStatus.cancelled:
        return Icon(
          Icons.block,
          size: 18,
          color: Colors.white.withValues(alpha: 0.3),
        );
    }
  }
}
