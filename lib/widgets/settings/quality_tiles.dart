import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

class QualityTiles extends ConsumerWidget {
  const QualityTiles({super.key});

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
                  style: const TextStyle(fontSize: 13.5),
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
                label: Text(
                  tr("qualityLow"),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              ButtonSegment(
                value: PreviewQuality.medium,
                label: Text(
                  tr("qualityMedium"),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              ButtonSegment(
                value: PreviewQuality.high,
                label: Text(
                  tr("qualityHigh"),
                  style: const TextStyle(fontSize: 12),
                ),
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
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            tr("settingsExportQualityHint"),
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          trailing: Text(
            '$eq',
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Colors.white70,
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
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            tr('imageCacheCapacityHint'),
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          trailing: SizedBox(
            width: 44,
            child: Text(
              '${ref.watch(imageCacheCapacityProvider)}',
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.white70,
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
      ],
    );
  }
}
