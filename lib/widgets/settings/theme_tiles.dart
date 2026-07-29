import 'package:easy_localization/easy_localization.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/providers.dart';

class ThemeTiles extends ConsumerWidget {
  final BorderRadius? tileBorderRadius;
  const ThemeTiles({super.key, this.tileBorderRadius});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dynamicEnabled = ref.watch(dynamicColorEnabledProvider);
    final seed = ref.watch(seedColorProvider);
    final seedColor = Color(seed);

    return Column(
      children: [
        _buildDynamicColorTile(ref, dynamicEnabled),
        if (!dynamicEnabled) _buildSeedColorTile(context, ref, seedColor),
      ],
    );
  }

  Widget _buildDynamicColorTile(WidgetRef ref, bool dynamicEnabled) {
    return SwitchListTile(
      shape: dynamicEnabled && tileBorderRadius != null
          ? RoundedRectangleBorder(borderRadius: tileBorderRadius!)
          : null,
      secondary: const Icon(Icons.palette_outlined, size: 20),
      title: Text(tr("settingsDynamicColor"), style: AppTypography.titleMedium),
      subtitle: Text(
        tr("settingsDynamicColorHint"),
        style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
      ),
      value: dynamicEnabled,
      onChanged: (v) => ref.read(dynamicColorEnabledProvider.notifier).set(v),
    );
  }

  Widget _buildSeedColorTile(
    BuildContext context,
    WidgetRef ref,
    Color seedColor,
  ) {
    return ListTile(
      leading: ColorIndicator(
        width: 36,
        height: 36,
        borderRadius: 18,
        color: seedColor,
        elevation: 1,
        onSelectFocus: false,
      ),
      title: Text(tr("settingsCustomColor"), style: AppTypography.titleMedium),
      subtitle: Text(
        ColorTools.materialNameAndCode(seedColor),
        style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
      ),
      onTap: () async {
        final newColor = await showColorPickerDialog(
          context,
          seedColor,
          title: Text(
            tr("colorPickerTitle"),
            style: AppTypography.headlineSmall,
          ),
          width: 44,
          height: 44,
          borderRadius: 22,
          spacing: 6,
          runSpacing: 6,
          wheelDiameter: 180,
          showColorCode: true,
          colorCodeHasColor: true,
          showColorName: true,
          showMaterialName: true,
          showRecentColors: true,
          maxRecentColors: 5,
          enableOpacity: false,
          enableTonalPalette: false,
          pickersEnabled: const <ColorPickerType, bool>{
            ColorPickerType.both: false,
            ColorPickerType.primary: false,
            ColorPickerType.accent: false,
            ColorPickerType.bw: false,
            ColorPickerType.custom: false,
            ColorPickerType.wheel: true,
          },
          constraints: const BoxConstraints(minWidth: 300, maxWidth: 320),
        );
        ref.read(seedColorProvider.notifier).set(newColor.toARGB32());
      },
    );
  }
}
