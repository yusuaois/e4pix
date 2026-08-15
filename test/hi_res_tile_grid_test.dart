import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:e4pix/render/hi_res/hi_res_tile_grid.dart';

void main() {
  group('computeGridTiles', () {
    test('整图可见：1024 图切 512 网格 → 2×2 四块，dst 按 0.5 缩放', () {
      const full = Size(1024, 1024);
      const display = Size(512, 512);
      final tiles = computeGridTiles(
        visibleSrc: const Rect.fromLTWH(0, 0, 1024, 1024),
        fullOutSize: full,
        displaySize: display,
        tileEdge: 512,
      );

      expect(tiles.length, 4);
      final ids = tiles.map((t) => t.id).toSet();
      expect(
        ids,
        containsAll([
          const HiResTileId(col: 0, row: 0),
          const HiResTileId(col: 1, row: 0),
          const HiResTileId(col: 0, row: 1),
          const HiResTileId(col: 1, row: 1),
        ]),
      );

      final tl = tiles.firstWhere(
        (t) => t.id == const HiResTileId(col: 0, row: 0),
      );
      expect(tl.src.left, closeTo(0, 0.001));
      expect(tl.src.top, closeTo(0, 0.001));
      expect(tl.src.width, closeTo(512, 0.001));
      expect(tl.src.height, closeTo(512, 0.001));
      expect(tl.dst.left, closeTo(0, 0.001));
      expect(tl.dst.top, closeTo(0, 0.001));
      expect(tl.dst.width, closeTo(256, 0.001));
      expect(tl.dst.height, closeTo(256, 0.001));
    });

    test('可见区域跨四格：返回完整整数网格单元，src 不裁剪、dst 严格连续', () {
      const full = Size(1024, 1024);
      const display = Size(512, 512);
      final tiles = computeGridTiles(
        visibleSrc: const Rect.fromLTWH(
          256,
          256,
          512,
          512,
        ), // (256,256)-(768,768)
        fullOutSize: full,
        displaySize: display,
        tileEdge: 512,
      );

      expect(tiles.length, 4);
      final tl = tiles.firstWhere(
        (t) => t.id == const HiResTileId(col: 0, row: 0),
      );
      // 关键：src 是完整整数单元，而非可见区交集
      expect(tl.src.left, closeTo(0, 0.001));
      expect(tl.src.top, closeTo(0, 0.001));
      expect(tl.src.right, closeTo(512, 0.001));
      expect(tl.src.bottom, closeTo(512, 0.001));
      expect(tl.dst.left, closeTo(0, 0.001));
      expect(tl.dst.top, closeTo(0, 0.001));
      expect(tl.dst.right, closeTo(256, 0.001));
      expect(tl.dst.bottom, closeTo(256, 0.001));

      // 相邻瓦片 dst 边界严格连续（无缝隙/重叠）
      final tr = tiles.firstWhere(
        (t) => t.id == const HiResTileId(col: 1, row: 0),
      );
      expect(tl.dst.right, closeTo(tr.dst.left, 1e-9));
      final bl = tiles.firstWhere(
        (t) => t.id == const HiResTileId(col: 0, row: 1),
      );
      expect(tl.dst.bottom, closeTo(bl.dst.top, 1e-9));
    });

    test('非整除：1000 图切 512 网格，末列/末行 488 宽', () {
      const full = Size(1000, 1000);
      final tiles = computeGridTiles(
        visibleSrc: const Rect.fromLTWH(0, 0, 1000, 1000),
        fullOutSize: full,
        displaySize: const Size(1000, 1000),
        tileEdge: 512,
      );

      expect(tiles.length, 4);
      final br = tiles.firstWhere(
        (t) => t.id == const HiResTileId(col: 1, row: 1),
      );
      expect(br.src.left, closeTo(512, 0.001));
      expect(br.src.top, closeTo(512, 0.001));
      expect(br.src.width, closeTo(488, 0.001));
      expect(br.src.height, closeTo(488, 0.001));
    });

    test('小数可见区：src 整数对齐、dst 连续（回归周边形变 bug）', () {
      // 模拟放大后可见区有小数边缘：full 4000×3000, display 800×600, scale=0.2
      const full = Size(4000, 3000);
      const display = Size(800, 600);
      final tiles = computeGridTiles(
        visibleSrc: const Rect.fromLTWH(1234.56, 987.65, 1500, 1200),
        fullOutSize: full,
        displaySize: display,
        tileEdge: 512,
      );

      expect(tiles, isNotEmpty);
      for (final t in tiles) {
        // 每块瓦片 src 必须是整数（像素精确提取的前提）
        expect(t.src.left, closeTo(t.src.left.roundToDouble(), 1e-9));
        expect(t.src.top, closeTo(t.src.top.roundToDouble(), 1e-9));
        expect(t.src.right, closeTo(t.src.right.roundToDouble(), 1e-9));
        expect(t.src.bottom, closeTo(t.src.bottom.roundToDouble(), 1e-9));
        // dst 与 src 严格线性（scale=0.2）
        expect(t.dst.left, closeTo(t.src.left * 0.2, 1e-9));
        expect(t.dst.top, closeTo(t.src.top * 0.2, 1e-9));
      }

      // 同行的相邻瓦片 dst 边界严格连续
      final byId = {for (final t in tiles) t.id: t};
      for (final t in tiles) {
        final right = byId[HiResTileId(col: t.id.col + 1, row: t.id.row)];
        if (right != null) {
          expect(t.dst.right, closeTo(right.dst.left, 1e-9));
        }
      }
    });

    test('可见右边界恰在网格线上：不越界取下一列', () {
      final tiles = computeGridTiles(
        visibleSrc: const Rect.fromLTWH(0, 0, 512, 512),
        fullOutSize: const Size(1024, 1024),
        displaySize: const Size(512, 512),
        tileEdge: 512,
      );

      expect(tiles.length, 1);
      expect(tiles.single.id, const HiResTileId(col: 0, row: 0));
    });

    test('level 参数 tag 到瓦片 id', () {
      final tiles = computeGridTiles(
        visibleSrc: const Rect.fromLTWH(0, 0, 512, 512),
        fullOutSize: const Size(1024, 1024),
        displaySize: const Size(512, 512),
        tileEdge: 512,
        level: 2,
      );
      expect(tiles.single.id, const HiResTileId(level: 2, col: 0, row: 0));
    });

    test('零面积可见区域：返回空', () {
      final tiles = computeGridTiles(
        visibleSrc: const Rect.fromLTWH(10, 10, 0, 0),
        fullOutSize: const Size(1024, 1024),
        displaySize: const Size(512, 512),
        tileEdge: 512,
      );
      expect(tiles, isEmpty);
    });

    test('非法参数（tileEdge<=0 或 full 尺寸<=0）：返回空', () {
      expect(
        computeGridTiles(
          visibleSrc: const Rect.fromLTWH(0, 0, 100, 100),
          fullOutSize: const Size(1024, 1024),
          displaySize: const Size(512, 512),
          tileEdge: 0,
        ),
        isEmpty,
      );
      expect(
        computeGridTiles(
          visibleSrc: const Rect.fromLTWH(0, 0, 100, 100),
          fullOutSize: const Size(0, 0),
          displaySize: const Size(512, 512),
          tileEdge: 512,
        ),
        isEmpty,
      );
    });
  });

  group('HiResTileId', () {
    test('相等性与 hashCode（含 level）', () {
      const a = HiResTileId(level: 1, col: 1, row: 2);
      const b = HiResTileId(level: 1, col: 1, row: 2);
      const c = HiResTileId(level: 0, col: 1, row: 2);
      const d = HiResTileId(level: 1, col: 2, row: 1);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });
  });
}
