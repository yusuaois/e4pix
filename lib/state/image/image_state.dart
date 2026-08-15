import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/raw_formats.dart';
import '../../core/models/adjustment_params.dart';
import '../../native/raw_bridge.dart';
import '../../render/cache/decoded_image_cache.dart';
import '../../render/cache/lut_texture_cache.dart';
import '../../render/raw_to_ui_image.dart';
import '../../services/image/image_loader.dart';
import '../providers.dart';

class ActiveFilePathNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// 切图：先预加载目标图的 LUT 进缓存（避免 LutNotifier 派生时闪烁），再切
  /// set 为 async；调用方可不 await（fire-and-forget），预加载完成后才更新 state，
  /// 确保 LutNotifier 重建时缓存已命中、同步出图、无闪烁
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
    } catch (e) {
      debugPrint('[ImageNotifier] LUT preload failed: $e');
    }
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

    // RAW：单次全分辨率解码（消除「先糊后清」的二次预览跳变）
    // decoded 保留全尺寸 raw，供超清渲染零重解码复用
    final sw1 = Stopwatch()..start();
    final decoded = await RawBridge.decodePreview(path);
    sw1.stop();
    if (gen != _generation) return null;

    final sw2 = Stopwatch()..start();
    final image = await rawToUiImage(decoded);
    sw2.stop();
    if (gen != _generation) {
      _scheduleDispose(image);
      return null;
    }

    _swapHeld(image);
    _cache.put(
      path,
      CachedDecode(
        image: image,
        metadata: decoded.metadata,
        width: decoded.width,
        height: decoded.height,
        bitsPerChannel: decoded.bitsPerChannel,
      ),
    );

    return DecodedImageState(
      path: path,
      uiImage: image,
      width: decoded.width,
      height: decoded.height,
      bitsPerChannel: decoded.bitsPerChannel,
      metadata: decoded.metadata,
      decodeTime: sw1.elapsed,
      convertTime: sw2.elapsed,
      isPreliminary: false,
      decoded: decoded,
    );
  }

  /// 释放已解码的全尺寸 raw（供超清源转换完成后回收内存）
  void releaseDecoded() {
    final cur = state.value;
    if (cur == null || cur.decoded == null) return;
    state = AsyncData(
      DecodedImageState(
        path: cur.path,
        uiImage: cur.uiImage,
        width: cur.width,
        height: cur.height,
        bitsPerChannel: cur.bitsPerChannel,
        metadata: cur.metadata,
        decodeTime: cur.decodeTime,
        convertTime: cur.convertTime,
        isPreliminary: cur.isPreliminary,
        decoded: null,
      ),
    );
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
