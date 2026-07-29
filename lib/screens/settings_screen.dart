import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../widgets/settings/tether_tiles.dart';
import '../widgets/settings/import_tiles.dart';
import '../widgets/settings/ai_tiles.dart';
import '../widgets/settings/theme_tiles.dart';
import '../widgets/settings/quality_tiles.dart';
import '../widgets/settings/editing_tiles.dart';
import '../widgets/settings/debug_tiles.dart';
import '../widgets/settings/about_tiles.dart';

export '../widgets/settings/about_tiles.dart' show UpdateDialog;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _bottomRadius = BorderRadius.only(
    bottomLeft: Radius.circular(10),
    bottomRight: Radius.circular(10),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(tr("settings")),
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView(children: _buildSections()),
      ),
    );
  }

  List<Widget> _buildSections() {
    return [
      _SectionCard(
        title: tr("settingsTether"),
        children: const [
          TetherFolderTile(),
          ImportModeTiles(tileBorderRadius: _bottomRadius),
        ],
      ),
      const SizedBox(height: 12),
      _SectionCard(
        title: tr("aiColor"),
        children: const [AISettingsLink(tileBorderRadius: _bottomRadius)],
      ),
      const SizedBox(height: 12),
      _SectionCard(
        title: tr("settingsTheme"),
        children: const [ThemeTiles(tileBorderRadius: _bottomRadius)],
      ),
      const SizedBox(height: 12),
      _SectionCard(
        title: tr("settingsRender"),
        children: const [QualityTiles(tileBorderRadius: _bottomRadius)],
      ),
      const SizedBox(height: 12),
      _SectionCard(
        title: tr("settingsEditing"),
        children: const [EditingTiles(tileBorderRadius: _bottomRadius)],
      ),
      const SizedBox(height: 12),
      _SectionCard(
        title: tr('debug'),
        children: const [DebugModeTile(tileBorderRadius: _bottomRadius)],
      ),
      const SizedBox(height: 12),
      _SectionCard(
        title: tr('settingsAbout'),
        children: const [AboutTiles(tileBorderRadius: _bottomRadius)],
      ),
    ];
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panelBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              title.toUpperCase(),
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.disabledText,
              ),
            ),
          ),
          for (int i = 0; i < children.length; i++) children[i],
        ],
      ),
    );
  }
}
