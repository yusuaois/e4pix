import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

/// EdgeSAM 推理：encoder 跑一次缓存 embedding，decoder 按点快速跑。
class SamSession {
  SamSession._();
  static final SamSession instance = SamSession._();

  // 资源路径（按需改名）
  static const _encoderAsset = 'assets/models/edge_sam_3x_encoder.onnx';
  static const _decoderAsset = 'assets/models/edge_sam_3x_decoder.onnx';
  static const _inputSize = 1024;

  // SAM 归一化（若模型已内置归一化，把这两行置 0/1）
  static const _mean = [123.675, 116.28, 103.53];
  static const _std = [58.395, 57.12, 57.375];

  OrtSession? _encoder;
  OrtSession? _decoder;
  bool _initTried = false;
  bool get available => _encoder != null && _decoder != null;

  // embedding 缓存
  Float32List? _emb;
  final List<int> _embShape = const [1, 256, 64, 64];
  Object? _embSig;
  int _gw = 0, _gh = 0, _newW = 0, _newH = 0;

  Future<bool> ensureLoaded() async {
    if (_initTried) return available;
    _initTried = true;
    try {
      OrtEnv.instance.init();
      final encBytes =
          (await rootBundle.load(_encoderAsset)).buffer.asUint8List();
      final decBytes =
          (await rootBundle.load(_decoderAsset)).buffer.asUint8List();
      final opt = OrtSessionOptions();
      _encoder = OrtSession.fromBuffer(encBytes, opt);
      _decoder = OrtSession.fromBuffer(decBytes, opt);
      debugPrint('SAM encoder inputs=${_encoder!.inputNames} '
          'outputs=${_encoder!.outputNames}');
      debugPrint('SAM decoder inputs=${_decoder!.inputNames} '
          'outputs=${_decoder!.outputNames}');
      return true;
    } catch (e) {
      debugPrint('SAM load failed: $e');
      _encoder = null;
      _decoder = null;
      return false;
    }
  }

  /// 确保当前 guide 的 embedding 已就绪（签名命中则跳过）
  Future<void> ensureEmbedding({
    required Uint8List guide, // RGBA
    required int gw,
    required int gh,
    required Object signature,
  }) async {
    if (!available) return;
    if (_embSig == signature && _emb != null) return;

    final longest = math.max(gw, gh);
    final scale = _inputSize / longest;
    final newW = (gw * scale).round().clamp(1, _inputSize);
    final newH = (gh * scale).round().clamp(1, _inputSize);

    // NCHW 归一化输入（双线性重采样 guide → newW×newH，右下补零）
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

    final encIn = _encoder!.inputNames.first;
    final t = OrtValueTensor.createTensorWithDataList(
        input, [1, 3, _inputSize, _inputSize]);
    final ro = OrtRunOptions();
    final outs = _encoder!.run(ro, {encIn: t});
    final emb = _toFloat32(outs[0]!.value, _embShape);
    t.release();
    ro.release();
    for (final o in outs) {
      o?.release();
    }

    _emb = emb;
    _embSig = signature;
    _gw = gw;
    _gh = gh;
    _newW = newW;
    _newH = newH;
  }

