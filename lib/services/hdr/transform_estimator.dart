import 'dart:math' as math;
import 'dart:ui';

/// 变换类型（按复杂度递增）
enum TransformType {
  /// 纯平移（1 对点）
  translation,

  /// 相似变换：平移 + 旋转 + 均匀缩放（2 对点）
  similarity,

  /// 仿射变换：平移 + 旋转 + 缩放 + 剪切（3 对点）
  affine,

  /// 单应性：透视变换（4 对点）
  homography,
}

/// 对齐变换结果
class AlignmentTransform {
  /// 3×3 行优先矩阵（source → reference 坐标变换）
  final List<double> matrix;

  /// 变换类型
  final TransformType type;

  /// 内点率 [0, 1]
  final double inlierRatio;

  /// 内点数
  final int inlierCount;

  const AlignmentTransform({
    required this.matrix,
    required this.type,
    required this.inlierRatio,
    required this.inlierCount,
  });

  /// 单位矩阵（无变换）
  static const AlignmentTransform identity = AlignmentTransform(
    matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
    type: TransformType.translation,
    inlierRatio: 1.0,
    inlierCount: 0,
  );
}

/// 变换估计器：RANSAC + 最小二乘
class TransformEstimator {
  TransformEstimator._();

  static const double _inlierThreshold = 2.5;
  static const int _maxIterations = 2000;
  static const double _minInlierRatio = 0.3;
  static const double _earlyTerminationRatio = 0.8;
  static const int _ransacSeed = 42;
  static const int _iterationMultiplier = 20;

  /// RANSAC 估计最佳变换
  ///
  /// [srcPoints] / [dstPoints]：匹配对（全分辨率坐标）
  /// [targetType]：目标变换类型
  ///
  /// 返回最佳 [AlignmentTransform]，若匹配不足或内点率过低返回 null
  static AlignmentTransform? ransacEstimate({
    required List<Offset> srcPoints,
    required List<Offset> dstPoints,
    TransformType targetType = TransformType.affine,
  }) {
    final n = srcPoints.length;
    if (n < _minSamples(targetType)) return null;

    // 按复杂度递增尝试
    final typesToTry = _typesUpTo(targetType);

    AlignmentTransform? best;
    for (final type in typesToTry) {
      final result = _ransacForType(srcPoints, dstPoints, type);
      if (result == null) continue;
      if (best == null || result.inlierCount > best.inlierCount) {
        best = result;
      }
      // 内点率足够高，不需要尝试更复杂类型
      if (result.inlierRatio > _earlyTerminationRatio) break;
    }

    if (best != null && best.inlierRatio >= _minInlierRatio) return best;
    return null;
  }

  static List<TransformType> _typesUpTo(TransformType type) {
    switch (type) {
      case TransformType.translation:
        return [TransformType.translation];
      case TransformType.similarity:
        return [TransformType.translation, TransformType.similarity];
      case TransformType.affine:
        return [
          TransformType.translation,
          TransformType.similarity,
          TransformType.affine,
        ];
      case TransformType.homography:
        return [
          TransformType.translation,
          TransformType.similarity,
          TransformType.affine,
          TransformType.homography,
        ];
    }
  }

  static int _minSamples(TransformType type) {
    switch (type) {
      case TransformType.translation:
        return 1;
      case TransformType.similarity:
        return 2;
      case TransformType.affine:
        return 3;
      case TransformType.homography:
        return 4;
    }
  }

