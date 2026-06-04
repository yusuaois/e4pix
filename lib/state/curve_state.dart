import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/rgb_curves.dart';
import '../render/curve_baker.dart';
import 'providers.dart';

/// 持有当前曲线烘出的 256×4 纹理（行0=主 行1=R 行2=G 行3=B）
class CurveTextureNotifier extends Notifier<ui.Image?> {
  ui.Image? _held;
  bool _disposed = false;

  @override
  ui.Image? build() {
    ref.onDispose(() {
      _disposed = true;
      _held?.dispose();
    });
    return null;
  }

  /// 在曲线变化时调用，重建纹理
  Future<void> update(RgbCurves curves) async {
    final img = await bakeCurveTexture(curves);
    if (_disposed) {
      img?.dispose();
      return;
    }
    _swap(img);
  }

  void _swap(ui.Image? next) {
    final old = _held;
    _held = next;
    state = next;
    if (old != null && old != next) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        try {
          old.dispose();
        } catch (_) {}
      });
    }
  }
}

final curveTextureProvider = NotifierProvider<CurveTextureNotifier, ui.Image?>(
  CurveTextureNotifier.new,
);

final effectiveCurveTextureProvider = Provider<ui.Image?>((ref) {
  if (ref.watch(compareBypassProvider)) return null;
  return ref.watch(curveTextureProvider);
});
