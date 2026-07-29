import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/tethered_shot.dart';
import '../../core/theme/app_typography.dart';
import '../../state/providers.dart';

// 顶部状态条
class TetherStatusBar extends ConsumerWidget {
  final String watchPath;
  final int shotCount;
  final DateTime? lastShotAt;
  final VoidCallback onStop;

  final bool preserveParams;
  final ValueChanged<bool> onPreserveChanged;

  const TetherStatusBar({
    super.key,
    required this.watchPath,
    required this.shotCount,
    required this.lastShotAt,
    required this.onStop,
    required this.preserveParams,
    required this.onPreserveChanged,
  });

  String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 5) return tr("justNow");
    if (s < 60) return tr("secondsAgo", args: [s.toString()]);
    final m = s ~/ 60;
    if (m < 60) return tr("minutesAgo", args: [m.toString()]);
    return tr("hoursAgo", args: [(m ~/ 60).toString()]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(tickerProvider);
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;
    return isPhone ? _buildPhone(context) : _buildDesktop(context);
  }

  Widget _buildPhone(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Row(
        children: [
          const _PulsingDot(color: AppColors.semanticSuccess),
          const SizedBox(width: 8),
          Text(
            'Tether',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${tr("shotCount", args: [shotCount.toString()])}'
              '${lastShotAt == null ? '' : ' · ${_ago(lastShotAt!)}'}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.mediumText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: preserveParams ? tr("preserveMode") : tr("isolateMode"),
            onPressed: () => onPreserveChanged(!preserveParams),
            icon: Icon(
              preserveParams ? Icons.link_rounded : Icons.link_off_rounded,
              color: preserveParams
                  ? AppColors.activeValue
                  : AppColors.semanticWarning.withValues(alpha: 0.85),
            ),
          ),
          IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: tr("stopCameraTether"),
            onPressed: onStop,
            icon: const Icon(
              Icons.stop_circle_outlined,
              color: AppColors.semanticError,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Row(
        children: [
          const _PulsingDot(color: AppColors.semanticSuccess),
          const SizedBox(width: 10),
          Text(
            'Tether',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.activeValue,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              watchPath,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.mediumText,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${tr("shotCount", args: [shotCount.toString()])}'
            '${lastShotAt == null ? '' : ' · ${_ago(lastShotAt!)}'}',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.mediumText,
            ),
          ),
          const SizedBox(width: 14),

          _PreserveToggle(
            preserved: preserveParams,
            onChanged: onPreserveChanged,
          ),
          const SizedBox(width: 6),

          TextButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined, size: 14),
            label: Text(tr("stop"), style: AppTypography.bodySmall),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.semanticError,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreserveToggle extends StatelessWidget {
  final bool preserved;
  final ValueChanged<bool> onChanged;
  const _PreserveToggle({required this.preserved, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final color = preserved
        ? AppColors.activeValue
        : AppColors.semanticWarning.withValues(alpha: 0.85);
    return Tooltip(
      message: preserved
          ? tr("preserveModeDescription")
          : tr("isolateModeDescription"),
      child: TextButton.icon(
        onPressed: () => onChanged(!preserved),
        icon: Icon(
          preserved ? Icons.link_rounded : Icons.link_off_rounded,
          size: 14,
          color: color,
        ),
        label: Text(
          preserved ? tr("preserveMode") : tr("isolateMode"),
          style: AppTypography.bodySmall.copyWith(color: color),
        ),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.4 + 0.6 * _c.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4 * _c.value),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 底部缩略图条
class TetherThumbStrip extends StatefulWidget {
  final List<TetheredShot> shots;
  final TetheredShot? activeShot;
  final ValueChanged<TetheredShot> onSelect;
  final bool multiSelectMode;
  final List<TetheredShot> selectedShots;
  final Axis axis;

  const TetherThumbStrip({
    super.key,
    required this.shots,
    required this.activeShot,
    required this.onSelect,
    this.multiSelectMode = false,
    this.selectedShots = const [],
    this.axis = Axis.horizontal,
  });

  @override
  State<TetherThumbStrip> createState() => _TetherThumbStripState();
}

class _TetherThumbStripState extends State<TetherThumbStrip> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.shots.isEmpty) return const SizedBox.shrink();
    final vertical = widget.axis == Axis.vertical;

    return Container(
      width: vertical ? 96 : null,
      height: vertical ? null : 92,
      decoration: const BoxDecoration(color: AppColors.surfaceBg),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
            PointerDeviceKind.trackpad,
          },
        ),
        child: Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final offset = pointerSignal.scrollDelta.dy;
              final target = _scrollController.offset + offset;
              _scrollController.jumpTo(
                target.clamp(0.0, _scrollController.position.maxScrollExtent),
              );
            }
          },
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: widget.axis,
            reverse: !vertical,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            // itemExtent = 缩略图尺寸 + padding(4×2)
            // vertical: 54 + 8 = 62, horizontal: 110 + 8 = 118
            itemExtent: vertical ? 62 : 118,
            itemCount: widget.shots.length,
            itemBuilder: (ctx, i) => _buildItem(i, vertical),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(int i, bool vertical) {
    final idx = vertical ? i : widget.shots.length - 1 - i;
    final shot = widget.shots[idx];
    final isActive = shot == widget.activeShot;
    final isPicked = widget.selectedShots.contains(shot);

    return Padding(
      padding: vertical
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => widget.onSelect(shot),
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isPicked
                      ? Theme.of(context).colorScheme.primary
                      : (isActive && !widget.multiSelectMode
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent),
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  width: vertical ? 76 : 110,
                  height: vertical ? 54 : 70,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (shot.thumbnail != null)
                        RawImage(image: shot.thumbnail, fit: BoxFit.cover)
                      else
                        Container(
                          color: AppColors.subtleBorder,
                          alignment: Alignment.center,
                          child: shot.error != null
                              ? Icon(
                                  Icons.broken_image_outlined,
                                  size: 18,
                                  color: AppColors.semanticError.withValues(
                                    alpha: 0.6,
                                  ),
                                )
                              : const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                ),
                        ),
                      if (widget.multiSelectMode && !isPicked)
                        Container(color: Colors.black.withValues(alpha: 0.35)),
                      if (shot.rating > 0)
                        Positioned(
                          left: 3,
                          bottom: 3,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              shot.rating,
                              (_) => const Icon(
                                Icons.star,
                                size: 9,
                                color: AppColors.semanticWarning,
                              ),
                            ),
                          ),
                        ),
                      if (shot.flag != ShotFlag.none)
                        Positioned(
                          top: 3,
                          right: 3,
                          child: Icon(
                            shot.flag == ShotFlag.pick
                                ? Icons.flag
                                : Icons.flag_outlined,
                            size: 12,
                            color: shot.flag == ShotFlag.pick
                                ? AppColors.semanticSuccess
                                : AppColors.semanticError,
                          ),
                        ),
                      if (widget.multiSelectMode && isActive)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'Now',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textPrimary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.multiSelectMode)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: isPicked
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isPicked
                          ? AppColors.textPrimary
                          : AppColors.mediumText,
                      width: 1.5,
                    ),
                  ),
                  child: isPicked
                      ? const Icon(
                          Icons.check,
                          size: 11,
                          color: AppColors.textPrimary,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
