import 'dart:async';

class DetectedCamera {
  final String model;     // "Panasonic DC-S5"
  final String port;      // "usb:001,003"
  const DetectedCamera({required this.model, required this.port});

  @override
  String toString() => '$model ($port)';
}

sealed class CameraEvent {
  const CameraEvent();
}
class CameraConnected     extends CameraEvent { final String model; const CameraConnected(this.model); }
class CameraTakingShot    extends CameraEvent { const CameraTakingShot(); }
class CameraShotSaved     extends CameraEvent { final String filename; const CameraShotSaved(this.filename); }
class CameraError         extends CameraEvent { final String message;  const CameraError(this.message); }
class CameraDisconnected  extends CameraEvent { const CameraDisconnected(); }

class CameraException implements Exception {
  final String message;
  CameraException(this.message);
  @override
  String toString() => 'CameraException: $message';
}

abstract class CameraController {
  /// 探测当前可用相机
  Future<List<DetectedCamera>> detectCameras();

  /// 启动 tether 捕获。文件落到 [saveFolder]。
  /// 返回的 stream 反映相机事件，用于状态显示。
  Stream<CameraEvent> startTether({
    required DetectedCamera camera,
    required String saveFolder,
  });

  /// 停止当前 tether 会话
  Future<void> stopTether();

  bool get isActive;
}