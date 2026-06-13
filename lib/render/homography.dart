import 'dart:typed_data';

import '../core/models/perspective_params.dart';

/// 逆向映射：从目标正方形反查到源四边形（用于 shader 像素逆映射）
///
/// 固定 h₂₂ = 1，4 对点构建 8×8 线性系统，一次高斯消元求解。
/// 返回 Float32List(9)，GLSL mat3 列主序。
Float32List computeInverseHomography8x8({required PerspectiveParams params}) {
  return _solve8x8(PerspectiveParams.destQuad, params.sourceQuad);
}

// ── 内部 8×8 求解器 ──────────────────────────────────────────────

Float32List _solve8x8(
  List<({double x, double y})> src,
  List<({double x, double y})> dst,
) {
  final a = List.generate(8, (_) => Float64List(8));
  final b = Float64List(8);

  for (int i = 0; i < 4; i++) {
    final x = src[i].x, y = src[i].y;
    final X = dst[i].x, Y = dst[i].y;

    final r1 = 2 * i;
    a[r1][0] = x;
    a[r1][1] = y;
    a[r1][2] = 1.0;
    a[r1][7] = -x * X;
    a[r1][8 - 2] = -y * X; // wait, index 6 and 7
    b[r1] = X;

    final r2 = 2 * i + 1;
    a[r2][3] = x;
    a[r2][4] = y;
    a[r2][5] = 1.0;
    a[r2][6] = -x * Y;
    a[r2][7] = -y * Y;
    b[r2] = Y;
  }

  final h = _gauss8(a, b);

  // GLSL mat3 列主序，h₂₂ = 1
  final result = Float32List(9);
  result[0] = h[0];
  result[1] = h[3];
  result[2] = h[6];
  result[3] = h[1];
  result[4] = h[4];
  result[5] = h[7];
  result[6] = h[2];
  result[7] = h[5];
  result[8] = 1.0;
  return result;
}

/// 部分选主元高斯消元 8×8
List<double> _gauss8(List<Float64List> a, Float64List b) {
  const n = 8;
  final m = List.generate(n, (i) {
    final row = Float64List(n + 1);
    for (int j = 0; j < n; j++) {
      row[j] = a[i][j];
    }
    row[n] = b[i];
    return row;
  });

  for (int col = 0; col < n; col++) {
    int best = col;
    double bestVal = m[col][col].abs();
    for (int row = col + 1; row < n; row++) {
      if (m[row][col].abs() > bestVal) {
        bestVal = m[row][col].abs();
        best = row;
      }
    }
    if (bestVal < 1e-15) continue;

    if (best != col) {
      final tmp = m[col];
      m[col] = m[best];
      m[best] = tmp;
    }

    final pivot = m[col][col];
    for (int row = col + 1; row < n; row++) {
      final factor = m[row][col] / pivot;
      for (int j = col; j <= n; j++) {
        m[row][j] -= factor * m[col][j];
      }
    }
  }

  final x = Float64List(n);
  for (int i = n - 1; i >= 0; i--) {
    double sum = m[i][n];
    for (int j = i + 1; j < n; j++) {
      sum -= m[i][j] * x[j];
    }
    x[i] = m[i][i].abs() > 1e-15 ? sum / m[i][i] : 0.0;
  }
  return x;
}

// ── 缓存 ──────────────────────────────────────────────────────────

/// 逆单应性矩阵缓存
///
/// 矩阵仅随 perspectiveParams 变化，帧间重复计算纯属浪费。
class PerspectiveMatrixCache {
  int _lastHash = 0;
  Float32List? _cached;

  /// 获取逆单应性矩阵（用于 shader 的 uInvHomography）
  Float32List get(PerspectiveParams params, int imgW, int imgH) {
    final newHash = Object.hash(
      params.topLeftX,
      params.topLeftY,
      params.topRightX,
      params.topRightY,
      params.bottomRightX,
      params.bottomRightY,
      params.bottomLeftX,
      params.bottomLeftY,
      imgW,
      imgH,
    );
    if (newHash == _lastHash && _cached != null) {
      return _cached!;
    }
    _lastHash = newHash;
    _cached = computeInverseHomography8x8(params: params);
    return _cached!;
  }

  void invalidate() {
    _lastHash = 0;
    _cached = null;
  }
}
