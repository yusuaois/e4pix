import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/adjustment_params.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../services/sr/sr_service.dart';
import '../../../../state/providers.dart';
import '../shared.dart';

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
    _syncPreviewOffIfDisabled(p, previewEnabled);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel(title: 'Super Resolution'),
          SwitchTile.tile(
            label: tr('superResEnable'),
            value: p.srEnabled,
            onChanged: (v) {
              widget.onChanged(p.copyWith(srEnabled: v));
              if (v && !_modelLoaded) _loadModel();
            },
          ),
          _buildHint(),
          if (p.srEnabled) _buildEnabledContent(previewEnabled),
        ],
      ),
    );
  }

  void _syncPreviewOffIfDisabled(AdjustmentParams p, bool previewEnabled) {
    if (!p.srEnabled && previewEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(srPreviewEnabledProvider.notifier).set(false);
      });
    }
  }

  Widget _buildHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        tr('superResExperimentalHint'),
        style: AppTypography.bodySmall.copyWith(color: AppColors.disabledText),
      ),
    );
  }

  Widget _buildEnabledContent(bool previewEnabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        _buildScaleDisplay(),
        SwitchTile.tile(
          label: tr('superResPreview'),
          value: previewEnabled,
          onChanged: (v) {
            ref.read(srPreviewEnabledProvider.notifier).set(v);
          },
        ),
        _buildModelStatusRow(),
      ],
    );
  }

  Widget _buildScaleDisplay() {
    final p = widget.params;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Text(tr('superResScale'), style: AppTypography.titleSmall),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    );
  }

  Widget _buildModelStatusRow() {
    IconData icon;
    Color iconColor;
    String label;
    Color labelColor;
    if (_modelLoaded) {
      icon = Icons.check_circle_outline;
      iconColor = AppColors.semanticSuccess;
      label = tr('superResModelLoaded');
      labelColor = AppColors.semanticSuccess;
    } else if (_modelLoading) {
      icon = Icons.hourglass_top;
      iconColor = AppColors.semanticWarning;
      label = tr('superResModelLoading');
      labelColor = AppColors.disabledText;
    } else {
      icon = Icons.cloud_download_outlined;
      iconColor = AppColors.disabledText;
      label = tr('superResModelNotLoaded');
      labelColor = AppColors.disabledText;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(color: labelColor),
          ),
        ],
      ),
    );
  }
}
