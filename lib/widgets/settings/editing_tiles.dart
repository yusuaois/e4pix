import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../screens/keybinding_settings_screen.dart';
import '../../state/providers.dart';

class EditingTiles extends ConsumerWidget {
  final BorderRadius? tileBorderRadius;
  const EditingTiles({super.key, this.tileBorderRadius});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _buildPreserveHistoryTile(ref),
        _buildSidecarTile(ref),
        _buildExitConfirmTile(ref),
        _buildKeybindingsTile(context),
        _buildDenoiseParallelismTile(ref),
      ],
    );
  }

  Widget _buildPreserveHistoryTile(WidgetRef ref) {
    return SwitchListTile(
      secondary: const Icon(Icons.history, size: 20),
      title: Text(
        tr("settingsPreserveHistory"),
        style: AppTypography.titleMedium,
      ),
      subtitle: Text(
        tr("settingsPreserveHistoryHint"),
        style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
      ),
      value: ref.watch(preserveHistoryProvider),
      onChanged: (v) => ref.read(preserveHistoryProvider.notifier).set(v),
    );
  }

  Widget _buildSidecarTile(WidgetRef ref) {
    return SwitchListTile(
      secondary: const Icon(Icons.save_outlined, size: 20),
      title: Text(tr("settingsSidecar"), style: AppTypography.titleMedium),
      subtitle: Text(
        tr("settingsSidecarHint"),
        style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
      ),
      value: ref.watch(sidecarEnabledProvider),
      onChanged: (v) => ref.read(sidecarEnabledProvider.notifier).set(v),
    );
  }

  Widget _buildExitConfirmTile(WidgetRef ref) {
    return SwitchListTile(
      secondary: const Icon(Icons.exit_to_app_outlined, size: 20),
      title: Text(tr("settingsExitConfirm"), style: AppTypography.titleMedium),
      subtitle: Text(
        tr("settingsExitConfirmHint"),
        style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
      ),
      value: !ref.watch(skipExitConfirmProvider),
      onChanged: (v) => ref.read(skipExitConfirmProvider.notifier).set(!v),
    );
  }

  Widget _buildKeybindingsTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.keyboard_outlined, size: 20),
      title: Text(tr('settingsKeybindings'), style: AppTypography.titleMedium),
      subtitle: Text(
        tr('settingsKeybindingsHint'),
        style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const KeybindingSettingsScreen()),
      ),
    );
  }

  Widget _buildDenoiseParallelismTile(WidgetRef ref) {
    return ListTile(
      shape: tileBorderRadius != null
          ? RoundedRectangleBorder(borderRadius: tileBorderRadius!)
          : null,
      leading: const Icon(Icons.memory, size: 20),
      title: Text(tr('denoiseParallelism'), style: AppTypography.titleMedium),
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
    );
  }
}
