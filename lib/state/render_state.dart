import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/lut/cube_lut.dart';

// Shader program (load once)
final shaderProgramProvider = FutureProvider<ui.FragmentProgram>((ref) async {
  return ui.FragmentProgram.fromAsset('shaders/develop.frag');
});
final maskShaderProgramProvider = FutureProvider<ui.FragmentProgram>((ref) async {
  return ui.FragmentProgram.fromAsset('shaders/develop_mask.frag');
});

// 1Hz ticker
final tickerProvider = StreamProvider<int>((ref) async* {
  int i = 0;
  while (true) {
    yield i++;
    await Future.delayed(const Duration(seconds: 1));
  }
});

// LUT
@immutable
class LutState {
  final ui.Image? texture;
  final int size;
  final String? name;
  final double intensity; 

  const LutState({
    this.texture,
    this.size = 0,
    this.name,
    this.intensity = 1.0,
  });

  bool get isLoaded => texture != null && size > 0;

  LutState copyWith({
    ui.Image? texture,
    int? size,
    String? name,
    double? intensity,
  }) =>
      LutState(
        texture: texture ?? this.texture,
        size: size ?? this.size,
        name: name ?? this.name,
        intensity: intensity ?? this.intensity,
      );
}

class LutNotifier extends Notifier<LutState> {
  ui.Image? _held;
  bool _disposeRegistered = false;
  bool _providerDisposed = false;

  void _registerOnDisposeOnce() {
    if (_disposeRegistered) return;
    _disposeRegistered = true;
    ref.onDispose(() {
      _providerDisposed = true;
      _held?.dispose();
      _held = null;
    });
  }

  @override
  LutState build() {
    _registerOnDisposeOnce();
    return const LutState();
  }

  Future<void> loadFromCubeFile(String path) async {
    final lut = await CubeLut.fromFile(path);
    final tex = await lut.toHaldStrip();
    _replaceTexture(tex, size: lut.size, name: lut.name);
  }

  Future<void> loadTestCinematic() async {
    final lut = CubeLut.testCinematic();
    final tex = await lut.toHaldStrip();
    _replaceTexture(tex, size: lut.size, name: lut.name);
  }

  Future<void> loadIdentity() async {
    final lut = CubeLut.identity();
    final tex = await lut.toHaldStrip();
    _replaceTexture(tex, size: lut.size, name: lut.name);
  }

  void clear() {
    final old = _held;
    _held = null;
    state = const LutState();
    if (old != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_providerDisposed) return;
        try {
          old.dispose();
        } catch (_) {}
      });
    }
  }

  void _replaceTexture(ui.Image tex, {required int size, required String name}) {
    final old = _held;
    _held = tex;
    state = state.copyWith(texture: tex, size: size, name: name);
    if (old != null && old != tex) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_providerDisposed) return;
        try {
          old.dispose();
        } catch (_) {}
      });
    }
  }
}

final lutNotifierProvider = NotifierProvider<LutNotifier, LutState>(LutNotifier.new);