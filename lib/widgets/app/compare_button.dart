import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

class CompareButton extends ConsumerStatefulWidget {
  final double boxSize;
  final double iconSize;
  const CompareButton({super.key, this.boxSize = 40, this.iconSize = 20});

  @override
  ConsumerState<CompareButton> createState() => _CompareButtonState();
}

class _CompareButtonState extends ConsumerState<CompareButton> {
  // 记录长按前所处的模式
  CompareViewMode _preHoldMode = CompareViewMode.off;

  void _toggleSplit() {
    final cur = ref.read(compareViewModeProvider);
    if (cur == CompareViewMode.hold) return;

    ref
        .read(compareViewModeProvider.notifier)
        .state = cur == CompareViewMode.split
        ? CompareViewMode.off
        : CompareViewMode.split;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(compareViewModeProvider);
    final active = mode != CompareViewMode.off;

    return Tooltip(
      message: mode == CompareViewMode.split
          ? tr('splitCompareExit')
          : tr('compareHint'),
      child: SizedBox(
        width: widget.boxSize,
        height: widget.boxSize,
        child: Center(
          child: GestureDetector(
            onTap: _toggleSplit,
            onLongPressStart: (_) {
              _preHoldMode = ref.read(compareViewModeProvider);
              ref.read(compareViewModeProvider.notifier).state =
                  CompareViewMode.hold;
            },
            onLongPressEnd: (_) {
              ref.read(compareViewModeProvider.notifier).state = _preHoldMode;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: widget.boxSize - 8,
              height: widget.boxSize - 8,
              decoration: BoxDecoration(
                color: active
                    ? Colors.amber.withValues(alpha: 0.25)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: active ? Colors.amber : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Icon(
                mode == CompareViewMode.split
                    ? Icons.vertical_split
                    : Icons.compare,
                size: widget.iconSize,
                color: active ? Colors.amber : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
