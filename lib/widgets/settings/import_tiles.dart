import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/providers.dart';

class ImportModeTiles extends ConsumerWidget {
  final BorderRadius? tileBorderRadius;
  const ImportModeTiles({super.key, this.tileBorderRadius});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(importModeProvider);
    final notifier = ref.read(importModeProvider.notifier);

    String label(ImportMode m) => switch (m) {
      ImportMode.rawPriority => tr('importModeRawPriority'),
      ImportMode.rawOnly => tr('importModeRawOnly'),
      ImportMode.all => tr('importModeAll'),
    };

    String desc(ImportMode m) => switch (m) {
      ImportMode.rawPriority => tr('importModeRawPriorityDesc'),
      ImportMode.rawOnly => tr('importModeRawOnlyDesc'),
      ImportMode.all => tr('importModeAllDesc'),
    };

    return ListTile(
      shape: tileBorderRadius != null
          ? RoundedRectangleBorder(borderRadius: tileBorderRadius!)
          : null,
      leading: const Icon(Icons.filter_alt_outlined, size: 20),
      title: Text(tr('importMode'), style: AppTypography.titleMedium),
      subtitle: Text(
        desc(mode),
        style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
      ),
      trailing: DropdownButton<ImportMode>(
        value: mode,
        items: [
          for (final m in ImportMode.values)
            DropdownMenuItem(
              value: m,
              child: Text(label(m), style: AppTypography.bodyLarge),
            ),
        ],
        onChanged: (v) {
          if (v != null) notifier.set(v);
        },
      ),
    );
  }
}
