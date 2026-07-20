import 'dart:async';
import 'dart:io';

import 'package:e4pix/services/notifications/tether_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/camera/camera_controller.dart';
import '../../services/camera/gphoto2_camera_controller.dart';
import '../../services/camera/libgphoto2_android_controller.dart';
import '../../utils/debouncer.dart';
import '../providers.dart';

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
  }) => CameraState(
    controller: clearController ? null : (controller ?? this.controller),
    modelName: clearController ? null : (modelName ?? this.modelName),
    shutterFlash: shutterFlash ?? this.shutterFlash,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );
}

class CameraNotifier extends Notifier<CameraState> {
  StreamSubscription<CameraEvent>? _sub;
  final _shutterDebouncer = Debouncer();

  @override
  CameraState build() {
    ref.onDispose(() async {
      _shutterDebouncer.dispose();
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

    await ref
        .read(tetherSessionNotifierProvider.notifier)
        .start(saveFolder, suppressNotification: true);

    state = state.copyWith(
      controller: controller,
      modelName: camera.model,
      clearError: true,
    );

    // 通知
    TetherNotificationService.instance.showCameraOngoing(
      model: camera.model,
      saveFolder: saveFolder,
    );

    final stream = controller.startTether(
      camera: camera,
      saveFolder: saveFolder,
    );
    _sub = stream.listen(_onEvent);
  }

  void _onEvent(CameraEvent ev) {
    if (!ref.mounted) return;

    if (ev is CameraConnected) {
      state = state.copyWith(modelName: ev.model);
    } else if (ev is CameraTakingShot) {
      state = state.copyWith(shutterFlash: true);
      _shutterDebouncer.run(const Duration(milliseconds: 200), () {
        if (ref.mounted) state = state.copyWith(shutterFlash: false);
      });
    } else if (ev is CameraError) {
      state = state.copyWith(lastError: ev.message);
    } else if (ev is CameraDisconnected) {
      stop();
      ref.read(tetherSessionNotifierProvider.notifier).stop();
    }
  }

  Future<void> stop() async {
    _shutterDebouncer.cancel();
    await _sub?.cancel();
    _sub = null;
    final ctrl = state.controller;
    state = state.copyWith(clearController: true);
    await ctrl?.stopTether();

    // 销毁通知
    TetherNotificationService.instance.dismissCameraOngoing();
  }

  Future<void> triggerCapture() async {
    final ctrl = state.controller;
    if (ctrl is LibGphoto2AndroidController) {
      await ctrl.triggerCapture();
    }
  }
}

final cameraNotifierProvider = NotifierProvider<CameraNotifier, CameraState>(
  CameraNotifier.new,
);
