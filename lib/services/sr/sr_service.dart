import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';

import '../debug/debug_log_service.dart';

/// 超分辨率推理服务
///
/// 使用 Real-ESRGAN ONNX 模型进行 2x 超分辨率
/// 通过 onnxruntime_v2 的 appendDefaultProviders() 自动选择最佳硬件
class SrService {
  static final instance = SrService._();
  SrService._();

  static const _modelAsset = 'assets/models/RealESRGAN_x2.onnx';
  static const int _tileSize = 128;
  static const int _overlap = 8;

  OrtSession? _session;
  String? _inputName;
  bool _initTried = false;
  Uint8List? _modelBytes;
  Isolate? _activeIsolate;
  bool _busy = false; // 防止重复推理

  bool get available => _session != null;

  /// 加载模型，appendDefaultProviders() 自动选择最佳硬件
  Future<bool> ensureLoaded() async {
    if (_initTried) return available;
    _initTried = true;

    try {
      OrtEnv.instance.init();

      // ① 检查可用的 provider 列表
      final providers = OrtEnv.instance.availableProviders();
      debugPrint('[SrService] Available providers: $providers');

      final rawAsset = await rootBundle.load(_modelAsset);
      _modelBytes = rawAsset.buffer.asUint8List();
      debugPrint(
        '[SrService] Model: ${(_modelBytes!.length / 1024 / 1024).toStringAsFixed(1)}MB',
      );

      final options = OrtSessionOptions();

      // ② 自动选择最佳 provider
      options.appendDefaultProviders();
      debugPrint('[SrService] Providers configured via appendDefaultProviders');

      options.setIntraOpNumThreads(4);

      _session = OrtSession.fromBuffer(_modelBytes!, options);
      _inputName = _session!.inputNames.first;

      debugPrint('[SrService] Session ready. inputs=${_session!.inputNames}');

      // 注意：此处跳过 test inference，因为部分 Android 设备上
      // onnxruntime CPU 内核使用了不支持的 ARM 指令集（SIGILL）
      // 实际推理在 upscaleRegion/upscaleFull 中执行，出错会被 try-catch 捕获

      options.release();
      return true;
    } catch (e) {
      debugPrint('[SrService] Load failed: $e');
      _session = null;
      return false;
    }
  }

  /// 预览推理（小区域）
  Future<ui.Image?> upscaleRegion({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
  }) async {
    if (!await ensureLoaded()) return null;
    try {
      final input = _rgbaToNchw(rgbaBytes, width, height);
      final tensor = OrtValueTensor.createTensorWithDataList(input, [
        1,
        3,
        height,
        width,
      ]);
      final outputs = _session!.run(OrtRunOptions(), {_inputName!: tensor});
      if (outputs.isEmpty) return null;
      final outTensor = outputs.first as OrtValueTensor?;
      if (outTensor == null) return null;
      return _rgbaToUiImage(
        _nchwToRgba(outTensor.value, width * 2, height * 2),
        width * 2,
        height * 2,
      );
    } catch (e) {
      debugPrint('[SrService] upscaleRegion failed: $e');
      return null;
    }
  }

