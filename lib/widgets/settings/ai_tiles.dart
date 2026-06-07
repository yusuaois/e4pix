import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../ai/ai_settings_dialog.dart';

class AISettingsLink extends StatelessWidget {
  const AISettingsLink({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.auto_awesome, size: 20),
      title: Text(
        tr("settingsAIConfiguration"),
        style: TextStyle(fontSize: 13.5),
      ),
      subtitle: Text(
        tr("settingsAIConfigurationHint"),
        style: TextStyle(fontSize: 11, color: Colors.white54),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: () {
        showDialog(context: context, builder: (_) => const AISettingsDialog());
      },
    );
  }
}
