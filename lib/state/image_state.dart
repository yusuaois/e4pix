import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/raw_formats.dart';
import '../core/models/adjustment_params.dart';
import '../native/raw_bridge.dart';
import '../render/decoded_image_cache.dart';
import '../render/lut_texture_cache.dart';
import '../render/raw_to_ui_image.dart';
import '../services/image_loader.dart';
import 'providers.dart';
// tether_state.dart/params_state.dart

class ActiveFilePathNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// 切图：先预加载目标图的 LUT 进缓存（避免 LutNotifier 派生时闪烁），再切。
  /// set 为 async；调用方可不 await（fire-and-forget）。预加载完成后才更新 state，
  /// 确保 LutNotifier 重建时缓存已命中、同步出图、无闪烁。
  Future<void> set(String? newPath) async {
    if (newPath == null) {
      state = null;
      return;
    }
    await _preloadLut(newPath);
    state = newPath;
  }

  Future<void> _preloadLut(String path) async {
    final shots = ref.read(shotsNotifierProvider);
    AdjustmentParams params = ref.read(currentParamsNotifierProvider); // 默认当前
    for (final s in shots) {
      if (s.path == path) {
        params = s.params;
        break;
      }
    }
    final cache = LutTextureCache.instance;
    try {
      if (params.lutNameA.isNotEmpty) await cache.load(params.lutNameA);
      if (params.lutNameB.isNotEmpty) await cache.load(params.lutNameB);
    } catch (_) {}
  }
}

final activeFilePathProvider =
    NotifierProvider<ActiveFilePathNotifier, String?>(
      ActiveFilePathNotifier.new,
    );

@immutable
class DecodedImageState {
  final String path;
  final ui.Image uiImage;
  final int width;
  final int height;
  final int bitsPerChannel;
  final RawMetadata? metadata;
  final Duration decodeTime;
  final Duration convertTime;
  final bool isPreliminary;
  
  /// RAW 解码后的原始像素数据；缓存命中或标准图为 null
  final RawDecodedImage? decoded;

  const DecodedImageState({
    required this.path,
    required this.uiImage,
    required this.width,
    required this.height,
    required this.bitsPerChannel,
    this.metadata,
    required this.decodeTime,
    required this.convertTime,
    this.isPreliminary = false,
    this.decoded,
  });
}

class ImageNotifier extends AsyncNotifier<DecodedImageState?> {
  ui.Image? _held;
  int _generation = 0;

  final _cache = DecodedImageCache.instance;

  /// dispose 旧持有图——若已被缓存接管则跳过 ~64ms延迟
  void _scheduleDispose(ui.Image old) {
    if (_cache.ownsImage(old)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 50), () {
        try {
          old.dispose();
        } catch (_) {}
      });
    });
  }

  void _swapHeld(ui.Image newImage) {
    final old = _held;
    _held = newImage;
    if (old != null && !identical(old, newImage)) _scheduleDispose(old);
  }

  @override
  Future<DecodedImageState?> build() async {
    final path = ref.watch(activeFilePathProvider);
    if (path == null) {
      final old = _held;
      _held = null;
      if (old != null) _scheduleDispose(old);
      return null;
    }

    final gen = ++_generation;

    // 缓存命中
    final hit = _cache.get(path);
    if (hit != null) {
      _swapHeld(hit.image);
      return DecodedImageState(
        path: path,
        uiImage: hit.image,
        width: hit.width,
        height: hit.height,
        bitsPerChannel: hit.bitsPerChannel,
        metadata: hit.metadata,
        decodeTime: Duration.zero,
        convertTime: Duration.zero,
        isPreliminary: false,
      );
    }

    if (RawFormats.isStandard(path)) {
      return _buildStandard(path, gen);
    }

    // RAW phase1: 快速预览
    final sw1 = Stopwatch()..start();
    final fastDecoded = await RawBridge.decodePreviewFast(path);
    sw1.stop();
    if (gen != _generation) return null;

    final sw2 = Stopwatch()..start();
    final fastImage = await rawToUiImage(fastDecoded);
    sw2.stop();
    if (gen != _generation) {
      _scheduleDispose(fastImage);
      return null;
    }

    _swapHeld(fastImage);
    final fastState = DecodedImageState(
      path: path,
      uiImage: fastImage,
      width: fastDecoded.width,
      height: fastDecoded.height,
      bitsPerChannel: fastDecoded.bitsPerChannel,
      metadata: fastDecoded.metadata,
      decodeTime: sw1.elapsed,
      convertTime: sw2.elapsed,
      isPreliminary: true,
      decoded: fastDecoded,
    );

    _runPhase2(path, gen);
    return fastState;
  }

  Future<void> _runPhase2(String path, int gen) async {
    await Future.delayed(const Duration(milliseconds: 16));
    if (gen != _generation) return;

    try {
      final sw1 = Stopwatch()..start();
      final fullDecoded = await RawBridge.decodePreview(path);
      sw1.stop();
      if (gen != _generation) return;

      final sw2 = Stopwatch()..start();
      final fullImage = await rawToUiImage(fullDecoded);
      sw2.stop();
      if (gen != _generation) {
        _scheduleDispose(fullImage);
        return;
      }

      _swapHeld(fullImage);
      // HD 图存入缓存
      _cache.put(
        path,
        CachedDecode(
          image: fullImage,
          metadata: fullDecoded.metadata,
          width: fullDecoded.width,
          height: fullDecoded.height,
          bitsPerChannel: fullDecoded.bitsPerChannel,
        ),
      );

      state = AsyncData(
        DecodedImageState(
          path: path,
          uiImage: fullImage,
          width: fullDecoded.width,
          height: fullDecoded.height,
          bitsPerChannel: fullDecoded.bitsPerChannel,
          metadata: fullDecoded.metadata,
          decodeTime: sw1.elapsed,
          convertTime: sw2.elapsed,
          isPreliminary: false,
          decoded: fullDecoded,
        ),
      );
    } catch (_) {}
  }

  Future<DecodedImageState?> _buildStandard(String path, int gen) async {
    final sw = Stopwatch()..start();
    final (image, meta) = await ImageLoader.decodeFull(path);
    sw.stop();
    if (gen != _generation) {
      _scheduleDispose(image);
      return null;
    }
    _swapHeld(image);
    _cache.put(
      path,
      CachedDecode(
        image: image,
        metadata: meta,
        width: image.width,
        height: image.height,
        bitsPerChannel: 8,
      ),
    );

    return DecodedImageState(
      path: path,
      uiImage: image,
      width: image.width,
      height: image.height,
      bitsPerChannel: 8,
      metadata: meta,
      decodeTime: sw.elapsed,
      convertTime: Duration.zero,
      isPreliminary: false,
    );
  }
}

final imageNotifierProvider =
    AsyncNotifierProvider<ImageNotifier, DecodedImageState?>(
      retry: (retryCount, error) => null,
      ImageNotifier.new,
    );
