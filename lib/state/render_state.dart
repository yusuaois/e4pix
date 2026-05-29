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
@immutable
class LutState {
  final ui.Image? textureA;
  final int sizeA;
  final String? nameA;
  final ui.Image? textureB;
  final int sizeB;
  final String? nameB;

  const LutState({
    this.textureA, this.sizeA = 0, this.nameA,
    this.textureB, this.sizeB = 0, this.nameB,
  });

  LutState copyWith({
    ui.Image? textureA, int? sizeA, String? nameA,
    ui.Image? textureB, int? sizeB, String? nameB,
    bool clearA = false, bool clearB = false,
  }) => LutState(
    textureA: clearA ? null : (textureA ?? this.textureA),
    sizeA: clearA ? 0 : (sizeA ?? this.sizeA),
    nameA: clearA ? null : (nameA ?? this.nameA),
    textureB: clearB ? null : (textureB ?? this.textureB),
    sizeB: clearB ? 0 : (sizeB ?? this.sizeB),
    nameB: clearB ? null : (nameB ?? this.nameB),
  );
}

class LutNotifier extends Notifier<LutState> {
  ui.Image? _heldA;
  ui.Image? _heldB;
  bool _disposeRegistered = false;
  bool _providerDisposed = false;

  void _registerOnDisposeOnce() {
    if (_disposeRegistered) return;
    _disposeRegistered = true;
    ref.onDispose(() {
      _providerDisposed = true;
      _heldA?.dispose(); _heldA = null;
      _heldB?.dispose(); _heldB = null;
    });
  }

  @override
  LutState build() {
    _registerOnDisposeOnce();
    return const LutState();
  }

  /// slot: 0 = A, 1 = B
  Future<void> loadFromCubeFile(String path, {int slot = 0}) async {
    final lut = await CubeLut.fromFile(path);
    final tex = await lut.toHaldStrip();
    _replaceTexture(slot, tex, size: lut.size, name: lut.name);
  }

  void clear({int slot = 0}) {
    final old = slot == 0 ? _heldA : _heldB;
    if (slot == 0) {
      _heldA = null;
      state = state.copyWith(clearA: true);
    } else {
      _heldB = null;
      state = state.copyWith(clearB: true);
    }
    _scheduleDispose(old);
  }

  void _replaceTexture(int slot, ui.Image tex,
      {required int size, required String name}) {
    final old = slot == 0 ? _heldA : _heldB;
    if (slot == 0) {
      _heldA = tex;
      state = state.copyWith(textureA: tex, sizeA: size, nameA: name);
    } else {
      _heldB = tex;
      state = state.copyWith(textureB: tex, sizeB: size, nameB: name);
    }
    if (old != null && old != tex) _scheduleDispose(old);
  }

  void _scheduleDispose(ui.Image? old) {
    if (old == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_providerDisposed) return;
      try { old.dispose(); } catch (_) {}
    });
  }
}

final lutNotifierProvider = NotifierProvider<LutNotifier, LutState>(LutNotifier.new);