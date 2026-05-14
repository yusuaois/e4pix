import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../core/models/tethered_shot.dart';

// 顶部状态条
class TetherStatusBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;
    return isPhone ? _buildPhone(context) : _buildDesktop(context);
  }

  Widget _buildPhone(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          const _PulsingDot(color: Colors.greenAccent),
          const SizedBox(width: 8),
          Text(
            'Tether',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.greenAccent.withOpacity(0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${tr("shotCount", args: [shotCount.toString()])}'
              '${lastShotAt == null ? '' : ' · ${_ago(lastShotAt!)}'}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.6),
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
                  ? Colors.greenAccent.withOpacity(0.85)
                  : Colors.orangeAccent.withOpacity(0.85),
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
              color: Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          _PulsingDot(color: Colors.greenAccent),
          const SizedBox(width: 10),
          Text(
            'Tether',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.greenAccent.withOpacity(0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              watchPath,
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withOpacity(0.7),
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${tr("shotCount", args: [shotCount.toString()])}'
            '${lastShotAt == null ? '' : ' · ${_ago(lastShotAt!)}'}',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.white.withOpacity(0.6),
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
            label: Text(tr("stop"), style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
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
        ? Colors.greenAccent.withOpacity(0.85)
        : Colors.orangeAccent.withOpacity(0.85);
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
          style: TextStyle(fontSize: 11, color: color),
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
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.4 + 0.6 * _c.value),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.4 * _c.value),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

// 底部缩略图条
class TetherThumbStrip extends StatelessWidget {
  final List<TetheredShot> shots;
  final TetheredShot? activeShot;
  final ValueChanged<TetheredShot> onSelect;
  final bool multiSelectMode;
  final List<TetheredShot> selectedShots;

  const TetherThumbStrip({
    super.key,
    required this.shots,
    required this.activeShot,
    required this.onSelect,
    this.multiSelectMode = false,
    this.selectedShots = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (shots.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B10),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: shots.length,
        itemBuilder: (ctx, i) {
          final shot = shots[shots.length - 1 - i];
          final isActive = shot == activeShot;
          final isPicked = selectedShots.contains(shot);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onSelect(shot),
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isPicked
                            ? const Color(0xFF6B5BFF)
                            : (isActive && !multiSelectMode
                                  ? const Color(0xFF6B5BFF)
                                  : Colors.transparent),
                        width: 2,
                      ),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        width: 110,
                        height: 70,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (shot.thumbnail != null)
                              RawImage(image: shot.thumbnail, fit: BoxFit.cover)
                            else
                              Container(
                                color: Colors.white.withOpacity(0.05),
                                alignment: Alignment.center,
                                child: shot.error != null
                                    ? Icon(
                                        Icons.broken_image_outlined,
                                        size: 18,
                                        color: Colors.redAccent.withOpacity(
                                          0.6,
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
                            if (multiSelectMode && !isPicked)
                              Container(color: Colors.black.withOpacity(0.35)),
                            if (multiSelectMode && isActive)
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: const Text(
                                    '当前',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      color: Colors.white,
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
                  if (multiSelectMode)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: isPicked
                              ? const Color(0xFF6B5BFF)
                              : Colors.black.withOpacity(0.55),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(isPicked ? 1 : 0.7),
                            width: 1.5,
                          ),
                        ),
                        child: isPicked
                            ? const Icon(
                                Icons.check,
                                size: 11,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
