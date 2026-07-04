import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/brush_layer.dart';
import 'clone_stamp_model.dart';
import '../../render/brush_layer_provider.dart';
import 'clone_stamp_cache.dart';
import '../../utils/shader_pass_util.dart';

/// Spot Removal (Clone Stamp) brush layer provider.
///
/// Renders spots onto the develop output and returns a [BrushLayer]
/// whose alpha channel encodes which pixels were modified (1.0 = modified,
/// 0.0 = untouched). The Compose pass uses this alpha mask to blend
/// the layer onto the base image.
class SpotRemovalLayerProvider implements BrushLayerProvider {
  @override
  String get id => 'spot_removal';

  final SpotRemovalCache _cache = SpotRemovalCache();
  final ui.FragmentProgram _program;
  ui.FragmentShader? _cachedShader;

  SpotRemovalLayerProvider({required ui.FragmentProgram program})
    : _program = program;

  ui.FragmentShader get _shader => _cachedShader ??= _program.fragmentShader();

  static const _kMaxSpots = 64;
  static const _kSpotUniformsPerSpot =
      6; // srcX, srcY, tgtX, tgtY, radius, hardness
  // Uniform total: 2(uSize) + 1(count) + 64*6 = 387 floats

  @override
  bool isActive(AdjustmentParams params) => params.spots.isNotEmpty;

  @override
  Future<BrushLayer> render({
    required AdjustmentParams params,
    required ui.Image developOutput,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  }) async {
    final spots = params.spots;
    if (spots.isEmpty) {
      return BrushLayer(id: id, active: false);
    }

    final texture = await _renderSpots(
      base: developOutput,
      spots: spots,
      developKey: developKey,
    );

    return BrushLayer(id: id, texture: texture, active: true);
  }

  /// Render spots onto [base], returning a new texture.
  Future<ui.Image> _renderSpots({
    required ui.Image base,
    required List<SpotMark> spots,
    required int developKey,
  }) async {
    if (spots.isEmpty) return base;

    // 1. Full hash cache
    final cached = _cache.getFromSpotsCache(developKey, spots);
    if (cached != null) return cached;

    // 2. Incremental cache
    final incremental = _cache.getIncremental(developKey, spots);

    ui.Image batchInput;
    int startIdx;
    bool batchInputOwned;

    if (incremental != null) {
      batchInput = incremental.$1;
      startIdx = incremental.$2;
      batchInputOwned = true;
    } else {
      batchInput = base;
      startIdx = 0;
      batchInputOwned = false;
    }

    // 3. Batch render remaining spots
    ui.Image? lastResult;
    for (int i = startIdx; i < spots.length; i += _kMaxSpots) {
      final batch = spots.sublist(i, (i + _kMaxSpots).clamp(0, spots.length));
      try {
        final result = await _runSpotRemovePass(
          input: batchInput,
          spots: batch,
        );
        if (batchInputOwned) batchInput.dispose();
        batchInput = result;
        batchInputOwned = true;
        lastResult = result;
      } catch (e) {
        if (batchInputOwned) batchInput.dispose();
        debugPrint('[SpotRemovalLayer] Batch render failed: $e');
        rethrow;
      }
    }

    // 4. Update caches
    if (lastResult != null) {
      _cache.putSpotsCache(developKey, spots, lastResult);
      _cache.putRolling(developKey, spots.length, lastResult);
    }

    return batchInput;
  }

  Future<ui.Image> _runSpotRemovePass({
    required ui.Image input,
    required List<SpotMark> spots,
  }) async {
    final w = input.width;
    final h = input.height;
    final count = spots.length.clamp(0, _kMaxSpots);
    return runSingleShaderPass(
      shader: _shader,
      outputWidth: w,
      outputHeight: h,
      samplers: [input],
      setUniforms: (s) {
        int i = 0;
        s.setFloat(i++, w.toDouble());
        s.setFloat(i++, h.toDouble());
        s.setFloat(i++, count.toDouble());
        for (int n = 0; n < _kMaxSpots; n++) {
          if (n < count) {
            final spot = spots[n];
            s.setFloat(i++, spot.source.dx);
            s.setFloat(i++, spot.source.dy);
            s.setFloat(i++, spot.target.dx);
            s.setFloat(i++, spot.target.dy);
            s.setFloat(i++, spot.radius);
            s.setFloat(i++, spot.hardness);
          } else {
            for (int j = 0; j < _kSpotUniformsPerSpot; j++) {
              s.setFloat(i++, 0.0);
            }
          }
        }
        assert(i == 2 + 1 + _kMaxSpots * _kSpotUniformsPerSpot);
      },
    );
  }

  @override
  Future<void> warmup(
    ui.Image developOutput,
    int targetWidth,
    int targetHeight,
  ) async {
    // 用 _kMaxSpots 个 dummy mark 填满整个 batch。
    // GPU 驱动对不同循环次数的 shader 生成不同 JIT 变体——
    // 1 个 mark（count=1）的预热不会加速 64 个 mark（count=64）的实际使用
    final dummies = List.generate(
      _kMaxSpots,
      (i) => SpotMark(
        source: const ui.Offset(0.0, 0.0),
        target: ui.Offset(i * 0.0001, i * 0.0001),
        radius: 0.0001,
        hardness: 1.0,
      ),
    );
    try {
      final result = await _runSpotRemovePass(
        input: developOutput,
        spots: dummies,
      );
      result.dispose();
    } catch (e) {
      debugPrint('[Warmup] clone_stamp FAILED: $e');
    }
  }

  @override
  void invalidate() => _cache.invalidate();

  @override
  void dispose() => _cache.dispose();
}
