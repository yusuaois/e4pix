import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// 导出降噪引擎选择：
/// - [gpu]：复用预览的 GPU shader，全尺寸跑一遍，秒级，效果与预览一致
/// - [cpu]：16-bit 线性域双边滤波，多 isolate 并行，质量最佳但较慢
enum DenoiseEngine { gpu, cpu }

/// 颜色降噪满强度时的最大采样半径（像素）
/// 并行分块的 halo（上下重叠行数）必须 >= 此值，否则带边界降噪不连续
const int kMaxDenoiseRadius = 24;

/// 多 isolate 分块并行 CPU 降噪
///
/// 把图按行切成 [parallelism] 条横带，每条带含上下各 [kMaxDenoiseRadius] 行
/// halo 作邻域参考，降噪后只保留本带行，最后按顺序拼接。各带在独立 isolate
/// 并行计算。[parallelism] <= 0 表示自动（取 CPU 核心数）
///
/// 输入/输出均为 16-bit 线性 RGB 交错（每像素 3 通道，0-65535）
Future<Uint16List> cpuDenoiseParallel(
  Uint16List src,
  int width,
  int height,
  double luma,
  double color, {
  required void Function(double) onProgress,
  int parallelism = 4,
}) async {
  int nBands = parallelism <= 0 ? Platform.numberOfProcessors : parallelism;
  if (nBands > 16) nBands = 16;
  if (nBands < 1) nBands = 1;
  // 行数太少不值得切分，退化单线程
  if (height < nBands * (2 * kMaxDenoiseRadius + 4)) nBands = 1;

  final rowsPerBand = (height / nBands).ceil();

  // 准备纯数据任务
  final tasks = <_BandTask>[];
  for (int b = 0; b < nBands; b++) {
    final startRow = b * rowsPerBand;
    if (startRow >= height) continue;
    final endRow = math.min(startRow + rowsPerBand, height);
    final bandRows = endRow - startRow;
    final haloStart = math.max(0, startRow - kMaxDenoiseRadius);
    final haloEnd = math.min(height, endRow + kMaxDenoiseRadius);
    final haloTop = startRow - haloStart;
    final totalRows = haloEnd - haloStart;

    final bandLen = totalRows * width * 3;
    final bandPixels = Uint16List(bandLen);
    bandPixels.setRange(0, bandLen, src, haloStart * width * 3);

    tasks.add(
      _BandTask(
        bandId: b,
        pixels: bandPixels,
        width: width,
        totalRows: totalRows,
        bandRows: bandRows,
        haloTop: haloTop,
        luma: luma,
        color: color,
      ),
    );
  }

  // 启动所有 isolate
  final futures = <Future<_BandOut>>[];
  for (final task in tasks) {
    futures.add(_runBandIsolate(task));
  }

  // 收集结果 + 报进度
  int completed = 0;
  final total = futures.length;
  final outs = <_BandOut>[];
  for (final f in futures) {
    final out = await f;
    outs.add(out);
    completed++;
    onProgress(completed / total);
  }

  // 按 bandId 顺序拼接
  final result = Uint16List(width * height * 3);
  outs.sort((a, b) => a.bandId.compareTo(b.bandId));
  int offset = 0;
  for (final o in outs) {
    result.setRange(offset, offset + o.pixels.length, o.pixels);
    offset += o.pixels.length;
  }
  return result;
}

// ── 并行内部实现 ──────────────────────────────────────────────

Future<_BandOut> _runBandIsolate(_BandTask task) {
  return Isolate.run(() => _denoiseBandTask(task));
}

/// 纯数据任务包
class _BandTask {
  final int bandId;
  final Uint16List pixels; // 含 halo 的 16-bit RGB 交错
  final int width;
  final int totalRows; // 含 halo 的总行数
  final int bandRows; // 本带实际输出行数
  final int haloTop; // 顶部 halo 行数（带内偏移）
  final double luma;
  final double color;
  _BandTask({
    required this.bandId,
    required this.pixels,
    required this.width,
    required this.totalRows,
    required this.bandRows,
    required this.haloTop,
    required this.luma,
    required this.color,
  });
}

class _BandOut {
  final int bandId;
  final Uint16List pixels;
  _BandOut(this.bandId, this.pixels);
}

/// 在 isolate 中降噪含 halo 的块，截取本带输出行
_BandOut _denoiseBandTask(_BandTask t) {
  final denoised = denoise16Linear(
    t.pixels,
    t.width,
    t.totalRows,
    t.luma,
    t.color,
  );
  final result = Uint16List(t.width * t.bandRows * 3);
  result.setRange(0, result.length, denoised, t.haloTop * t.width * 3);
  return _BandOut(t.bandId, result);
}

// ── 降噪算法 ──────────────────────────────────────────────────

