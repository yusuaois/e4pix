import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/compare_state.dart';

class CompareButton extends ConsumerWidget {
  final double boxSize;
  final double iconSize;
  const CompareButton({super.key, this.boxSize = 40, this.iconSize = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(compareBypassProvider);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => ref.read(compareBypassProvider.notifier).state = true,
        onPointerUp: (_) => ref.read(compareBypassProvider.notifier).state = false,
        onPointerCancel: (_) => ref.read(compareBypassProvider.notifier).state = false,
        child: Tooltip(
          message: tr('compareHint'),
          child: SizedBox(
            width: boxSize,
            height: boxSize,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: boxSize - 8,    // 内层背景框略小，留边距
                height: boxSize - 8,
                decoration: BoxDecoration(
                  color: active ? Colors.amber.withValues(alpha: 0.25) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: active ? Colors.amber : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.compare,
                  size: iconSize,
                  color: active ? Colors.amber : Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