  /// 按点解码，返回 gw×gh 的 0..1 软 mask
  Future<Float32List?> decode(ui.Offset seedNorm) async {
    if (!available || _emb == null) return null;
    final gw = _gw, gh = _gh;
    final scale = _inputSize / math.max(gw, gh);
    final px = (seedNorm.dx * gw) * scale; // 1024 空间的 x
    final py = (seedNorm.dy * gh) * scale; // 1024 空间的 y

    // EdgeSAM: 坐标 (height,width)=(y,x)，单个正样本点(label=1)，无填充点
    // ⚠️ 若选区沿对角线镜像，把下一行的 [py, px] 改成 [px, py]
    final coords = Float32List.fromList([py, px]);
    final labels = Float32List.fromList([1]);

    final emb =
        OrtValueTensor.createTensorWithDataList(_emb!, _embShape);
    final coordT =
        OrtValueTensor.createTensorWithDataList(coords, [1, 1, 2]);
    final labelT =
        OrtValueTensor.createTensorWithDataList(labels, [1, 1]);

    final created = <OrtValueTensor>[emb, coordT, labelT];
    final inNames = _decoder!.inputNames;
    final inputs = <String, OrtValue>{};

    if (inNames.length <= 3) {
      // EdgeSAM：按顺序 [embeddings, coords, labels]
      inputs[inNames[0]] = emb;
      inputs[inNames[1]] = coordT;
      inputs[inNames[2]] = labelT;
    } else {
      // 原版 SAM 6 输入：按名字补齐（容错保留）
      final mi = OrtValueTensor.createTensorWithDataList(
          Float32List(256 * 256), [1, 1, 256, 256]);
      final hmi =
          OrtValueTensor.createTensorWithDataList(Float32List(1), [1]);
      final ois = OrtValueTensor.createTensorWithDataList(
          Float32List.fromList([gh.toDouble(), gw.toDouble()]), [2]);
      created.addAll([mi, hmi, ois]);
      final byName = <String, OrtValueTensor>{
        'image_embeddings': emb,
        'point_coords': coordT,
        'point_labels': labelT,
        'mask_input': mi,
        'has_mask_input': hmi,
        'orig_im_size': ois,
      };
      for (final n in inNames) {
        final c = byName[n];
        if (c != null) inputs[n] = c;
      }
    }

    final ro = OrtRunOptions();
    final outs = _decoder!.run(ro, inputs);

    final names = _decoder!.outputNames;
    int oi = names.indexWhere((n) => n.contains('low_res'));
    if (oi < 0) oi = names.indexWhere((n) => n.contains('mask'));
    if (oi < 0) oi = 0;
    final grid = _maskGrid(outs[oi]!.value);

    ro.release();
    for (final t in created) {
      t.release();
    }
    for (final o in outs) {
      o?.release();
    }

    final outH = grid.length, outW = grid[0].length;
    final upscaled = (outW == gw && outH == gh);
    final validW = upscaled ? outW.toDouble() : outW * (_newW / _inputSize);
    final validH = upscaled ? outH.toDouble() : outH * (_newH / _inputSize);

    final mask = Float32List(gw * gh);
    for (int j = 0; j < gh; j++) {
      final v = (j + 0.5) / gh * validH - 0.5;
      final v0 = v.floor().clamp(0, outH - 1);
      final v1 = (v0 + 1).clamp(0, outH - 1);
      final fy = (v - v0).clamp(0.0, 1.0);
      for (int i = 0; i < gw; i++) {
        final u = (i + 0.5) / gw * validW - 0.5;
        final u0 = u.floor().clamp(0, outW - 1);
        final u1 = (u0 + 1).clamp(0, outW - 1);
        final fx = (u - u0).clamp(0.0, 1.0);
        final top = grid[v0][u0] + (grid[v0][u1] - grid[v0][u0]) * fx;
        final bot = grid[v1][u0] + (grid[v1][u1] - grid[v1][u0]) * fx;
        final logit = top + (bot - top) * fy;
        mask[j * gw + i] = 1.0 / (1.0 + math.exp(-logit)); // sigmoid 软 mask
      }
    }
    return mask;
  }

  // 鲁棒：自动剥到 [h][w]（兼容 2D/3D/4D 输出），取第一个 mask 通道
  List<List<double>> _maskGrid(dynamic v) {
    List cur = v as List;
    while (cur.isNotEmpty &&
        cur[0] is List &&
        (cur[0] as List).isNotEmpty &&
        (cur[0] as List)[0] is List) {
      cur = cur[0] as List;
    }
    return [
      for (final row in cur)
        [for (final e in (row as List)) (e as num).toDouble()]
    ];
  }

  // 把 encoder 输出 [1,ch,h,w] 展平到 Float32List，并回填真实 shape
  Float32List _toFloat32(dynamic v, List<int> shapeOut) {
    final l0 = v as List;
    final l1 = l0[0] as List;
    final l2 = l1[0] as List;
    final l3 = l2[0] as List;
    final c = l0.length, ch = l1.length, hh = l2.length, ww = l3.length;
    shapeOut
      ..clear()
      ..addAll([c, ch, hh, ww]);
    final out = Float32List(c * ch * hh * ww);
    int idx = 0;
    for (int a = 0; a < c; a++) {
      final la = l0[a] as List;
      for (int b = 0; b < ch; b++) {
        final lb = la[b] as List;
        for (int y = 0; y < hh; y++) {
          final ly = lb[y] as List;
          for (int x = 0; x < ww; x++) {
            out[idx++] = (ly[x] as num).toDouble();
          }
        }
      }
    }
    return out;
  }
}