  /// 全图超分
  ///
  /// 返回 null 表示失败或被取消
  /// 调用方应通过 [cancelExport] 取消进行中的任务
  Future<ui.Image?> upscaleFull({
    required ui.Image source,
    void Function(double progress)? onProgress,
  }) async {
    if (_busy) {
      debugPrint('[SrService] upscaleFull already running, skipping');
      return null;
    }
    _busy = true;
    if (!await ensureLoaded()) {
      _busy = false;
      return null;
    }

    final sw = Stopwatch()..start();

    try {
      final srcW = source.width;
      final srcH = source.height;
      final byteData = await source.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;
      final srcBytes = byteData.buffer.asUint8List();

      debugPrint(
        '[SrService] upscaleFull: ${srcW}x$srcH → ${srcW * 2}x${srcH * 2}',
      );

      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(
        _isolateUpscale,
        _IsolateParams(
          sendPort: receivePort.sendPort,
          modelBytes: _modelBytes!,
          srcBytes: srcBytes,
          srcW: srcW,
          srcH: srcH,
          tileSize: _tileSize,
          overlap: _overlap,
          logFilePath: DebugLogService.instance.logFilePath,
        ),
      );
      _activeIsolate = isolate;

      // 等待 Isolate 返回结果
      final result = await receivePort.first as _SrResult?;

      _activeIsolate = null;

      if (result == null) {
        debugPrint('[SrService] Isolate returned null');
        return null;
      }

      sw.stop();
      final secs = (sw.elapsedMilliseconds / 1000).toStringAsFixed(1);
      debugPrint('[SrService] Done in ${secs}s');
      return _rgbaToUiImage(result.bytes, result.width, result.height);
    } catch (e) {
      debugPrint('[SrService] upscaleFull failed: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  /// 取消正在进行的导出超分任务
  void cancelExport() {
    final isolate = _activeIsolate;
    if (isolate != null) {
      debugPrint('[SrService] Killing SR isolate');
      isolate.kill(priority: Isolate.immediate);
      _activeIsolate = null;
    }
  }

  // ── 辅助方法 ──

  static Float32List _rgbaToNchw(Uint8List rgba, int w, int h) {
    final nchw = Float32List(3 * h * w);
    final plane = h * w;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final s = (y * w + x) * 4;
        final d = y * w + x;
        nchw[d] = rgba[s] / 255.0;
        nchw[plane + d] = rgba[s + 1] / 255.0;
        nchw[plane * 2 + d] = rgba[s + 2] / 255.0;
      }
    }
    return nchw;
  }

  static Uint8List _nchwToRgba(dynamic data, int w, int h) {
    final rgba = Uint8List(w * h * 4);
    final plane = h * w;
    final flat = _flatten(data);
    for (int i = 0; i < plane; i++) {
      final r = flat[i].clamp(0.0, 1.0) * 255;
      final g = flat[plane + i].clamp(0.0, 1.0) * 255;
      final b = flat[plane * 2 + i].clamp(0.0, 1.0) * 255;
      final o = i * 4;
      rgba[o] = r.round();
      rgba[o + 1] = g.round();
      rgba[o + 2] = b.round();
      rgba[o + 3] = 255;
    }
    return rgba;
  }

  static Float64List _flatten(dynamic data) {
    if (data is Float32List) {
      return Float64List.fromList(data.map((e) => e.toDouble()).toList());
    }
    if (data is Float64List) return data;
    if (data is List<double>) return Float64List.fromList(data);
    final out = <double>[];
    _flattenRecursive(data, out);
    return Float64List.fromList(out);
  }

  static void _flattenRecursive(dynamic data, List<double> out) {
    if (data is List) {
      for (final item in data) {
        _flattenRecursive(item, out);
      }
    } else {
      out.add((data as num).toDouble());
    }
  }

  static Future<ui.Image> _rgbaToUiImage(Uint8List rgba, int w, int h) async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }
}

// ── Isolate 通信 ──

class _IsolateParams {
  final SendPort sendPort;
  final Uint8List modelBytes;
  final Uint8List srcBytes;
  final int srcW;
  final int srcH;
  final int tileSize;
  final int overlap;
  final String? logFilePath;
  const _IsolateParams({
    required this.sendPort,
    required this.modelBytes,
    required this.srcBytes,
    required this.srcW,
    required this.srcH,
    required this.tileSize,
    required this.overlap,
    this.logFilePath,
  });
}

