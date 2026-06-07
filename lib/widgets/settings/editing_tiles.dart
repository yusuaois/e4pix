import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          title: Text(
            tr("settingsSidecar"),
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            tr("settingsSidecarHint"),
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          value: ref.watch(sidecarEnabledProvider),
          onChanged: (v) => ref.read(sidecarEnabledProvider.notifier).set(v),
        ),

        ListTile(
          leading: const Icon(Icons.keyboard_outlined, size: 20),
          title: Text(
            tr('settingsKeybindings'),
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            tr('settingsKeybindingsHint'),
            style: const TextStyle(fontSize: 11, color: Colors.white54),
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
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            tr('denoiseParallelismDesc'),
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          trailing: DropdownButton<int>(
            value: ref.watch(denoiseParallelismProvider),
            items: [
              DropdownMenuItem(
                value: 0,
                child: Text(tr('auto'), style: TextStyle(fontSize: 12)),
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
