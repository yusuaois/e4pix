import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'camera_controller.dart';

/// Android 端 USB 联机：libgphoto2 (JNI) + Android USB Host API
class LibGphoto2AndroidController implements CameraController {
  static const _channel = MethodChannel('e4pix/camera');
  static const _eventChannel = EventChannel('e4pix/camera/events');

  StreamController<CameraEvent>? _events;
  StreamSubscription<dynamic>? _eventSub;
  bool _active = false;

  @override
  bool get isActive => _active;

  // ============================================================================
  // 探测相机
  // ============================================================================
  @override
  Future<List<DetectedCamera>> detectCameras() async {
    if (!Platform.isAndroid) {
      throw CameraException('LibGphoto2AndroidController 仅支持 Android');
    }
    try {
      final list = await _channel
          .invokeListMethod<dynamic>('detectCameras')
          .timeout(const Duration(seconds: 5));
      if (list == null) return const [];
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return DetectedCamera(
          model: (m['model'] as String?) ?? 'USB Camera',
          port: (m['port'] as String?) ?? 'usb:?',
        );
      }).toList(growable: false);
    } on TimeoutException {
      throw CameraException('USB 探测超时');
    } on PlatformException catch (e) {
      throw CameraException('探测失败: ${e.message ?? e.code}');
    }
  }

  // ============================================================================
  // 启动 tether
  // ============================================================================
  @override
  Stream<CameraEvent> startTether({
    required DetectedCamera camera,
    required String saveFolder,
  }) {
    if (_active) {
      throw CameraException('已有 tether 会话在运行');
    }
    _active = true;
    _events = StreamController<CameraEvent>.broadcast();

    // 1. 先订阅 EventChannel —— 必须早于 startTether RPC，否则 connected 事件会丢
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object err, StackTrace _) {
        _events?.add(CameraError('Event channel error: $err'));
      },
    );

    // 2. 异步触发 startTether（不 await，让 stream 先返回给调用方）
    _channel.invokeMethod<void>('startTether', {
      'port': camera.port,
      'saveFolder': saveFolder,
    }).catchError((Object e) {
      final msg = e is PlatformException
          ? '${e.code}: ${e.message ?? ""}'
          : e.toString();
      _events?.add(CameraError('启动失败: $msg'));
      _events?.add(const CameraDisconnected());
      _cleanup();
    });

    return _events!.stream;
  }

  void _onNativeEvent(dynamic data) {
    if (data is! Map) return;
    final m = Map<String, dynamic>.from(data);
    final type = m['type'] as String?;
    if (type == null) return;

    final ev = _toCameraEvent(type, m);
    if (ev == null) return;

    _events?.add(ev);

    // disconnected 事件投递后清理（异步，避免在 listener 内 close stream）
    if (ev is CameraDisconnected) {
      scheduleMicrotask(_cleanup);
    }
  }

  CameraEvent? _toCameraEvent(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'connected':
        return CameraConnected((data['model'] as String?) ?? 'Camera');
      case 'takingShot':
        return const CameraTakingShot();
      case 'shotSaved':
        return CameraShotSaved((data['filename'] as String?) ?? '');
      case 'error':
        return CameraError((data['message'] as String?) ?? 'Unknown error');
      case 'disconnected':
        return const CameraDisconnected();
    }
    return null;
  }

  // ============================================================================
  // 停止
  // ============================================================================
  @override
  Future<void> stopTether() async {
    if (!_active) return;
    try {
      await _channel.invokeMethod('stopTether');
      // Kotlin 端会发 'disconnected' → _onNativeEvent → scheduleMicrotask(_cleanup)
    } on PlatformException catch (e) {
      _events?.add(CameraError('停止失败: ${e.message ?? e.code}'));
      _events?.add(const CameraDisconnected());
      _cleanup();
    }
  }

  void _cleanup() {
    _eventSub?.cancel();
    _eventSub = null;
    final ev = _events;
    if (ev != null && !ev.isClosed) {
      ev.close();
    }
    _events = null;
    _active = false;
  }

  // ============================================================================
  // 接口外的扩展（仅 Android 有意义）
  // ============================================================================

  /// 远程触发快门（不通过相机按钮）
  Future<void> triggerCapture() async {
    await _channel.invokeMethod('triggerCapture');
  }

  /// 诊断：libgphoto2 版本字符串
  Future<String> getLibraryVersion() async {
    return (await _channel.invokeMethod<String>('getLibraryVersion')) ?? '';
  }
}