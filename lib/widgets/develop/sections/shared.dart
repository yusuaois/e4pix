import 'package:flutter/material.dart';
import '../../../core/constants/math_constants.dart';
import '../../../core/theme/app_colors.dart';

import '../../../core/theme/app_typography.dart';
import '../tracked_slider.dart';

// 通用滑块
class DevelopSliderTile extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String suffix;
  final int fractionDigits;
  final double? resetValue; // 若提供，双击重置到此值且使用该值作为"中性"判断
  final EdgeInsets? padding;

  const DevelopSliderTile({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
    this.fractionDigits = 0,
    this.resetValue,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final neutralValue =
        resetValue ?? (min < 0 && max > 0 ? 0.0 : (min + max) / 2);
    final isNeutral = (value - neutralValue).abs() < kParamEpsilon;
    final display = value.toStringAsFixed(fractionDigits);
    final sign = value > 0 ? '+' : '';

    return Padding(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: AppTypography.titleSmall)),
              GestureDetector(
                onDoubleTap: () => onChanged(neutralValue),
                child: Text(
                  '$sign$display$suffix',
                  style: AppTypography.bodyMedium.copyWith(
                    fontFamily: 'monospace',
                    color: isNeutral
                        ? AppColors.disabledText
                        : AppColors.activeValue,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3),
            child: TrackedSlider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// 分区标签
class SectionLabel extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionLabel({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.disabledText,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

/// 激活/非激活切换胶囊按钮
///
/// 在画笔 Section 面板中用于切换工具激活状态和模式开关
/// 激活状态下显示高亮背景、亮色边框和活跃文字色；
/// 非激活状态下显示低调背景和暗色文字
class PillChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const PillChip({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.activeBg : AppColors.dividerLine,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? AppColors.lightBorder.withValues(alpha: 0.6)
                : AppColors.subtleBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? AppColors.activeValue : AppColors.mediumText,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: isActive ? AppColors.activeValue : AppColors.mediumText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