  static AlignmentTransform? _ransacForType(
    List<Offset> src,
    List<Offset> dst,
    TransformType type,
  ) {
    final n = src.length;
    final minN = _minSamples(type);
    if (n < minN) return null;

    final rng = math.Random(_ransacSeed);
    final iterations = math.min(_maxIterations, n * _iterationMultiplier);

    int bestInliers = 0;
    List<double>? bestMatrix;

    for (int iter = 0; iter < iterations; iter++) {
      // 采样不重复的点
      final indices = <int>{};
      while (indices.length < minN) {
        indices.add(rng.nextInt(n));
      }
      final sample = indices.toList();

      // 用采样点拟合变换
      final matrix = _fitTransform(
        sample.map((i) => src[i]).toList(),
        sample.map((i) => dst[i]).toList(),
        type,
      );
      if (matrix == null) continue;

      // 计算内点数
      int inliers = 0;
      for (int i = 0; i < n; i++) {
        final dx = src[i].dx;
        final dy = src[i].dy;
        final w = matrix[6] * dx + matrix[7] * dy + matrix[8];
        if (w.abs() < 1e-10) continue;
        final tx = (matrix[0] * dx + matrix[1] * dy + matrix[2]) / w;
        final ty = (matrix[3] * dx + matrix[4] * dy + matrix[5]) / w;
        final err = math.sqrt(
          (tx - dst[i].dx) * (tx - dst[i].dx) +
              (ty - dst[i].dy) * (ty - dst[i].dy),
        );
        if (err < _inlierThreshold) inliers++;
      }

      if (inliers > bestInliers) {
        bestInliers = inliers;
        bestMatrix = matrix;
      }
    }

    if (bestMatrix == null || bestInliers < minN) return null;

    // 用所有内点重新拟合（最小二乘）
    final inlierSrc = <Offset>[];
    final inlierDst = <Offset>[];
    for (int i = 0; i < n; i++) {
      final dx = src[i].dx;
      final dy = src[i].dy;
      final w = bestMatrix[6] * dx + bestMatrix[7] * dy + bestMatrix[8];
      if (w.abs() < 1e-10) continue;
      final tx = (bestMatrix[0] * dx + bestMatrix[1] * dy + bestMatrix[2]) / w;
      final ty = (bestMatrix[3] * dx + bestMatrix[4] * dy + bestMatrix[5]) / w;
      final err = math.sqrt(
        (tx - dst[i].dx) * (tx - dst[i].dx) +
            (ty - dst[i].dy) * (ty - dst[i].dy),
      );
      if (err < _inlierThreshold) {
        inlierSrc.add(src[i]);
        inlierDst.add(dst[i]);
      }
    }

    final refined = _fitTransform(inlierSrc, inlierDst, type);
    if (refined == null) return null;

    return AlignmentTransform(
      matrix: refined,
      type: type,
      inlierRatio: bestInliers / n,
      inlierCount: bestInliers,
    );
  }

  /// 用最小二乘拟合指定类型的变换
  static List<double>? _fitTransform(
    List<Offset> src,
    List<Offset> dst,
    TransformType type,
  ) {
    switch (type) {
      case TransformType.translation:
        return _fitTranslation(src, dst);
      case TransformType.similarity:
        return _fitSimilarity(src, dst);
      case TransformType.affine:
        return _fitAffine(src, dst);
      case TransformType.homography:
        return _fitHomography(src, dst);
    }
  }

  /// 平移：T * [x,y,1] = [x+tx, y+ty, 1]
  static List<double>? _fitTranslation(List<Offset> src, List<Offset> dst) {
    double sumDx = 0, sumDy = 0;
    for (int i = 0; i < src.length; i++) {
      sumDx += dst[i].dx - src[i].dx;
      sumDy += dst[i].dy - src[i].dy;
    }
    final tx = sumDx / src.length;
    final ty = sumDy / src.length;
    return [1, 0, tx, 0, 1, ty, 0, 0, 1];
  }

  /// 相似变换：s*R*[x,y] + [tx,ty]
  static List<double>? _fitSimilarity(List<Offset> src, List<Offset> dst) {
    if (src.length < 2) return null;

    // 构建超定方程组 A * [a, b, tx, ty]^T = b
    // [x, -y, 1, 0] [a ]   [x']
    // [y,  x, 0, 1] [b ] = [y']
    final n = src.length;
    // A^T * A (4×4)
    final ata = List<double>.filled(16, 0);
    final atb = List<double>.filled(4, 0);

    for (int i = 0; i < n; i++) {
      final x = src[i].dx, y = src[i].dy;
      final xp = dst[i].dx, yp = dst[i].dy;
      // Row 0: [x, -y, 1, 0] → xp
      _addToNormal(ata, atb, [x, -y, 1, 0], xp, 4);
      // Row 1: [y, x, 0, 1] → yp
      _addToNormal(ata, atb, [y, x, 0, 1], yp, 4);
    }

    final sol = _solveLinear(ata, atb, 4);
    if (sol == null) return null;
    final a = sol[0], b = sol[1], tx = sol[2], ty = sol[3];
    return [a, -b, tx, b, a, ty, 0, 0, 1];
  }

