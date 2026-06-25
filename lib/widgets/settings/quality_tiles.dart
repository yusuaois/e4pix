import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/app/app_settings.dart';
import '../../state/providers.dart';

class QualityTiles extends ConsumerWidget {
  final BorderRadius? tileBorderRadius;
  const QualityTiles({super.key, this.tileBorderRadius});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pq = ref.watch(previewQualityProvider);
    final eq = ref.watch(exportQualityProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.speed, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr("settingsPreviewQuality"),
                  style: AppTypography.titleMedium,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<PreviewQuality>(
            segments: [
              ButtonSegment(
                value: PreviewQuality.low,
                label: Text(tr("qualityLow"), style: AppTypography.bodyLarge),
              ),
              ButtonSegment(
                value: PreviewQuality.medium,
                label: Text(
                  tr("qualityMedium"),
                  style: AppTypography.bodyLarge,
                ),
              ),
              ButtonSegment(
                value: PreviewQuality.high,
                label: Text(tr("qualityHigh"), style: AppTypography.bodyLarge),
              ),
            ],
            selected: {pq},
            onSelectionChanged: (s) =>
                ref.read(previewQualityProvider.notifier).set(s.first),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.high_quality_outlined, size: 20),
          title: Text(
            tr("settingsExportQuality"),
            style: AppTypography.titleMedium,
          ),
          subtitle: Text(
            tr("settingsExportQualityHint"),
            style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
          ),
          trailing: Text(
            '$eq',
            style: AppTypography.bodyLarge.copyWith(
              fontFamily: 'monospace',
              color: AppColors.mediumText,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: eq.toDouble(),
            min: 50,
            max: 100,
            divisions: 50,
            onChanged: (v) =>
                ref.read(exportQualityProvider.notifier).set(v.round()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cached, size: 20),
          title: Text(
            tr('imageCacheCapacity'),
            style: AppTypography.titleMedium,
          ),
          subtitle: Text(
            tr('imageCacheCapacityHint'),
            style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
          ),
          trailing: SizedBox(
            width: 44,
            child: Text(
              '${ref.watch(imageCacheCapacityProvider)}',
              style: AppTypography.bodyLarge.copyWith(
                fontFamily: 'monospace',
                color: AppColors.mediumText,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: ref.watch(imageCacheCapacityProvider).toDouble(),
            min: 0,
            max: 20,
            divisions: 20,
            onChanged: (v) =>
                ref.read(imageCacheCapacityProvider.notifier).set(v.round()),
          ),
        ),
        _ExportConcurrencyTile(tileBorderRadius: tileBorderRadius),
      ],
    );
  }
}

class _ExportConcurrencyTile extends StatefulWidget {
  final BorderRadius? tileBorderRadius;
  const _ExportConcurrencyTile({this.tileBorderRadius});

  @override
  State<_ExportConcurrencyTile> createState() => _ExportConcurrencyTileState();
}

class _ExportConcurrencyTileState extends State<_ExportConcurrencyTile> {
  int _concurrency = 1;

  @override
  void initState() {
    super.initState();
    AppSettings.getExportConcurrency().then((v) {
      if (mounted) setState(() => _concurrency = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          shape: widget.tileBorderRadius != null
              ? RoundedRectangleBorder(borderRadius: widget.tileBorderRadius!)
              : null,
          leading: const Icon(Icons.queue_outlined, size: 20),
          title: Text(
            tr('settingsExportConcurrency'),
            style: AppTypography.titleMedium,
          ),
          subtitle: Text(
            tr('settingsExportConcurrencyHint'),
            style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
          ),
          trailing: SizedBox(
            width: 44,
            child: Text(
              '$_concurrency',
              style: AppTypography.bodyLarge.copyWith(
                fontFamily: 'monospace',
                color: AppColors.mediumText,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: _concurrency.toDouble(),
            min: 1,
            max: 4,
            divisions: 3,
            onChanged: (v) {
              final val = v.round();
              setState(() => _concurrency = val);
              AppSettings.setExportConcurrency(val);
            },
          ),
        ),
      ],
    );
  }
}
