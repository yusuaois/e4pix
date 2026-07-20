import 'package:flutter/material.dart';

import '../../../../core/models/tone_curve.dart';

// 坐标转换与手势计算

/// 局部像素坐标 → 归一化 [0,1] 空间
Offset2 toNorm(Offset local, Size size) => Offset2(
  (local.dx / size.width).clamp(0.0, 1.0),
  (1 - local.dy / size.height).clamp(0.0, 1.0),
);

/// 归一化点 → 像素坐标
Offset toScreen(Offset2 p, Size size) =>
    Offset(p.x * size.width, (1 - p.y) * size.height);

/// 命中测试：返回 [local] 处最近的控制点索引，否则 null
int? hitTest(
  Offset local,
  Size size,
  ToneCurve curve, {
  double hitRadius = 22.0,
}) {
  for (int i = 0; i < curve.points.length; i++) {
    if ((toScreen(curve.points[i], size) - local).distance < hitRadius) {
      return i;
    }
  }
  return null;
}

/// 点击添加控制点，返回新的 [ToneCurve]；命中已有控制点则返回 null
ToneCurve? handleTapUp(Offset local, Size size, ToneCurve curve) {
  if (hitTest(local, size, curve) != null) return null;
  final n = toNorm(local, size);
  final pts = [...curve.points, Offset2(n.x, n.y)]
    ..sort((a, b) => a.x.compareTo(b.x));
  return ToneCurve(pts);
}

/// 拖拽移动控制点，返回新的 [ToneCurve]；[dragIndex] 为 null 时返回 null
ToneCurve? handlePanUpdate(
  Offset local,
  Size size,
  ToneCurve curve,
  int? dragIndex,
) {
  if (dragIndex == null) return null;
  final n = toNorm(local, size);
  final pts = [...curve.points];
  final isFirst = dragIndex == 0, isLast = dragIndex == pts.length - 1;
  double nx;
  if (isFirst) {
    nx = 0.0;
  } else if (isLast) {
    nx = 1.0;
  } else {
    nx = n.x.clamp(pts[dragIndex - 1].x + 0.01, pts[dragIndex + 1].x - 0.01);
  }
  pts[dragIndex] = Offset2(nx, n.y);
  return ToneCurve(pts);
}

/// 长按删除控制点，返回新的 [ToneCurve]；不可删除首尾控制点
ToneCurve? handleLongPress(Offset local, Size size, ToneCurve curve) {
  final hit = hitTest(local, size, curve);
  if (hit == null || hit == 0 || hit == curve.points.length - 1) return null;
  final pts = [...curve.points]..removeAt(hit);
  return ToneCurve(pts);
}
