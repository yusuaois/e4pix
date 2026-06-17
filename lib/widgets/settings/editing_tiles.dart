import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../screens/keybinding_settings_screen.dart';
import '../../state/providers.dart';

class EditingTiles extends ConsumerWidget {
  const EditingTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.save_outlined, size: 20),
          title: Text(tr("settingsSidecar"), style: AppTypography.titleMedium),
          subtitle: Text(
            tr("settingsSidecarHint"),
            style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
          ),
          value: ref.watch(sidecarEnabledProvider),
          onChanged: (v) => ref.read(sidecarEnabledProvider.notifier).set(v),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.exit_to_app_outlined, size: 20),
          title: Text(
            tr("settingsExitConfirm"),
            style: AppTypography.titleMedium,
          ),
          subtitle: Text(
            tr("settingsExitConfirmHint"),
            style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
          ),
          value: !ref.watch(skipExitConfirmProvider),
          onChanged: (v) => ref.read(skipExitConfirmProvider.notifier).set(!v),
        ),

        ListTile(
          leading: const Icon(Icons.keyboard_outlined, size: 20),
          title: Text(
            tr('settingsKeybindings'),
            style: AppTypography.titleMedium,
          ),
          subtitle: Text(
            tr('settingsKeybindingsHint'),
            style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const KeybindingSettingsScreen()),
          ),
        ),

        ListTile(
          leading: const Icon(Icons.memory, size: 20),
          title: Text(
            tr('denoiseParallelism'),
            style: AppTypography.titleMedium,
          ),
          subtitle: Text(
            tr('denoiseParallelismDesc'),
            style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
          ),
          trailing: DropdownButton<int>(
            value: ref.watch(denoiseParallelismProvider),
            items: [
              DropdownMenuItem(
                value: 0,
                child: Text(tr('auto'), style: AppTypography.bodyLarge),
              ),
              for (final n in [1, 2, 4, 6, 8, 12, 16])
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: (v) {
              if (v != null) {
                ref.read(denoiseParallelismProvider.notifier).set(v);
              }
            },
          ),
        ),
      ],
    );
  }
}
