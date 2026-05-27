import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// EdgeSAM 推理
class SamSession {
  SamSession._();
  static final SamSession instance = SamSession._();

  static const _encoderAsset = 'assets/models/edge_sam_3x_encoder.onnx';
  static const _decoderAsset = 'assets/models/edge_sam_3x_decoder.onnx';
  static const _inputSize = 1024;

  static const _mean = [123.675, 116.28, 103.53];
  static const _std = [58.395, 57.12, 57.375];

  final _ort = OnnxRuntime();
  OrtSession? _encoder;
  OrtSession? _decoder;
  bool _initTried = false;
  bool get available => _encoder != null && _decoder != null;

  // 提示点
  final List<double> _ptX = [];
  final List<double> _ptY = [];
  final List<int> _ptLabel = []; // 1=正, 0=负

  OrtValue? _embOrt;
  Object? _embSig;
  int _gw = 0, _gh = 0, _newW = 0, _newH = 0;

  Future<bool> ensureLoaded() async {
    if (_initTried) return available;
    _initTried = true;
    try {
      _encoder = await _ort.createSessionFromAsset(_encoderAsset);
      _decoder = await _ort.createSessionFromAsset(_decoderAsset);
      debugPrint(
        'SAM encoder inputs=${_encoder!.inputNames} '
        'outputs=${_encoder!.outputNames}',
      );
      debugPrint(
        'SAM decoder inputs=${_decoder!.inputNames} '
        'outputs=${_decoder!.outputNames}',
      );
      return true;
    } catch (e) {
      debugPrint('SAM load failed: $e');
      _encoder = null;
      _decoder = null;
      return false;
    }
  }

  Future<void> ensureEmbedding({
    required Uint8List guide,
    required int gw,
    required int gh,
    required Object signature,
  }) async {
    if (!available) return;
    if (_embSig == signature && _embOrt != null) return;
    _clearPoints();
    await _embOrt?.dispose();
    _embOrt = null;

    final longest = math.max(gw, gh);
    final scale = _inputSize / longest;
    final newW = (gw * scale).round().clamp(1, _inputSize);
    final newH = (gh * scale).round().clamp(1, _inputSize);

    // NCHW 归一化输入：双线性重采样 guide → newW×newH，右下补零
    final input = Float32List(3 * _inputSize * _inputSize);
    const plane = _inputSize * _inputSize;
    for (int ty = 0; ty < newH; ty++) {
      final sy = (ty + 0.5) / scale - 0.5;
      final y0 = sy.floor().clamp(0, gh - 1);
      final y1 = (y0 + 1).clamp(0, gh - 1);
      final wy = (sy - y0).clamp(0.0, 1.0);
      for (int tx = 0; tx < newW; tx++) {
        final sx = (tx + 0.5) / scale - 0.5;
        final x0 = sx.floor().clamp(0, gw - 1);
        final x1 = (x0 + 1).clamp(0, gw - 1);
        final wx = (sx - x0).clamp(0.0, 1.0);
        for (int c = 0; c < 3; c++) {
          double s(int xx, int yy) => guide[(yy * gw + xx) * 4 + c].toDouble();
          final top = s(x0, y0) + (s(x1, y0) - s(x0, y0)) * wx;
          final bot = s(x0, y1) + (s(x1, y1) - s(x0, y1)) * wx;
          final v = top + (bot - top) * wy;
          input[c * plane + ty * _inputSize + tx] = (v - _mean[c]) / _std[c];
        }
      }
    }

    final encInName = _encoder!.inputNames.first;
    final encOutName = _encoder!.outputNames.first;
    final inT = await OrtValue.fromList(input, [1, 3, _inputSize, _inputSize]);
    final outs = await _encoder!.run({encInName: inT});

    // 缓存
    _embOrt = outs[encOutName];
    for (final e in outs.entries) {
      if (e.key != encOutName) {
        await e.value.dispose();
      }
    }
    await inT.dispose();

    _embSig = signature;
    _gw = gw;
    _gh = gh;
    _newW = newW;
    _newH = newH;
    debugPrint('SAM embedding cached, shape=${_embOrt?.shape}');
  }

