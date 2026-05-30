import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 一条色调曲线，由控制点定义（归一化 [0,1]）
/// 默认 [(0,0),(1,1)] = 直线（不改变）
@immutable
class ToneCurve {
  /// 控制点，按 x 升序
  final List<Offset2> points;

  const ToneCurve(this.points);

  static const ToneCurve identity = ToneCurve([Offset2(0, 0), Offset2(1, 1)]);

  bool get isIdentity =>
      points.length == 2 &&
      points[0].x == 0 &&
      points[0].y == 0 &&
      points[1].x == 1 &&
      points[1].y == 1;

  ToneCurve copyWith({List<Offset2>? points}) =>
      ToneCurve(points ?? this.points);

  /// 采样成 [count] 个点的查找表（y 值，0..1），单调三次插值
  Float32List toLut({int count = 256}) {
    final out = Float32List(count);
    final pts = [...points]..sort((a, b) => a.x.compareTo(b.x));
    final n = pts.length;

    if (n < 2) {
      for (int j = 0; j < count; j++) {
        out[j] = (j / (count - 1)).clamp(0.0, 1.0);
      }
      return out;
    }

    final xs = [for (final p in pts) p.x];
    final ys = [for (final p in pts) p.y];

    // 段斜率
    final d = List<double>.filled(n - 1, 0);
    for (int i = 0; i < n - 1; i++) {
      final dx = xs[i + 1] - xs[i];
      d[i] = dx.abs() < 1e-6 ? 0 : (ys[i + 1] - ys[i]) / dx;
    }

    // 各点切线
    final m = List<double>.filled(n, 0);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (int i = 1; i < n - 1; i++) {
      if (d[i - 1] * d[i] <= 0) {
        m[i] = 0;
      } else {
        m[i] = (d[i - 1] + d[i]) / 2;
      }
    }

    // 防过冲
    for (int i = 0; i < n - 1; i++) {
      if (d[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
      } else {
        final a = m[i] / d[i];
        final b = m[i + 1] / d[i];
        final s = a * a + b * b;
        if (s > 9) {
          final tau = 3 / math.sqrt(s);
          m[i] = tau * a * d[i];
          m[i + 1] = tau * b * d[i];
        }
      }
    }

    // 采样
    int seg = 0;
    for (int j = 0; j < count; j++) {
      final x = j / (count - 1);
      while (seg < n - 2 && x > xs[seg + 1]) {
        seg++;
      }
      final x0 = xs[seg], x1 = xs[seg + 1];
      final h = x1 - x0;
      double y;
      if (h.abs() < 1e-6) {
        y = ys[seg];
      } else {
        final t = ((x - x0) / h).clamp(0.0, 1.0);
        final t2 = t * t, t3 = t2 * t;
        final h00 = 2 * t3 - 3 * t2 + 1;
        final h10 = t3 - 2 * t2 + t;
        final h01 = -2 * t3 + 3 * t2;
        final h11 = t3 - t2;
        y = h00 * ys[seg] + h10 * h * m[seg] + h01 * ys[seg + 1] + h11 * h * m[seg + 1];
      }
      out[j] = y.clamp(0.0, 1.0);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'points': [
      for (final p in points) [p.x, p.y],
    ],
  };

  factory ToneCurve.fromJson(Map<String, dynamic> j) {
    final raw = (j['points'] as List?) ?? const [];
    if (raw.length < 2) return identity;
    return ToneCurve([
      for (final e in raw) Offset2((e as List)[0] as double, e[1] as double),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is ToneCurve && listEquals(points, other.points);

  @override
  int get hashCode => Object.hashAll(points);
}

@immutable
class Offset2 {
  final double x, y;
  const Offset2(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is Offset2 && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}
