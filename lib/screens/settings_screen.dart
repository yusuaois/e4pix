import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../state/app_settings_state.dart';
import '../widgets/ai_settings_dialog.dart';
import '../state/theme_state.dart';
import '../widgets/theme_color_picker.dart';

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

          _SectionHeader(tr("settingsTheme")),
          const _ThemeTiles(),
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

class _ThemeTiles extends ConsumerWidget {
  const _ThemeTiles();

  // 4 个预设色点（可自行改）；第 5 个是取色盘
  static const List<Color> _presets = [
    Color(0xFF6B5BFF), // 紫（默认）
    Color(0xFF1E88E5), // 蓝
    Color(0xFF43A047), // 绿
    Color(0xFFFB8C00), // 橙
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dynamicEnabled = ref.watch(dynamicColorEnabledProvider);
    final seed = ref.watch(seedColorProvider);
    final isPreset = _presets.any((c) => c.toARGB32() == seed);

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.palette_outlined, size: 20),
          title: Text(
            tr("settingsDynamicColor"),
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            tr("settingsDynamicColorHint"),
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          value: dynamicEnabled,
          onChanged: (v) =>
              ref.read(dynamicColorEnabledProvider.notifier).set(v),
        ),
        if (!dynamicEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
            child: Row(
              children: [
                Text(
                  tr("settingsCustomColor"),
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                ),
                const SizedBox(width: 16),
                for (final c in _presets) ...[
                  _Swatch(
                    color: c,
                    selected: seed == c.toARGB32(),
                    onTap: () =>
                        ref.read(seedColorProvider.notifier).set(c.toARGB32()),
                  ),
                  const SizedBox(width: 10),
                ],
                _Swatch.wheel(
                  selected: !isPreset,
                  current: Color(seed),
                  onTap: () async {
                    final picked = await showDialog<Color>(
                      context: context,
                      builder: (_) =>
                          ThemeColorWheelDialog(initial: Color(seed)),
                    );
                    if (picked != null) {
                      ref
                          .read(seedColorProvider.notifier)
                          .set(picked.toARGB32());
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool isWheel;
  final Color? current;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  }) : isWheel = false,
       current = null;

  const _Swatch.wheel({
    required this.selected,
    required this.current,
    required this.onTap,
  }) : color = Colors.transparent,
       isWheel = true;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isWheel ? null : color,
          shape: BoxShape.circle,
          gradient: isWheel
              ? const SweepGradient(
                  colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                )
              : null,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 3 : 1,
          ),
        ),
        child: isWheel
            ? const Icon(Icons.colorize, size: 15, color: Colors.white)
            : (selected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null),
      ),
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
                url_launcher.launchUrl(
                  Uri.parse('https://github.com/yusuaois/e4pix'),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
