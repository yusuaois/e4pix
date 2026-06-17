import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/providers.dart';
import '../app/theme_color_picker.dart';

class ThemeTiles extends ConsumerWidget {
  const ThemeTiles({super.key});

  static const List<Color> _presets = [
    Color(0xFFC0C0C0), // 亮灰
    Color(0xFFA0A0A0), // 中性灰
    Color(0xFF808080), // 中暗灰
    Color(0xFF606060), // 暗灰
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
            style: AppTypography.titleMedium,
          ),
          subtitle: Text(
            tr("settingsDynamicColorHint"),
            style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
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
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.mediumText,
                  ),
                ),
                const SizedBox(width: 16),
                for (final c in _presets) ...[
                  Swatch(
                    color: c,
                    selected: seed == c.toARGB32(),
                    onTap: () =>
                        ref.read(seedColorProvider.notifier).set(c.toARGB32()),
                  ),
                  const SizedBox(width: 10),
                ],
                Swatch.wheel(
                  selected: !isPreset,
                  current: Color(seed),
                  onTap: () async {
                    final picked = await showDialog<Color>(
                      context: context,
                      builder: (_) => ThemeColorWheelDialog(
                        initial: Color(seed),
                        isGrayscale: true,
                      ),
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

class Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool isWheel;
  final Color? current;

  const Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  }) : isWheel = false,
       current = null;

  const Swatch.wheel({
    super.key,
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
                    Color(0xFF121212),
                    Color(0xFF444444),
                    Color(0xFF999999),
                    Color(0xFFEEEEEE),
                    Color(0xFF999999),
                    Color(0xFF444444),
                    Color(0xFF121212),
                  ],
                )
              : null,
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.lightBorder,
            width: selected ? 3 : 1,
          ),
        ),
        child: isWheel
            ? const Icon(Icons.colorize, size: 15, color: AppColors.textPrimary)
            : (selected
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.textPrimary,
                    )
                  : null),
      ),
    );
  }
}