  /// 追加一个提示点（正/负），用累积的所有点解码，返回 gw×gh 软 mask
  Future<Float32List?> decode(
    ui.Offset seedNorm, {
    bool negative = false,
  }) async {
    if (!available || _embOrt == null) return null;
    final gw = _gw, gh = _gh;
    final scale = _inputSize / math.max(gw, gh);

    _ptX.add((seedNorm.dx * gw) * scale);
    _ptY.add((seedNorm.dy * gh) * scale);
    _ptLabel.add(negative ? 0 : 1);

    final n = _ptX.length;
    final coords = Float32List(n * 2);
    final labels = Float32List(n);
    for (int i = 0; i < n; i++) {
      coords[i * 2] = _ptX[i]; // x
      coords[i * 2 + 1] = _ptY[i]; // y
      labels[i] = _ptLabel[i].toDouble();
    }

    final coordT = await OrtValue.fromList(coords, [1, n, 2]);
    final labelT = await OrtValue.fromList(labels, [1, n]);

    final inNames = _decoder!.inputNames;
    final outs = await _decoder!.run({
      inNames[0]: _embOrt!,
      inNames[1]: coordT,
      inNames[2]: labelT,
    });

    final outNames = _decoder!.outputNames;
    String pick = outNames.firstWhere(
      (n) => n.contains('low_res'),
      orElse: () => '',
    );
    if (pick.isEmpty) {
      pick = outNames.firstWhere(
        (n) => n.contains('mask'),
        orElse: () => outNames.first,
      );
    }
    final maskOrt = outs[pick]!;
    final outShape = maskOrt.shape;
    final outH = outShape[outShape.length - 2];
    final outW = outShape[outShape.length - 1];

    final flatDyn = await maskOrt.asFlattenedList();
    final stride = outH * outW;
    final flat = Float32List(stride);
    for (int i = 0; i < stride; i++) {
      flat[i] = (flatDyn[i] as num).toDouble();
    }

    await coordT.dispose();
    await labelT.dispose();
    for (final v in outs.values) {
      await v.dispose();
    }

    // 双线性上采样到 gw×gh，detect 是否已 upscaled
    final upscaled = (outW == gw && outH == gh);
    final validW = upscaled ? outW.toDouble() : outW * (_newW / _inputSize);
    final validH = upscaled ? outH.toDouble() : outH * (_newH / _inputSize);

    final mask = Float32List(gw * gh);
    for (int j = 0; j < gh; j++) {
      final vv = (j + 0.5) / gh * validH - 0.5;
      final v0 = vv.floor().clamp(0, outH - 1);
      final v1 = (v0 + 1).clamp(0, outH - 1);
      final fy = (vv - v0).clamp(0.0, 1.0);
      final r0 = v0 * outW, r1 = v1 * outW;
      for (int i = 0; i < gw; i++) {
        final uu = (i + 0.5) / gw * validW - 0.5;
        final u0 = uu.floor().clamp(0, outW - 1);
        final u1 = (u0 + 1).clamp(0, outW - 1);
        final fx = (uu - u0).clamp(0.0, 1.0);
        final a = flat[r0 + u0], b = flat[r0 + u1];
        final c = flat[r1 + u0], d = flat[r1 + u1];
        final top = a + (b - a) * fx;
        final bot = c + (d - c) * fx;
        final logit = top + (bot - top) * fy;
        const double margin = 1.0;
        mask[j * gw + i] = ((logit + margin) / (margin * 2.0)).clamp(0.0, 1.0);
      }
    }
    return mask;
  }

  void _clearPoints() {
    _ptX.clear();
    _ptY.clear();
    _ptLabel.clear();
  }

  void resetPoints() => _clearPoints();
}
