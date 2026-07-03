import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/models/rgb_curves.dart';
import '../../render/curve_baker.dart';
import '../../render/lut_texture_cache.dart';
import '../providers.dart';
import '../utils/texture_notifier.dart';

@immutable
class _ShaderBundle {
  final ui.FragmentProgram develop;
  final ui.FragmentProgram mask;
  final ui.FragmentProgram sharpen;
  final ui.FragmentProgram denoise;
  final ui.FragmentProgram perspective;
  final ui.FragmentProgram lensCorrect;
  final ui.FragmentProgram spotRemove;
  const _ShaderBundle({
    required this.develop,
    required this.mask,
    required this.sharpen,
    required this.denoise,
    required this.perspective,
    required this.lensCorrect,
    required this.spotRemove,
  });
}

// 并行加载全部 7 个 shader，首个访问触发批量加载
final _allShadersProvider = FutureProvider<_ShaderBundle>((ref) async {
  final results = await Future.wait([
    ui.FragmentProgram.fromAsset('assets/shaders/develop.shader'),
    ui.FragmentProgram.fromAsset('assets/shaders/develop_mask.shader'),
    ui.FragmentProgram.fromAsset('assets/shaders/sharpen.shader'),
    ui.FragmentProgram.fromAsset('assets/shaders/denoise.shader'),
    ui.FragmentProgram.fromAsset('assets/shaders/perspective.shader'),
    ui.FragmentProgram.fromAsset('assets/shaders/lens_correct.shader'),
    ui.FragmentProgram.fromAsset('assets/shaders/spot_remove.shader'),
  ]);
  for (final p in results) {
    p.fragmentShader(); // 预热编译
  }
  return _ShaderBundle(
    develop: results[0],
    mask: results[1],
    sharpen: results[2],
    denoise: results[3],
    perspective: results[4],
    lensCorrect: results[5],
    spotRemove: results[6],
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

final perspectiveShaderProgramProvider = FutureProvider<ui.FragmentProgram>((
  ref,
) async {
  return (await ref.watch(_allShadersProvider.future)).perspective;
});

final lensCorrectShaderProgramProvider = FutureProvider<ui.FragmentProgram>((
  ref,
) async {
  return (await ref.watch(_allShadersProvider.future)).lensCorrect;
});

final spotRemoveShaderProgramProvider = FutureProvider<ui.FragmentProgram>((
  ref,
) async {
  return (await ref.watch(_allShadersProvider.future)).spotRemove;
});

/// Healing brush shader.
///
/// Same independent-loading pattern as [composeShaderProgramProvider].
final healingShaderProgramProvider = FutureProvider<ui.FragmentProgram?>((
  ref,
) async {
  try {
    final p = await ui.FragmentProgram.fromAsset(
      'assets/shaders/healing.shader',
    );
    p.fragmentShader(); // warm-up
    return p;
  } catch (_) {
    return null;
  }
});

/// 管道渲染完成计数器每次 full-pipeline 渲染产出新帧 +1
/// spot removal overlay 用它感知"已提交的笔画已管线合成完毕"，然后清除本地预览
final renderedPreviewGenerationProvider = StateProvider<int>((ref) => 0);

/// 最后一次渲染完成时使用的 spots 列表哈希
/// overlay 用此信号判断"包含本次描边的渲染是否已完成"——
/// 只有 hash 匹配时才清除 committed preview，避免被无关渲染误触发
final renderedSpotsHashProvider = StateProvider<int>((ref) => 0);

/// 最后一次渲染完成时使用的 healing marks 列表哈希
/// healing overlay 用此信号判断"包含本次描边的渲染是否已完成"
final renderedHealingHashProvider = StateProvider<int>((ref) => 0);

/// Develop pass 输出快照（spot removal 激活时非空）
/// spot removal overlay 用它做笔画预览，替代原始未处理源图
///
/// 通过 [TextureNotifier] mixin 集中管理旧纹理的 dispose：
/// [update] 自动延迟一帧释放旧图，避免 GPU 并发冲突
/// 调用方无需手动管理生命周期
class DevelopOutputNotifier extends Notifier<ui.Image?> with TextureNotifier {
  @override
  ui.Image? build() => null;

  void update(ui.Image? newImage) => updateTexture(newImage);
}

final developOutputProvider =
    NotifierProvider<DevelopOutputNotifier, ui.Image?>(
      DevelopOutputNotifier.new,
    );

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
///
/// 通过 [TextureNotifier] mixin 管理纹理生命周期
/// [update] 是 async 操作（[bakeCurveTexture]），完成后需检查 [_disposed] 守卫，
/// 防止 Provider 已销毁后赋值
class CurveTextureNotifier extends Notifier<ui.Image?> with TextureNotifier {
  bool _disposed = false;

  @override
  ui.Image? build() {
    ref.onDispose(() {
      _disposed = true;
      state?.dispose();
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
    updateTexture(img);
  }
}

final curveTextureProvider = NotifierProvider<CurveTextureNotifier, ui.Image?>(
  CurveTextureNotifier.new,
);

final effectiveCurveTextureProvider = Provider<ui.Image?>((ref) {
  if (ref.watch(compareBypassProvider) ||
      ref.watch(compareViewModeProvider) == CompareViewMode.hold) {
    return null;
  }
  return ref.watch(curveTextureProvider);
});
