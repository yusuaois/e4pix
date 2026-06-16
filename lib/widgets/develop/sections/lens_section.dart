import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/lens_correction_params.dart';
import '../../../core/models/perspective_params.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/lens/lensfun_database.dart';
import '../../../state/providers.dart';
import 'shared.dart';

class LensSection extends ConsumerWidget {
  const LensSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = ref.watch(currentParamsNotifierProvider);
    final lens = params.lensCorrection;
    final persp = params.perspective;

    void setLens(LensCorrectionParams v) {
      ref
          .read(currentParamsNotifierProvider.notifier)
          .update(params.copyWith(lensCorrection: v));
    }

    void setPersp(PerspectiveParams v) {
      ref
          .read(currentParamsNotifierProvider.notifier)
          .update(params.copyWith(perspective: v));
    }

    Future<void> autoDetect() async {
      final metadata = ref.read(imageNotifierProvider).value?.metadata;
      if (metadata == null) {
        _snack(context, 'No image metadata');
        return;
      }
      final db = LensfunDatabase.instance;
      await db.ensureLoaded();
      final cal = db.lookup(
        cameraMake: metadata.cameraMake,
        cameraModel: metadata.cameraModel,
        lensModel: metadata.lensModel,
        focalLength: metadata.focalLength,
        aperture: metadata.aperture,
      );
      if (!context.mounted) return;
      if (cal == null) {
        _snack(
          context,
          'No lens profile: ${metadata.cameraModel} / ${metadata.lensModel}',
        );
        return;
      }

      // TCA poly3: R 通道缩放 vr + br*r²，B 通道缩放 vb + bb*r²
      // UI 的 caRed/caBlue 是常数缩放因子，取线性项 vr/vb 做主校正
      ref
          .read(currentParamsNotifierProvider.notifier)
          .update(
            params.copyWith(
              lensCorrection: LensCorrectionParams(
                enabled: true,
                caRed: cal.tcaVr,
                caBlue: cal.tcaVb,
                distortionEnabled: true,
                distortionK1: cal.distortionA,
                distortionK2: cal.distortionB,
                distortionK3: cal.distortionC,
                vignettingEnabled: true,
                vignettingK1: cal.vignettingK1,
                vignettingK2: cal.vignettingK2,
                vignettingK3: cal.vignettingK3,
              ),
            ),
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: "lens",
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: autoDetect,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    'Auto',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (!lens.isNeutral || !persp.isIdentity) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    ref
                        .read(currentParamsNotifierProvider.notifier)
                        .update(
                          params.copyWith(
                            lensCorrection: LensCorrectionParams.neutral,
                            perspective: PerspectiveParams.identity,
                          ),
                        );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      'reset',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.faintText,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── CA 色差校正 ──
        _SwitchHeader(
          label: tr('lensCAEnabled'),
          value: lens.enabled,
          onChanged: (v) => setLens(lens.copyWith(enabled: v)),
        ),
        _AnimatedSection(
          expanded: lens.enabled,
          children: [
            DevelopSliderTile(
              label: tr('lensCARed'),
              value: lens.caRed,
              min: 0.8,
              max: 1.2,
              fractionDigits: 4,
              resetValue: 1.0,
              onChanged: (v) => setLens(lens.copyWith(caRed: v)),
            ),
            DevelopSliderTile(
              label: tr('lensCABlue'),
              value: lens.caBlue,
              min: 0.8,
              max: 1.2,
              fractionDigits: 4,
              resetValue: 1.0,
              onChanged: (v) => setLens(lens.copyWith(caBlue: v)),
            ),
          ],
        ),

        // ── 畸变校正 ──
        _SwitchHeader(
          label: tr('lensDistortionEnabled'),
          value: lens.distortionEnabled,
          onChanged: (v) => setLens(lens.copyWith(distortionEnabled: v)),
        ),
        _AnimatedSection(
          expanded: lens.distortionEnabled,
          children: [
            DevelopSliderTile(
              label: tr('lensDistortionK1'),
              value: lens.distortionK1,
              min: -0.5,
              max: 0.5,
              fractionDigits: 4,
              resetValue: 0.0,
              onChanged: (v) => setLens(lens.copyWith(distortionK1: v)),
            ),
            DevelopSliderTile(
              label: tr('lensDistortionK2'),
              value: lens.distortionK2,
              min: -0.5,
              max: 0.5,
              fractionDigits: 4,
              resetValue: 0.0,
              onChanged: (v) => setLens(lens.copyWith(distortionK2: v)),
            ),
            DevelopSliderTile(
              label: tr('lensDistortionK3'),
              value: lens.distortionK3,
              min: -0.5,
              max: 0.5,
              fractionDigits: 4,
              resetValue: 0.0,
              onChanged: (v) => setLens(lens.copyWith(distortionK3: v)),
            ),
          ],
        ),

        // ── 暗角校正 ──
        _SwitchHeader(
          label: tr('lensVignettingEnabled'),
          value: lens.vignettingEnabled,
          onChanged: (v) => setLens(lens.copyWith(vignettingEnabled: v)),
        ),
        _AnimatedSection(
          expanded: lens.vignettingEnabled,
          children: [
            DevelopSliderTile(
              label: tr('lensVignettingK1'),
              value: lens.vignettingK1,
              min: -1.0,
              max: 1.0,
              fractionDigits: 4,
              resetValue: 0.0,
              onChanged: (v) => setLens(lens.copyWith(vignettingK1: v)),
            ),
            DevelopSliderTile(
              label: tr('lensVignettingK2'),
              value: lens.vignettingK2,
              min: -1.0,
              max: 1.0,
              fractionDigits: 4,
              resetValue: 0.0,
              onChanged: (v) => setLens(lens.copyWith(vignettingK2: v)),
            ),
            DevelopSliderTile(
              label: tr('lensVignettingK3'),
              value: lens.vignettingK3,
              min: -1.0,
              max: 1.0,
              fractionDigits: 4,
              resetValue: 0.0,
              onChanged: (v) => setLens(lens.copyWith(vignettingK3: v)),
            ),
          ],
        ),

        const SizedBox(height: 8),
        Divider(height: 1, color: AppColors.faintBorder),

        // ── 透视矫正 ──
        SectionLabel(title: tr('perspective')),
        DevelopSliderTile(
          label: tr('perspectiveHorizontal'),
          value: persp.currentHorizontal(),
          min: -60,
          max: 60,
          fractionDigits: 1,
          resetValue: 0,
          onChanged: (v) => setPersp(persp.withHorizontalKeystone(v)),
        ),
        DevelopSliderTile(
          label: tr('perspectiveVertical'),
          value: persp.currentVertical(),
          min: -60,
          max: 60,
          fractionDigits: 1,
          resetValue: 0,
          onChanged: (v) => setPersp(persp.withVerticalKeystone(v)),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _SwitchHeader extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchHeader({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
                color: value ? AppColors.mediumText : AppColors.disabledText,
              ),
            ),
          ),
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

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 11)),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class _AnimatedSection extends StatelessWidget {
  final bool expanded;
  final List<Widget> children;

  const _AnimatedSection({required this.expanded, required this.children});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: expanded ? 1.0 : 0.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [const SizedBox(height: 4), ...children],
          ),
        ),
      ),
    );
  }
}
