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
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
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

/// 开关磁贴
///
/// 统一的开关行组件，支持两种视觉变体：
/// - [SwitchTile.tile] — 默认行式，匹配原标题样式
/// - [SwitchTile.header] — 大写 header 样式，激活/非激活动态文字色
class SwitchTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final EdgeInsetsGeometry padding;
  final bool uppercase;
  final TextStyle? textStyle;
  final Color? activeColor;
  final Color? inactiveColor;

  const SwitchTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    this.uppercase = false,
    this.textStyle,
    this.activeColor,
    this.inactiveColor,
  });

  /// 默认行式开关（原 `_SwitchTile`）
  factory SwitchTile.tile({
    Key? key,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchTile(
      key: key,
      label: label,
      value: value,
      onChanged: onChanged,
    );
  }

  /// 大写 header 开关（原 `_SwitchHeader`）
  factory SwitchTile.header({
    Key? key,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchTile(
      key: key,
      label: label,
      value: value,
      onChanged: onChanged,
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
      uppercase: true,
      textStyle: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w600),
      activeColor: AppColors.mediumText,
      inactiveColor: AppColors.disabledText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayLabel = uppercase ? label.toUpperCase() : label;

    TextStyle effectiveStyle = textStyle ?? AppTypography.titleSmall;
    if (activeColor != null || inactiveColor != null) {
      effectiveStyle = effectiveStyle.copyWith(
        color: value ? activeColor : inactiveColor,
      );
    }

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(displayLabel, style: effectiveStyle)),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

/// 首帧延迟构建：首帧渲染空占位，下一帧真正构建，减少 TabBarView 或列表初始开销
class LazyBuild extends StatefulWidget {
  final WidgetBuilder builder;
  const LazyBuild({super.key, required this.builder});

  @override
  State<LazyBuild> createState() => _LazyBuildState();
}

class _LazyBuildState extends State<LazyBuild> {
  bool _built = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _built = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_built) return const SizedBox.shrink();
    return widget.builder(context);
  }
}

/// 激活/非激活切换胶囊按钮
///
/// 用于二选一 / 多选一的互斥模式切换
/// 激活/非激活总开关请使用 [SwitchTile]
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