/// 16-bit 线性 RGB 交错 → 双边滤波降噪 → 16-bit 线性 RGB 交错。
///
/// YCbCr 分离：明度（Y）做 5×5 双边滤波保细节，色度（Cb/Cr）做大半径稀疏
/// 双边滤波消彩斑。range/空间权重均预计算查表，避免每像素 math.exp。
Uint16List denoise16Linear(
  Uint16List src,
  int w,
  int h,
  double luma,
  double color, {
  void Function(double)? onProgress,
}) {
  final out = Uint16List(src.length);
  final n = w * h;

  // RGB → YCbCr（BT.709，归一化 0-1）
  final yCh = Float32List(n);
  final cbCh = Float32List(n);
  final crCh = Float32List(n);
  const inv = 1.0 / 65535.0;
  for (int i = 0; i < n; i++) {
    final si = i * 3;
    final r = src[si] * inv;
    final g = src[si + 1] * inv;
    final b = src[si + 2] * inv;
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    yCh[i] = y;
    cbCh[i] = (b - y) * 0.5389 + 0.5;
    crCh[i] = (r - y) * 0.6350 + 0.5;
  }

  final sigmaY = _lerp(0.003, 0.05, luma);
  final sigmaC = _lerp(0.02, 0.35, color);
  const int ry = 2; // 明度 5×5
  final double radiusC = _lerp(6.0, 24.0, color); // 颜色半径，满强度 ±24
  final int stepsC = 4; // 颜色稀疏 9×9
  final double stepC = radiusC / stepsC;
  const double spatialY2 = 4.0;
  final double spatialC2 = radiusC * radiusC * 0.35;

  // range 权重查找表：exp(-0..kLutMax)
  const int kLutSize = 2048;
  const double kLutMax = 10.0;
  final expLut = Float32List(kLutSize);
  for (int i = 0; i < kLutSize; i++) {
    expLut[i] = math.exp(-(i / kLutSize) * kLutMax);
  }

  // 明度空间权重预计算 (5×5)
  final int wy = 2 * ry + 1;
  final spatialYLut = Float32List(wy * wy);
  {
    int k = 0;
    for (int dy = -ry; dy <= ry; dy++) {
      for (int dx = -ry; dx <= ry; dx++) {
        spatialYLut[k++] = math.exp(-(dx * dx + dy * dy) / (2.0 * spatialY2));
      }
    }
  }

  // 颜色空间权重 + 整数偏移预计算 (9×9 稀疏)
  final int wc = 2 * stepsC + 1;
  final spatialCLut = Float32List(wc * wc);
  final offCx = Int32List(wc * wc);
  final offCy = Int32List(wc * wc);
  {
    int k = 0;
    for (int sy = -stepsC; sy <= stepsC; sy++) {
      for (int sx = -stepsC; sx <= stepsC; sx++) {
        final ox = sx * stepC, oy = sy * stepC;
        spatialCLut[k] = math.exp(-(ox * ox + oy * oy) / (2.0 * spatialC2));
        offCx[k] = ox.round();
        offCy[k] = oy.round();
        k++;
      }
    }
  }

  final double invDenomY = 1.0 / (2.0 * sigmaY * sigmaY);
  final double invDenomC = 1.0 / (2.0 * sigmaC * sigmaC);
  final double lutScale = kLutSize / kLutMax;

  final outY = Float32List(n);
  final outCb = Float32List(n);
  final outCr = Float32List(n);

  final doLuma = luma > 0.001;
  final doColor = color > 0.001;

  for (int y0 = 0; y0 < h; y0++) {
    for (int x0 = 0; x0 < w; x0++) {
      final ci = y0 * w + x0;
      final cY = yCh[ci], cCb = cbCh[ci], cCr = crCh[ci];

      // 明度 5×5 双边
      if (doLuma) {
        double acc = 0, sum = 0;
        int k = 0;
        for (int dy = -ry; dy <= ry; dy++) {
          final yy = y0 + dy;
          for (int dx = -ry; dx <= ry; dx++) {
            final xx = x0 + dx;
            if (yy < 0 || yy >= h || xx < 0 || xx >= w) {
              k++;
              continue;
            }
            final si = yy * w + xx;
            final spatial = spatialYLut[k++];
            final dY = yCh[si] - cY;
            final e = dY * dY * invDenomY * lutScale;
            final range = e >= kLutSize ? 0.0 : expLut[e.toInt()];
            final wgt = spatial * range;
            acc += yCh[si] * wgt;
            sum += wgt;
          }
        }
        outY[ci] = sum > 0 ? cY + (acc / sum - cY) * luma : cY;
      } else {
        outY[ci] = cY;
      }

      // 颜色 9×9 稀疏双边
      if (doColor) {
        double accCb = 0, accCr = 0, sum = 0;
        for (int k = 0; k < wc * wc; k++) {
          final yy = y0 + offCy[k];
          final xx = x0 + offCx[k];
          if (yy < 0 || yy >= h || xx < 0 || xx >= w) continue;
          final si = yy * w + xx;
          final spatial = spatialCLut[k];
          final dCb = cbCh[si] - cCb, dCr = crCh[si] - cCr;
          final e = (dCb * dCb + dCr * dCr) * invDenomC * lutScale;
          final range = e >= kLutSize ? 0.0 : expLut[e.toInt()];
          final wgt = spatial * range;
          accCb += cbCh[si] * wgt;
          accCr += crCh[si] * wgt;
          sum += wgt;
        }
        if (sum > 0) {
          outCb[ci] = cCb + (accCb / sum - cCb) * color;
          outCr[ci] = cCr + (accCr / sum - cCr) * color;
        } else {
          outCb[ci] = cCb;
          outCr[ci] = cCr;
        }
      } else {
        outCb[ci] = cCb;
        outCr[ci] = cCr;
      }
    }
    if ((y0 & 0x1F) == 0) onProgress?.call(y0 / h);
  }

  // YCbCr → RGB → 16-bit
  for (int i = 0; i < n; i++) {
    final yv = outY[i];
    final cb = outCb[i] - 0.5;
    final cr = outCr[i] - 0.5;
    final r = yv + cr * 1.5748;
    final b = yv + cb * 1.8556;
    final g = (yv - 0.2126 * r - 0.0722 * b) / 0.7152;
    final si = i * 3;
    out[si] = _clamp16(r);
    out[si + 1] = _clamp16(g);
    out[si + 2] = _clamp16(b);
  }
  return out;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

int _clamp16(double v) {
  final i = (v * 65535.0).round();
  return i < 0 ? 0 : (i > 65535 ? 65535 : i);
}
