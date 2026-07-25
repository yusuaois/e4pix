import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../render/thumbnail_renderer.dart';
import '../../../state/params/history_entry.dart';
import '../../../state/providers.dart';

/// 弹出 History 面板
Future<void> showHistoryPanelSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.elevatedBg,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _HistoryPanelSheet(),
  );
}

class _HistoryPanelSheet extends ConsumerStatefulWidget {
  const _HistoryPanelSheet();

  @override
  ConsumerState<_HistoryPanelSheet> createState() => _HistoryPanelSheetState();
}

class _HistoryPanelSheetState extends ConsumerState<_HistoryPanelSheet> {
  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(historyPanelProvider);
    final entries = panel.entries;
    final selectedIndex = panel.selectedIndex;
    final brushSourceIndex = panel.brushSourceIndex;
    final notifier = ref.read(historyPanelProvider.notifier);
    final maxH = MediaQuery.of(context).size.height * 0.7;

    // 监听缩略图状态变化以驱动自动刷新
    final thumbState = ref.watch(thumbnailRendererProvider);
    final thumbNotifier = ref.read(thumbnailRendererProvider.notifier);

    Future.microtask(() {
      if (!mounted) return;
      for (final entry in entries) {
        thumbNotifier.requestFull('history', entry.id, entry.params);
      }
    });

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Text(tr('history'), style: AppTypography.titleMedium),
                const Spacer(),
                if (entries.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      notifier.clear();
                      Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.semanticError,
                    ),
                    child: Text(
                      tr('ClearAll'),
                      style: AppTypography.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                tr('historyEmpty'),
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 12,
                ),
                itemCount: entries.length,
                separatorBuilder: (_, b) => const SizedBox(height: 2),
                itemBuilder: (_, index) {
                  final entry = entries[index];
                  final isSelected = selectedIndex == index;
                  final isBrushSource = brushSourceIndex == index;

                  return _HistoryRow(
                    entry: entry,
                    index: index,
                    isSelected: isSelected,
                    isBrushSource: isBrushSource,
                    thumbState: thumbState,
                    onTap: () {
                      notifier.revertTo(index);
                      Navigator.pop(context);
                    },
                    onSetSource: () => notifier.selectBrushSource(index),
                    onClearSource: () => notifier.clearBrushSource(),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              tr('historyHint'),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final HistoryEntry entry;
  final int index;
  final bool isSelected;
  final bool isBrushSource;
  final ThumbnailRenderState thumbState;
  final VoidCallback onTap;
  final VoidCallback onSetSource;
  final VoidCallback onClearSource;

  const _HistoryRow({
    required this.entry,
    required this.index,
    required this.isSelected,
    required this.isBrushSource,
    required this.thumbState,
    required this.onTap,
    required this.onSetSource,
    required this.onClearSource,
  });

  String _relativeTime(DateTime dt, BuildContext context) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return tr('timeSAgo', args: ['${diff.inSeconds}']);
    if (diff.inMinutes < 60) return tr('timeMAgo', args: ['${diff.inMinutes}']);
    if (diff.inHours < 24) return tr('timeHAgo', args: ['${diff.inHours}']);
    return tr('timeDAgo', args: ['${diff.inDays}']);
  }

  @override
  Widget build(BuildContext context) {
    final thumbKey = 'history:${entry.id}';
    final thumb = thumbState.thumbs[thumbKey];
    final label = entry.label;
    final timestamp = entry.timestamp;

    return Material(
      color: isSelected ? AppColors.activeBg : AppColors.surfaceBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onSetSource,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            children: [
              // 缩略图
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 60,
                  height: 40,
                  child: thumb != null
                      ? RawImage(image: thumb, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.subtleBorder,
                          child: Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 16,
                              color: AppColors.faintText,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              // 标签 + 时间戳
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTypography.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _relativeTime(timestamp, context),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              // 画笔源指示器
              if (isBrushSource)
                IconButton(
                  icon: Icon(
                    Icons.brush,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  tooltip: tr('historyBrushSourceActive'),
                  onPressed: onClearSource,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                )
              else
                IconButton(
                  icon: Icon(
                    Icons.brush_outlined,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  tooltip: tr('historySetBrushSource'),
                  onPressed: onSetSource,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
