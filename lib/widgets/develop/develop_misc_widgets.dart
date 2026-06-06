import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/tethered_shot.dart';
import '../../state/providers.dart';

// 星级 + 旗标条
class RatingFlagBar extends ConsumerWidget {
  const RatingFlagBar({super.key});

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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 5 颗星
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
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Icon(
                i <= active.rating ? Icons.star : Icons.star_border,
                size: 18,
                color: i <= active.rating
                    ? Colors.amberAccent
                    : Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ),
        const SizedBox(width: 8),
        // 旗标
        IconButton(
          icon: Icon(
            Icons.flag,
            size: 16,
            color: active.flag == ShotFlag.pick
                ? Colors.greenAccent
                : Colors.white.withValues(alpha: 0.4),
          ),
          tooltip: tr('flagPick'),
          visualDensity: VisualDensity.compact,
          onPressed: () {
            notifier.updateFlag(
              active.path,
              active.flag == ShotFlag.pick ? ShotFlag.none : ShotFlag.pick,
            );
            writeSidecar();
          },
        ),
        IconButton(
          icon: Icon(
            Icons.block,
            size: 16,
            color: active.flag == ShotFlag.reject
                ? Colors.redAccent
                : Colors.white.withValues(alpha: 0.4),
          ),
          tooltip: tr('flagReject'),
          visualDensity: VisualDensity.compact,
          onPressed: () {
            notifier.updateFlag(
              active.path,
              active.flag == ShotFlag.reject ? ShotFlag.none : ShotFlag.reject,
            );
            writeSidecar();
          },
        ),
      ],
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
        onTap: () => ref.read(fullscreenPreviewProvider.notifier).state = false,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.fullscreen_exit, size: 22, color: Colors.white),
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
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }
    if (ai.pendingSuggestion == null) return const SizedBox.shrink();

    final s = ai.pendingSuggestion!;
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
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: s.mood.isNotEmpty
                            ? s.mood
                            : tr("aiColorSuggestionReady"),
                        style: const TextStyle(fontSize: 11.5),
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
                child: Text(tr("apply"), style: const TextStyle(fontSize: 11)),
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
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
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
