import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/tethered_shot.dart';
import '../../core/theme/app_typography.dart';
import '../../services/ai/ai_color_service.dart';
import '../../state/providers.dart';

// 星级 + 旗标条
class RatingFlagBar extends ConsumerWidget {
  final bool compact;
  const RatingFlagBar({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeShotProvider);
    if (active == null) return const SizedBox.shrink();
    final notifier = ref.read(shotsNotifierProvider.notifier);

    void writeSidecar() {
      if (!ref.read(sidecarEnabledProvider)) return;
      final shots = ref.read(shotsNotifierProvider);
      final idx = shots.indexWhere((s) => s.path == active.path);
      if (idx < 0) return;
      final s = shots[idx];
      ref
          .read(sidecarWriterProvider)
          .writeNow(active.path, s.params, s.rating, s.flag);
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStars(active, notifier, writeSidecar),
          const SizedBox(width: 8),
          _buildFlagButton(
            active: active,
            notifier: notifier,
            writeSidecar: writeSidecar,
            flag: ShotFlag.pick,
            icon: Icons.flag,
            activeColor: AppColors.semanticSuccess,
            tooltipKey: 'flagPick',
          ),
          _buildFlagButton(
            active: active,
            notifier: notifier,
            writeSidecar: writeSidecar,
            flag: ShotFlag.reject,
            icon: Icons.block,
            activeColor: AppColors.semanticError,
            tooltipKey: 'flagReject',
          ),
        ],
      ),
    );
  }

  Widget _buildStars(
    TetheredShot active,
    ShotsNotifier notifier,
    VoidCallback writeSidecar,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          GestureDetector(
            onTap: () {
              notifier.updateRating(
                active.path,
                active.rating == i ? i - 1 : i,
              );
              writeSidecar();
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 4,
                vertical: compact ? 2.0 : 8.0,
              ),
              child: Icon(
                i <= active.rating ? Icons.star : Icons.star_border,
                size: 18,
                color: i <= active.rating
                    ? AppColors.semanticWarning
                    : AppColors.disabledText,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFlagButton({
    required TetheredShot active,
    required ShotsNotifier notifier,
    required VoidCallback writeSidecar,
    required ShotFlag flag,
    required IconData icon,
    required Color activeColor,
    required String tooltipKey,
  }) {
    final isActive = active.flag == flag;
    return IconButton(
      icon: Icon(
        icon,
        size: 16,
        color: isActive ? activeColor : AppColors.disabledText,
      ),
      tooltip: tr(tooltipKey),
      visualDensity: VisualDensity.compact,
      onPressed: () {
        notifier.updateFlag(active.path, isActive ? ShotFlag.none : flag);
        writeSidecar();
      },
    );
  }
}

class FullscreenExitButton extends ConsumerWidget {
  const FullscreenExitButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => ref.read(fullscreenPreviewProvider.notifier).set(false),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(
            Icons.fullscreen_exit,
            size: 22,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// AI Banner
class AIBanner extends ConsumerWidget {
  const AIBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(aiAutoNotifierProvider);

    if (ai.inProgress && ai.pendingSuggestion == null) {
      return _buildInProgressBanner(context);
    }
    if (ai.pendingSuggestion == null) return const SizedBox.shrink();

    return _buildSuggestionBanner(context, ai.pendingSuggestion!, ref);
  }

  Widget _buildInProgressBanner(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            tr("aiColorInProgress"),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.mediumText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionBanner(
    BuildContext context,
    AIColorSuggestion s,
    WidgetRef ref,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
      child: InkWell(
        onTap: () {
          ref.read(aiAutoNotifierProvider.notifier).applyPending();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: tr("aiColorSuggestionLabel"),
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: s.mood.isNotEmpty
                            ? s.mood
                            : tr("aiColorSuggestionReady"),
                        style: AppTypography.bodyMedium,
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(aiAutoNotifierProvider.notifier).applyPending(),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(tr("apply"), style: AppTypography.bodySmall),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(aiAutoNotifierProvider.notifier).dismissPending(),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  tr("ignore"),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.mediumText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
