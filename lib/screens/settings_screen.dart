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
import '../widgets/settings/about_tiles.dart';

export '../widgets/settings/about_tiles.dart' show UpdateDialog;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(tr("settings")),
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
      ),
      body: ListView(
        children: [
          _SectionHeader(tr("settingsTether")),
          const TetherFolderTile(),
          const ImportModeTiles(),
          const SizedBox(height: 16),

          _SectionHeader(tr("aiColor")),
          const AISettingsLink(),
          const SizedBox(height: 16),

          _SectionHeader(tr("settingsTheme")),
          const ThemeTiles(),
          const SizedBox(height: 16),

          _SectionHeader(tr("settingsRender")),
          const QualityTiles(),
          const SizedBox(height: 16),

          _SectionHeader(tr("settingsEditing")),
          const EditingTiles(),
          const SizedBox(height: 16),

          _SectionHeader(tr("settingsAbout")),
          const AboutTiles(),
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
        style: AppTypography.labelSmall.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: AppColors.faintText,
        ),
      ),
    );
  }
}
