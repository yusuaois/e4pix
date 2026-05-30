import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/rgb_curves.dart';

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
    if (curves.isIdentity) {
      _swap(null);
      return;
    }
    final master = curves.master.toLut(count: 256);
    final r = curves.red.toLut(count: 256);
    final g = curves.green.toLut(count: 256);
    final b = curves.blue.toLut(count: 256);

    // 256 宽 × 4 高，每行一条曲线，值塞 R/G/B（灰度），A=255
    final pixels = Uint8List(256 * 4 * 4); // w * h * rgba
    void writeRow(int row, Float32List lut) {
      for (int x = 0; x < 256; x++) {
        final idx = (row * 256 + x) * 4;
        final v = (lut[x] * 255).round().clamp(0, 255);
        pixels[idx] = v;
        pixels[idx + 1] = v;
        pixels[idx + 2] = v;
        pixels[idx + 3] = 255;
      }
    }

    writeRow(0, master);
    writeRow(1, r);
    writeRow(2, g);
    writeRow(3, b);

    final img = await _decode(pixels, 256, 4);
    if (_disposed) {
      img.dispose();
      return;
    }
    _swap(img);
  }

  Future<ui.Image> _decode(Uint8List pixels, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
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

final curveTextureProvider =
    NotifierProvider<CurveTextureNotifier, ui.Image?>(CurveTextureNotifier.new);