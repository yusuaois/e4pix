import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cache/raw_cache_cleaner.dart';
import '../native/raw_bridge.dart';
import '../render/raw_to_ui_image.dart';

class ActiveFilePathNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  
  void set(String? newPath) {
    final old = state;
    state = newPath;
    // 删掉缓存副本
    if (old != null && old != newPath) {
      RawCacheCleaner.deleteIfCached(old);
    }
  }
}

final activeFilePathProvider =
    NotifierProvider<ActiveFilePathNotifier, String?>(
      ActiveFilePathNotifier.new,
    );

// 解码结果
@immutable
class DecodedImageState {
  final String path;
  final RawDecodedImage decoded;
  final ui.Image uiImage;
  final Duration decodeTime;
  final Duration convertTime;

  final bool isPreliminary;

  const DecodedImageState({
    required this.path,
    required this.decoded,
    required this.uiImage,
    required this.decodeTime,
    required this.convertTime,
    this.isPreliminary = false,
  });
}

class ImageNotifier extends AsyncNotifier<DecodedImageState?> {
  ui.Image? _held;

  /// 每次 build 增 1, 异步链判断最新请求
  int _generation = 0;

  void _scheduleDispose(ui.Image old) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        try {
          old.dispose();
        } catch (e) {
          debugPrint('Stale ui.Image dispose: $e');
        }
      });
    });
  }

  void _swapHeld(ui.Image newImage) {
    final old = _held;
    _held = newImage;
    if (old != null && old != newImage) _scheduleDispose(old);
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

    // half_size + PPG
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
      decoded: fastDecoded,
      uiImage: fastImage,
      decodeTime: sw1.elapsed,
      convertTime: sw2.elapsed,
      isPreliminary: true,
    );

    // print('[Build] phase1 done, scheduling phase2 gen=$gen');
    _runPhase2(path, gen);
    return fastState;
  }

  Future<void> _runPhase2(String path, int gen) async {
    // ignore: avoid_print
    print('[Phase2] enter gen=$gen _gen=$_generation');

    await Future.delayed(const Duration(milliseconds: 16));
    if (gen != _generation) {
      // print('[Phase2] bail: stale gen $gen != $_generation');
      return;
    }

    // print('[Phase2] calling RawBridge.decodePreview');

    try {
      final sw1 = Stopwatch()..start();
      final fullDecoded = await RawBridge.decodePreview(path);
      sw1.stop();
      if (gen != _generation) return;
      // print('[Phase2] decode ${sw1.elapsedMilliseconds}ms');

      final sw2 = Stopwatch()..start();
      final fullImage = await rawToUiImage(fullDecoded);
      sw2.stop();
      if (gen != _generation) {
        _scheduleDispose(fullImage);
        return;
      }
      // print('[Phase2] convert ${sw2.elapsedMilliseconds}ms');

      _swapHeld(fullImage);
      state = AsyncData(DecodedImageState(
        path: path,
        decoded: fullDecoded,
        uiImage: fullImage,
        decodeTime: sw1.elapsed,
        convertTime: sw2.elapsed,
        isPreliminary: false,
      ));
      // print('[Phase2] HD ready');
    } catch (e) { //st
      // print('[Phase2] ERROR: $e\n$st');
    }
  }
}

final imageNotifierProvider =
    AsyncNotifierProvider<ImageNotifier, DecodedImageState?>(ImageNotifier.new);
