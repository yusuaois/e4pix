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

    Widget tile(
      ImportMode value,
      String title,
      String desc, {
      BorderRadius? shape,
    }) {
      return RadioListTile<ImportMode>(
        value: value,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: shape != null
            ? RoundedRectangleBorder(borderRadius: shape)
            : null,
        title: Text(title, style: AppTypography.bodyLarge),
        subtitle: Text(
          desc,
          style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
        ),
      );
    }

    return RadioGroup<ImportMode>(
      groupValue: mode,
      onChanged: (v) => v != null ? notifier.set(v) : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.filter_alt_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('importMode'),
                    style: AppTypography.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          tile(
            ImportMode.rawPriority,
            tr('importModeRawPriority'),
            tr('importModeRawPriorityDesc'),
          ),
          tile(
            ImportMode.rawOnly,
            tr('importModeRawOnly'),
            tr('importModeRawOnlyDesc'),
          ),
          tile(
            ImportMode.all,
            tr('importModeAll'),
            tr('importModeAllDesc'),
            shape: tileBorderRadius,
          ),
        ],
      ),
    );
  }
}
