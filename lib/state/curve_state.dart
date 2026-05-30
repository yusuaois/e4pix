import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/tone_curve.dart';

/// 持有当前曲线烘出的 256×1 纹理
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

  /// 由 develop_screen 在曲线变化时调用，重建纹理
  Future<void> update(ToneCurve curve) async {
    if (curve.isIdentity) {
      _swap(null);
      return;
    }
    final lut = curve.toLut(count: 256);
    final pixels = Uint8List(256 * 4);
    for (int i = 0; i < 256; i++) {
      final v = (lut[i] * 255).round().clamp(0, 255);
      pixels[i * 4] = v;
      pixels[i * 4 + 1] = v;
      pixels[i * 4 + 2] = v;
      pixels[i * 4 + 3] = 255;
    }
    final img = await _decode(pixels);
    if (_disposed) { img.dispose(); return; }
    _swap(img);
  }

  Future<ui.Image> _decode(Uint8List pixels) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, 256, 1, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  void _swap(ui.Image? next) {
    final old = _held;
    _held = next;
    state = next;
    if (old != null && old != next) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        try { old.dispose(); } catch (_) {}
      });
    }
  }
}

final curveTextureProvider =
    NotifierProvider<CurveTextureNotifier, ui.Image?>(CurveTextureNotifier.new);