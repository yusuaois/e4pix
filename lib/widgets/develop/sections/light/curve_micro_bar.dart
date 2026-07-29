import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/rgb_curves.dart';
import '../../../../core/models/tone_curve.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../state/providers.dart';

/// 竖屏曲线模式选择栏
class CurveMicroBar extends ConsumerWidget {
  final VoidCallback onDone;

  const CurveMicroBar({super.key, required this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(activeOverlayProvider) as CurveActiveOverlay;
    final channel = overlay.channel;
    final curves = ref.watch(
      currentParamsNotifierProvider.select((p) => p.curves),
    );
    final curve = switch (channel) {
      1 => curves.red,
      2 => curves.green,
      3 => curves.blue,
      4 => curves.luminance,
      _ => curves.master,
    };
    final lineColor = _lineColor(context, channel);

    return Container(
      color: AppColors.panelBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context),
          _buildChannelRow(context, ref, lineColor),
          _buildFooter(context, ref, channel, curves, curve),
        ],
      ),
    );
  }

  Color _lineColor(BuildContext context, int channel) => switch (channel) {
    1 => AppColors.curveRed,
    2 => AppColors.curveGreen,
    3 => AppColors.curveBlue,
    4 => AppColors.curveLum,
    _ => Theme.of(context).colorScheme.primary,
  };

  void _resetCurve(WidgetRef ref, int channel, RgbCurves curves) {
    final next = switch (channel) {
      1 => curves.copyWith(red: ToneCurve.identity),
      2 => curves.copyWith(green: ToneCurve.identity),
      3 => curves.copyWith(blue: ToneCurve.identity),
      4 => curves.copyWith(luminance: ToneCurve.identity),
      _ => curves.copyWith(master: ToneCurve.identity),
    };
    final params = ref.read(currentParamsNotifierProvider);
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(curves: next));
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: Row(
        children: [
          Text(
            'CURVE',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.disabledText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onDone,
            child: Text(
              tr('done'),
              style: AppTypography.bodyLarge.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelRow(
    BuildContext context,
    WidgetRef ref,
    Color lineColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sectionHorizontal,
      ),
      child: Row(
        children: [
          _chTab(context, ref, 'RGB', 0, lineColor),
          _chTab(context, ref, 'R', 1, AppColors.curveRed),
          _chTab(context, ref, 'G', 2, AppColors.curveGreen),
          _chTab(context, ref, 'B', 3, AppColors.curveBlue),
          _chTab(context, ref, tr('lum'), 4, AppColors.curveLum),
        ],
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    WidgetRef ref,
    int channel,
    RgbCurves curves,
    ToneCurve curve,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            tr('curveHint'),
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.disabledText,
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: curve.isIdentity
                ? null
                : () => _resetCurve(ref, channel, curves),
            child: Text(tr('reset'), style: AppTypography.bodyLarge),
          ),
        ],
      ),
    );
  }

  Widget _chTab(
    BuildContext context,
    WidgetRef ref,
    String label,
    int ch,
    Color color,
  ) {
    final sel =
        (ref.watch(activeOverlayProvider) as CurveActiveOverlay).channel == ch;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(activeOverlayProvider.notifier).setChannel(ch),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: sel ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: sel ? color : AppColors.faintBorder,
              width: sel ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: AppTypography.labelMedium.copyWith(
              color: sel ? color : AppColors.mediumText,
              fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
