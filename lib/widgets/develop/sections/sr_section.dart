import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/adjustment_params.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../services/sr/sr_service.dart';
import '../../../state/providers.dart';
import 'shared.dart';

/// 超分辨率 Section
///
/// - 标题 "Super Resolution"
/// - 开关 "启用超分辨率"
/// - 开启后显示：放大倍数、预览效果、模型状态
class SrSection extends ConsumerStatefulWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;

  const SrSection({super.key, required this.params, required this.onChanged});

  @override
  ConsumerState<SrSection> createState() => _SrSectionState();
}

class _SrSectionState extends ConsumerState<SrSection> {
  bool _modelLoaded = false;
  bool _modelLoading = false;

  @override
  void initState() {
    super.initState();
    if (SrService.instance.available) {
      _modelLoaded = true;
    }
  }

  Future<void> _loadModel() async {
    if (_modelLoading || _modelLoaded) return;
    setState(() => _modelLoading = true);
    try {
      final ok = await SrService.instance.ensureLoaded();
      if (mounted) {
        setState(() {
          _modelLoading = false;
          _modelLoaded = ok;
        });
      }
    } catch (e) {
      debugPrint('[SrSection] Model load failed: $e');
      if (mounted) setState(() => _modelLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.params;
    final previewEnabled = ref.watch(srPreviewEnabledProvider);

    // 参数重置时同步关闭预览开关
    if (!p.srEnabled && previewEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(srPreviewEnabledProvider.notifier).state = false;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Super Resolution'),

        // ── 总开关 ──
        _SwitchTile(
          label: tr('superResEnable'),
          value: p.srEnabled,
          onChanged: (v) {
            widget.onChanged(p.copyWith(srEnabled: v));
            if (v && !_modelLoaded) _loadModel();
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            tr('superResExperimentalHint'),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.disabledText,
            ),
          ),
        ),

        // ── 开启后的内容 ──
        if (p.srEnabled) ...[
          const SizedBox(height: 4),

          // 放大倍数
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Text(tr('superResScale'), style: AppTypography.titleSmall),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.elevatedBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${p.srScale}x',
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.activeValue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 预览效果开关
          _SwitchTile(
            label: tr('superResPreview'),
            value: previewEnabled,
            onChanged: (v) {
              ref.read(srPreviewEnabledProvider.notifier).state = v;
            },
          ),

          // 模型状态
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(
                  _modelLoaded
                      ? Icons.check_circle_outline
                      : (_modelLoading
                            ? Icons.hourglass_top
                            : Icons.cloud_download_outlined),
                  size: 16,
                  color: _modelLoaded
                      ? AppColors.semanticSuccess
                      : (_modelLoading
                            ? AppColors.semanticWarning
                            : AppColors.disabledText),
                ),
                const SizedBox(width: 8),
                Text(
                  _modelLoaded
                      ? tr('superResModelLoaded')
                      : (_modelLoading
                            ? tr('superResModelLoading')
                            : tr('superResModelNotLoaded')),
                  style: AppTypography.labelMedium.copyWith(
                    color: _modelLoaded
                        ? AppColors.semanticSuccess
                        : AppColors.disabledText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 开关 Tile
class _SwitchTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.titleSmall)),
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