/// Isolate 入口：接收参数，处理完后通过 SendPort 发回结果
void _isolateUpscale(_IsolateParams p) {
  DebugLogService.setupIsolateLogging(logFilePath: p.logFilePath);
  try {
    OrtEnv.instance.init();
    final options = OrtSessionOptions();
    options.appendDefaultProviders();
    options.setIntraOpNumThreads(4);
    final session = OrtSession.fromBuffer(p.modelBytes, options);
    final inputName = session.inputNames.first;
    options.release();

    final srcW = p.srcW;
    final srcH = p.srcH;
    final tileSize = p.tileSize;
    final overlap = p.overlap;
    final srcBytes = p.srcBytes;

    final effectiveTile = tileSize - overlap * 2;
    final tilesX = (srcW / effectiveTile).ceil();
    final tilesY = (srcH / effectiveTile).ceil();
    final totalTiles = tilesX * tilesY;
    final outW = srcW * 2;
    final outH = srcH * 2;
    // 用 Float32 累加，避免 Uint8 中间值截断导致接缝暗带
    final outAccum = Float32List(outW * outH * 4);
    final weightMap = Float32List(outW * outH);

    debugPrint('[SrService:isolate] $totalTiles tiles');

    int processed = 0;
    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final x0 = (tx * effectiveTile - overlap).clamp(0, srcW);
        final y0 = (ty * effectiveTile - overlap).clamp(0, srcH);
        final x1 = (x0 + tileSize).clamp(0, srcW);
        final y1 = (y0 + tileSize).clamp(0, srcH);
        final tw = x1 - x0;
        final th = y1 - y0;

        // 模型要求输入尺寸为偶数，边缘 tile 需要 padding
        final padW = tw.isOdd ? tw + 1 : tw;
        final padH = th.isOdd ? th + 1 : th;

        // 提取 tile（padding 区域填零）
        final tileBytes = Uint8List(padW * padH * 4);
        for (int y = 0; y < th; y++) {
          final srcOff = ((y0 + y) * srcW + x0) * 4;
          final dstOff = y * padW * 4;
          tileBytes.setRange(dstOff, dstOff + tw * 4, srcBytes, srcOff);
        }

        // RGBA → NCHW
        final input = Float32List(3 * padH * padW);
        final plane = padH * padW;
        for (int y = 0; y < padH; y++) {
          for (int x = 0; x < padW; x++) {
            final s = (y * padW + x) * 4;
            final d = y * padW + x;
            input[d] = tileBytes[s] / 255.0;
            input[plane + d] = tileBytes[s + 1] / 255.0;
            input[plane * 2 + d] = tileBytes[s + 2] / 255.0;
          }
        }

        // 推理（使用 padding 后的尺寸）
        final tensor = OrtValueTensor.createTensorWithDataList(input, [
          1,
          3,
          padH,
          padW,
        ]);
        final outputs = session.run(OrtRunOptions(), {inputName: tensor});

        if (outputs.isNotEmpty) {
          final outTensor = outputs.first as OrtValueTensor?;
          if (outTensor != null) {
            final flat = SrService._flatten(outTensor.value);
            // 输出尺寸基于实际 tile 大小（不含 padding）
            final oTw = tw * 2;
            final oTh = th * 2;
            // 模型输出基于 padding 后的尺寸
            final oPadW = padW * 2;
            final oPadH = padH * 2;
            final oPlanePad = oPadH * oPadW;
            final overlapPx = overlap * 2;
            for (int y = 0; y < oTh; y++) {
              for (int x = 0; x < oTw; x++) {
                double w = 1.0;
                if (overlapPx > 0) {
                  final dx = x < oTw - x ? x : oTw - 1 - x;
                  final dy = y < oTh - y ? y : oTh - 1 - y;
                  final edge = dx < dy ? dx : dy;
                  if (edge < overlapPx) w = (edge + 1) / (overlapPx + 1);
                }
                final outIdx = ((y0 * 2 + y) * outW + (x0 * 2 + x)) * 4;
                // 从 padded 输出中读取（跳过 padding 区域）
                final srcIdx = y * oPadW + x;
                for (int c = 0; c < 3; c++) {
                  final v = flat[oPlanePad * c + srcIdx].clamp(0.0, 1.0) * 255;
                  outAccum[outIdx + c] += v * w;
                }
                outAccum[outIdx + 3] = 255;
                weightMap[(y0 * 2 + y) * outW + (x0 * 2 + x)] += w;
              }
            }
          }
        }

        processed++;
        if (processed % 100 == 0 || processed == totalTiles) {
          debugPrint(
            '[SrService:isolate] $processed/$totalTiles '
            '(${(processed / totalTiles * 100).round()}%)',
          );
        }
      }
    }

    // 归一化并转为 Uint8List
    final outBytes = Uint8List(outW * outH * 4);
    for (int i = 0; i < outW * outH; i++) {
      final idx = i * 4;
      if (weightMap[i] > 0) {
        final invW = 1.0 / weightMap[i];
        for (int c = 0; c < 3; c++) {
          outBytes[idx + c] = (outAccum[idx + c] * invW).round().clamp(0, 255);
        }
      }
      outBytes[idx + 3] = 255;
    }

    debugPrint('[SrService:isolate] Complete ${outW}x$outH');
    p.sendPort.send(_SrResult(bytes: outBytes, width: outW, height: outH));
  } catch (e) {
    debugPrint('[SrService:isolate] Failed: $e');
    p.sendPort.send(null);
  }
}

class _SrResult {
  final Uint8List bytes;
  final int width;
  final int height;
  const _SrResult({
    required this.bytes,
    required this.width,
    required this.height,
  });
}
