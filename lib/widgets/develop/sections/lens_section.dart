import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/lens_correction_params.dart';
import '../../../core/models/perspective_params.dart';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: "lens",
          trailing: !lens.isNeutral || !persp.isIdentity
              ? GestureDetector(
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
                  child: Text(
                    'reset',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : null,
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
        const Divider(height: 1, color: Colors.white12),

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

// ── 与 DetailSection grainAdvanced 风格对齐的 Switch 标题行 ──────────────
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
                color: Colors.white.withValues(alpha: value ? 0.6 : 0.4),
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

// ── 与 DetailSection grainAdvanced 动画一致的展开区域 ────────────────────
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