  /// 仿射变换（6 参数）
  static List<double>? _fitAffine(List<Offset> src, List<Offset> dst) {
    if (src.length < 3) return null;

    final n = src.length;
    final ata = List<double>.filled(36, 0);
    final atb = List<double>.filled(6, 0);

    for (int i = 0; i < n; i++) {
      final x = src[i].dx, y = src[i].dy;
      // Row 0: [x, y, 1, 0, 0, 0] → xp
      _addToNormal(ata, atb, [x, y, 1, 0, 0, 0], dst[i].dx, 6);
      // Row 1: [0, 0, 0, x, y, 1] → yp
      _addToNormal(ata, atb, [0, 0, 0, x, y, 1], dst[i].dy, 6);
    }

    final sol = _solveLinear(ata, atb, 6);
    if (sol == null) return null;
    return [sol[0], sol[1], sol[2], sol[3], sol[4], sol[5], 0, 0, 1];
  }

  /// 单应性（固定 h[8]=1，求解 8 参数）
  ///
  /// h = [h0..h7, 1]，方程：
  ///   x' = (h0*x + h1*y + h2 - h6*x*x' - h7*y*x')   → rhs = x'
  ///   y' = (h3*x + h4*y + h5 - h6*x*y' - h7*y*y')   → rhs = y'
  static List<double>? _fitHomography(List<Offset> src, List<Offset> dst) {
    if (src.length < 4) return null;

    final n = src.length;
    // 8×8 法方程矩阵
    final ata = List<double>.filled(64, 0);
    final atb = List<double>.filled(8, 0);

    for (int i = 0; i < n; i++) {
      final x = src[i].dx, y = src[i].dy;
      final xp = dst[i].dx, yp = dst[i].dy;
      // X 轴方程: [x, y, 1, 0, 0, 0, -x*xp, -y*xp] → xp
      _addToNormal(ata, atb, [x, y, 1, 0, 0, 0, -x * xp, -y * xp], xp, 8);
      // Y 轴方程: [0, 0, 0, x, y, 1, -x*yp, -y*yp] → yp
      _addToNormal(ata, atb, [0, 0, 0, x, y, 1, -x * yp, -y * yp], yp, 8);
    }

    final sol = _solveLinear(ata, atb, 8);
    if (sol == null) return null;
    return [
      sol[0],
      sol[1],
      sol[2],
      sol[3],
      sol[4],
      sol[5],
      sol[6],
      sol[7],
      1.0,
    ];
  }

  /// A^T * A 累加
  static void _addToNormal(
    List<double> ata,
    List<double> atb,
    List<double> row,
    double rhs,
    int n,
  ) {
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        ata[i * n + j] += row[i] * row[j];
      }
      atb[i] += row[i] * rhs;
    }
  }

  /// 高斯消元求解 n×n 线性方程组
  static List<double>? _solveLinear(List<double> ata, List<double> atb, int n) {
    // 复制矩阵
    final a = List<double>.from(ata);
    final b = List<double>.from(atb);

    for (int col = 0; col < n; col++) {
      // 部分主元选取
      int maxRow = col;
      double maxVal = a[col * n + col].abs();
      for (int row = col + 1; row < n; row++) {
        final val = a[row * n + col].abs();
        if (val > maxVal) {
          maxVal = val;
          maxRow = row;
        }
      }
      if (maxVal < 1e-12) return null; // 奇异矩阵

      // 交换行
      if (maxRow != col) {
        for (int j = col; j < n; j++) {
          final tmp = a[col * n + j];
          a[col * n + j] = a[maxRow * n + j];
          a[maxRow * n + j] = tmp;
        }
        final tmp = b[col];
        b[col] = b[maxRow];
        b[maxRow] = tmp;
      }

      // 消元
      final pivot = a[col * n + col];
      for (int row = col + 1; row < n; row++) {
        final factor = a[row * n + col] / pivot;
        for (int j = col; j < n; j++) {
          a[row * n + j] -= factor * a[col * n + j];
        }
        b[row] -= factor * b[col];
      }
    }

    // 回代
    final x = List<double>.filled(n, 0);
    for (int i = n - 1; i >= 0; i--) {
      double sum = b[i];
      for (int j = i + 1; j < n; j++) {
        sum -= a[i * n + j] * x[j];
      }
      final diag = a[i * n + i];
      if (diag.abs() < 1e-12) return null;
      x[i] = sum / diag;
    }
    return x;
  }
}
