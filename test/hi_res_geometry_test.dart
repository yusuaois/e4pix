import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:e4pix/render/hi_res/hi_res_geometry.dart';

void main() {
  // 统一场景：视口 1000×800，显示图 800×600（居中偏移 centerDx=100, centerDy=100），
  // 全尺寸裁剪后输出 4000×3000（比例 4:3，与显示图一致，sx=5, sy=5）
  const viewport = Size(1000, 800);
  const display = Size(800, 600);
  const fullOut = Size(4000, 3000);

  group('computeTileRects', () {
    test('identity 矩阵：可见区域 = 整个 displaySize', () {
      final r = computeTileRects(
        viewportTransform: Matrix4.identity(),
        viewportSize: viewport,
        displaySize: display,
        fullOutSize: fullOut,
      )!;

      expect(r.dst.left, closeTo(0, 0.001));
      expect(r.dst.top, closeTo(0, 0.001));
      expect(r.dst.width, closeTo(800, 0.001));
      expect(r.dst.height, closeTo(600, 0.001));
      expect(r.src.left, closeTo(0, 0.001));
      expect(r.src.top, closeTo(0, 0.001));
      expect(r.src.width, closeTo(4000, 0.001));
      expect(r.src.height, closeTo(3000, 0.001));
    });

    test('缩放 2x 围绕视口中心：可见区域缩小到中心一半', () {
      final zoom2 = Matrix4.identity()
        ..translateByDouble(500.0, 400.0, 0.0, 1.0)
        ..scaleByDouble(2.0, 2.0, 1.0, 1.0)
        ..translateByDouble(-500.0, -400.0, 0.0, 1.0);
      final r = computeTileRects(
        viewportTransform: zoom2,
        viewportSize: viewport,
        displaySize: display,
        fullOutSize: fullOut,
      )!;

      // 可见区域应为 display 中心 500×400
      expect(r.dst.left, closeTo(150, 0.001));
      expect(r.dst.top, closeTo(100, 0.001));
      expect(r.dst.width, closeTo(500, 0.001));
      expect(r.dst.height, closeTo(400, 0.001));
      // src 按 5x 放大
      expect(r.src.left, closeTo(750, 0.001));
      expect(r.src.top, closeTo(500, 0.001));
      expect(r.src.width, closeTo(2500, 0.001));
      expect(r.src.height, closeTo(2000, 0.001));
    });

    test('平移后越界：dst clamp 到 displaySize 边界', () {
      final pan = Matrix4.identity()
        ..translateByDouble(-200.0, -100.0, 0.0, 1.0);
      final r = computeTileRects(
        viewportTransform: pan,
        viewportSize: viewport,
        displaySize: display,
        fullOutSize: fullOut,
      )!;

      expect(r.dst.left, closeTo(100, 0.001));
      expect(r.dst.top, closeTo(0, 0.001));
      expect(r.dst.right, closeTo(800, 0.001)); // clamp
      expect(r.dst.bottom, closeTo(600, 0.001)); // clamp
    });

    test('完全缩出（空交集）：返回 null', () {
      // 平移极远，可见区域完全落在 displaySize 之外
      final far = Matrix4.identity()
        ..translateByDouble(-10000.0, -10000.0, 0.0, 1.0);
      final r = computeTileRects(
        viewportTransform: far,
        viewportSize: viewport,
        displaySize: display,
        fullOutSize: fullOut,
      );
      expect(r, isNull);
    });

    test('不可逆矩阵：返回 null', () {
      final r = computeTileRects(
        viewportTransform: Matrix4.zero(),
        viewportSize: viewport,
        displaySize: display,
        fullOutSize: fullOut,
      );
      expect(r, isNull);
    });
  });
}
