import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../state/app_settings_state.dart';
import '../widgets/ai_settings_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      appBar: AppBar(
        title: Text(tr("settings")),
        backgroundColor: const Color(0xFF0A0A0E),
        elevation: 0,
      ),
      body: ListView(
        children: [
          _SectionHeader(tr("settingsTether")),
          _TetherFolderTile(),
          SizedBox(height: 16),

          _SectionHeader(tr("aiColor")),
          _AISettingsLink(),
          SizedBox(height: 16),

          _SectionHeader(tr("settingsAbout")),
          _AboutTiles(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.white54,
        ),
      ),
    );
  }
}

class _TetherFolderTile extends ConsumerWidget {
  const _TetherFolderTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(tetherFolderProvider);

    Future<void> pick() async {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: tr("settingsTetherFolderChoose"),
      );
      if (path != null && path.isNotEmpty) {
        await ref.read(tetherFolderProvider.notifier).set(path);
      }
    }

    return ListTile(
      leading: const Icon(Icons.folder_outlined, size: 20),
      title: Text(tr("settingsTetherFolder"), style: TextStyle(fontSize: 13.5)),
      subtitle: Text(
        folder ?? tr("settingsTetherFolderNone"),
        style: TextStyle(
          fontSize: 11,
          fontFamily: folder != null ? 'monospace' : null,
          color: folder == null ? Colors.white38 : Colors.white70,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (folder != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: tr("settingsTetherFolderClear"),
              visualDensity: VisualDensity.compact,
              onPressed: () => ref.read(tetherFolderProvider.notifier).clear(),
            ),
          TextButton(
            onPressed: pick,
            child: Text(tr("browse"), style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _AISettingsLink extends StatelessWidget {
  const _AISettingsLink();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.auto_awesome, size: 20),
      title: Text(tr("settingsAIConfiguration"), style: TextStyle(fontSize: 13.5)),
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

class _AboutTiles extends StatelessWidget {
  const _AboutTiles();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (ctx, snap) {
        final ver = snap.hasData
            ? '${snap.data!.version} (${snap.data!.buildNumber})'
            : '...';
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline, size: 20),
              title: Text(tr("version"), style: TextStyle(fontSize: 13.5)),
              trailing: Text(
                ver,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.white70,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.code, size: 20),
              title: Text(tr("projectUrl"), style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                'github.com/yusuaois/e4pix',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              trailing: const Icon(Icons.open_in_new, size: 14),
              onTap: () {
                url_launcher.launchUrl(Uri.parse('https://github.com/yusuaois/e4pix'));
              },
            ),
          ],
        );
      },
    );
  }
}
