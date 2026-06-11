import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/rgb_curves.dart';
import '../../render/curve_baker.dart';
import '../../render/lut_texture_cache.dart';
import '../providers.dart';

@immutable
class _ShaderBundle {
  final ui.FragmentProgram develop;
  final ui.FragmentProgram mask;
  final ui.FragmentProgram sharpen;
  final ui.FragmentProgram denoise;
  const _ShaderBundle({
    required this.develop,
    required this.mask,
    required this.sharpen,
    required this.denoise,
  });
}

// 并行加载全部 4 个 shader，首个访问触发批量加载
final _allShadersProvider = FutureProvider<_ShaderBundle>((ref) async {
  final results = await Future.wait([
    ui.FragmentProgram.fromAsset('assets/shaders/develop.shader'),
    ui.FragmentProgram.fromAsset('assets/shaders/develop_mask.shader'),
    ui.FragmentProgram.fromAsset('assets/shaders/sharpen.shader'),
    ui.FragmentProgram.fromAsset('assets/shaders/denoise.shader'),
  ]);
  for (final p in results) {
    p.fragmentShader(); // 预热编译
  }
  return _ShaderBundle(
    develop: results[0],
    mask: results[1],
    sharpen: results[2],
    denoise: results[3],
  );
});

// 保持 FutureProvider API 兼容：各 provider 复用并行加载结果
final shaderProgramProvider = FutureProvider<ui.FragmentProgram>((ref) async {
  return (await ref.watch(_allShadersProvider.future)).develop;
});

final maskShaderProgramProvider = FutureProvider<ui.FragmentProgram>((
  ref,
) async {
  return (await ref.watch(_allShadersProvider.future)).mask;
});

final sharpenShaderProgramProvider = FutureProvider<ui.FragmentProgram>((
  ref,
) async {
  return (await ref.watch(_allShadersProvider.future)).sharpen;
});

final denoiseShaderProgramProvider = FutureProvider<ui.FragmentProgram>((
  ref,
) async {
  return (await ref.watch(_allShadersProvider.future)).denoise;
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
  final ui.Image? textureA;
  final int sizeA;
  final String? nameA;
  final ui.Image? textureB;
  final int sizeB;
  final String? nameB;

  const LutState({
    this.textureA,
    this.sizeA = 0,
    this.nameA,
    this.textureB,
    this.sizeB = 0,
    this.nameB,
  });

  LutState copyWith({
    ui.Image? textureA,
    int? sizeA,
    String? nameA,
    ui.Image? textureB,
    int? sizeB,
    String? nameB,
    bool clearA = false,
    bool clearB = false,
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
  int _gen = 0;
  final _cache = LutTextureCache.instance;

  @override
  LutState build() {
    final nameA = ref.watch(
      currentParamsNotifierProvider.select((p) => p.lutNameA),
    );
    final nameB = ref.watch(
      currentParamsNotifierProvider.select((p) => p.lutNameB),
    );

    // 缓存命中则同步构造（切图前已预加载，命中即不闪）；未命中则异步加载后更新
    final cachedA = nameA.isEmpty ? null : _cache.peek(nameA);
    final cachedB = nameB.isEmpty ? null : _cache.peek(nameB);

    final allHit =
        (nameA.isEmpty || cachedA != null) &&
        (nameB.isEmpty || cachedB != null);

    if (!allHit) {
      _loadAsync(nameA, nameB);
    }

    return LutState(
      textureA: cachedA?.texture,
      sizeA: cachedA?.size ?? 0,
      nameA: nameA.isEmpty ? null : nameA,
      textureB: cachedB?.texture,
      sizeB: cachedB?.size ?? 0,
      nameB: nameB.isEmpty ? null : nameB,
    );
  }

  Future<void> _loadAsync(String nameA, String nameB) async {
    final gen = ++_gen;
    final texA = nameA.isEmpty ? null : await _cache.load(nameA);
    if (gen != _gen) return;
    final texB = nameB.isEmpty ? null : await _cache.load(nameB);
    if (gen != _gen) return;

    state = LutState(
      textureA: texA?.texture,
      sizeA: texA?.size ?? 0,
      nameA: nameA.isEmpty ? null : nameA,
      textureB: texB?.texture,
      sizeB: texB?.size ?? 0,
      nameB: nameB.isEmpty ? null : nameB,
    );
  }
}

final lutNotifierProvider = NotifierProvider<LutNotifier, LutState>(
  LutNotifier.new,
);

// ── 曲线纹理 ──

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
