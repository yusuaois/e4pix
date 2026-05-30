import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/compare_state.dart';
import '../state/curve_state.dart';

class CompareButton extends ConsumerWidget {
  const CompareButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(compareBypassProvider);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          ref.read(compareBypassProvider.notifier).state = true;
        },
        onPointerUp: (_) {
          ref.read(compareBypassProvider.notifier).state = false;
        },
        onPointerCancel: (_) {
          ref.read(compareBypassProvider.notifier).state = false;
        },
        child: Tooltip(
          message: tr('compareHint'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            margin: const EdgeInsets.symmetric(horizontal: 2),
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
              Icons.compare,
              size: 20,
              color: active ? Colors.amber : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

final effectiveCurveTextureProvider = Provider<ui.Image?>((ref) {
  if (ref.watch(compareBypassProvider)) return null;
  return ref.watch(curveTextureProvider);
});
