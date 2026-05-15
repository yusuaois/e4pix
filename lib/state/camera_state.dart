import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/camera/camera_controller.dart';
import '../services/camera/gphoto2_camera_controller.dart';
import '../services/camera/libgphoto2_android_controller.dart';
import 'tether_state.dart';

@immutable
class CameraState {
  final CameraController? controller;
  final String? modelName;
  final bool shutterFlash;
  final String? lastError;

  const CameraState({
    this.controller,
    this.modelName,
    this.shutterFlash = false,
    this.lastError,
  });

  bool get isActive => controller != null;

  CameraState copyWith({
    CameraController? controller,
    String? modelName,
    bool? shutterFlash,
    String? lastError,
    bool clearController = false,
    bool clearError = false,
  }) =>
      CameraState(
        controller: clearController ? null : (controller ?? this.controller),
        modelName: clearController ? null : (modelName ?? this.modelName),
        shutterFlash: shutterFlash ?? this.shutterFlash,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

class CameraNotifier extends Notifier<CameraState> {
  StreamSubscription<CameraEvent>? _sub;
  Timer? _shutterTimer;

  @override
  CameraState build() {
    ref.onDispose(() async {
      _shutterTimer?.cancel();
      await _sub?.cancel();
      await state.controller?.stopTether();
    });
    return const CameraState();
  }

  static CameraController createController() {
    if (Platform.isAndroid) {
      return LibGphoto2AndroidController();
    }
    return Gphoto2CameraController();
  }

  Future<void> start({
    required CameraController controller,
    required DetectedCamera camera,
    required String saveFolder,
  }) async {
    if (state.isActive) return;

    await ref.read(tetherSessionNotifierProvider.notifier).start(saveFolder);

    state = state.copyWith(
      controller: controller,
      modelName: camera.model,
      clearError: true,
    );

    final stream = controller.startTether(camera: camera, saveFolder: saveFolder);
    _sub = stream.listen(_onEvent);
  }

  void _onEvent(CameraEvent ev) {
    if (!ref.mounted) return;

    if (ev is CameraConnected) {
      state = state.copyWith(modelName: ev.model);
    } else if (ev is CameraTakingShot) {
      state = state.copyWith(shutterFlash: true);
      _shutterTimer?.cancel();
      _shutterTimer = Timer(const Duration(milliseconds: 200), () {
        if (ref.mounted) state = state.copyWith(shutterFlash: false);
      });
    } else if (ev is CameraError) {
      state = state.copyWith(lastError: ev.message);
    } else if (ev is CameraDisconnected) {
      stop();
    }
  }

  Future<void> stop() async {
    _shutterTimer?.cancel();
    _shutterTimer = null;
    await _sub?.cancel();
    _sub = null;
    final ctrl = state.controller;
    state = state.copyWith(clearController: true);
    await ctrl?.stopTether();
    await ref.read(tetherSessionNotifierProvider.notifier).stop();
  }

  Future<void> triggerCapture() async {
    final ctrl = state.controller;
    if (ctrl is LibGphoto2AndroidController) {
      await ctrl.triggerCapture();
    }
  }
}

final cameraNotifierProvider =
    NotifierProvider<CameraNotifier, CameraState>(CameraNotifier.new);