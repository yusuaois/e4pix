import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../state/providers.dart';

class ImportModeTiles extends ConsumerWidget {
  const ImportModeTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(importModeProvider);
    final notifier = ref.read(importModeProvider.notifier);

    Widget tile(ImportMode value, String title, String desc) {
      return RadioListTile<ImportMode>(
        value: value,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(title, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          desc,
          style: TextStyle(fontSize: 11, color: AppColors.faintText),
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
                    style: const TextStyle(fontSize: 13.5),
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
          tile(ImportMode.all, tr('importModeAll'), tr('importModeAllDesc')),
        ],
      ),
    );
  }
}
