import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/raw_bridge.dart';
import '../render/raw_to_ui_image.dart';

// 当前正在编辑的 RAW 文件路径
class ActiveFilePathNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? path) => state = path;
}

final activeFilePathProvider =
    NotifierProvider<ActiveFilePathNotifier, String?>(ActiveFilePathNotifier.new);

// 解码结果
@immutable
class DecodedImageState {
  final String path;
  final RawDecodedImage decoded;
  final ui.Image uiImage;
  final Duration decodeTime;
  final Duration convertTime;

  const DecodedImageState({
    required this.path,
    required this.decoded,
    required this.uiImage,
    required this.decodeTime,
    required this.convertTime,
  });
}

class ImageNotifier extends AsyncNotifier<DecodedImageState?> {
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

  void _scheduleDispose(ui.Image old) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_providerDisposed) return;
        try {
          old.dispose();
        } catch (e) {
          debugPrint('Stale ui.Image dispose: $e');
        }
      });
    });
  }

  @override
  Future<DecodedImageState?> build() async {
    _registerOnDisposeOnce();

    final path = ref.watch(activeFilePathProvider);
    if (path == null) {
      final old = _held;
      _held = null;
      if (old != null) _scheduleDispose(old);
      return null;
    }

    final sw1 = Stopwatch()..start();
    final decoded = await RawBridge.decodePreview(path);
    sw1.stop();

    final sw2 = Stopwatch()..start();
    final uiImage = await rawToUiImage(decoded);
    sw2.stop();

    final oldImage = _held;
    _held = uiImage;
    if (oldImage != null && oldImage != uiImage) {
      _scheduleDispose(oldImage);
    }

    return DecodedImageState(
      path: path,
      decoded: decoded,
      uiImage: uiImage,
      decodeTime: sw1.elapsed,
      convertTime: sw2.elapsed,
    );
  }
}

final imageNotifierProvider =
    AsyncNotifierProvider<ImageNotifier, DecodedImageState?>(ImageNotifier.new);