import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../ai/ai_settings_dialog.dart';

class AISettingsLink extends StatelessWidget {
  final BorderRadius? tileBorderRadius;
  const AISettingsLink({super.key, this.tileBorderRadius});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: tileBorderRadius != null
          ? RoundedRectangleBorder(borderRadius: tileBorderRadius!)
          : null,
      leading: const Icon(Icons.auto_awesome, size: 20),
      title: Text(
        tr("settingsAIConfiguration"),
        style: AppTypography.titleMedium,
      ),
      subtitle: Text(
        tr("settingsAIConfigurationHint"),
        style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: () {
        showDialog(context: context, builder: (_) => const AISettingsDialog());
      },
    );
  }
}
