import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:e4pix/render/hi_res/hi_res_pyramid.dart';

void main() {
  group('pyramidLevelCount', () {
    test('4000×3000 → 4 级（L0..L3）', () {
      expect(pyramidLevelCount(const Size(4000, 3000)), 4);
    });

    test('512×512 → 2 级（L0=512, L1=256）', () {
      expect(pyramidLevelCount(const Size(512, 512)), 2);
    });

    test('小于最小边长的图 → 仅 1 级', () {
      expect(pyramidLevelCount(const Size(200, 100)), 1);
    });
  });

  group('selectPyramidLevel', () {
    // 统一场景：full 4000×3000，display 800×600（scale 5x 到真实像素）
    const full = Size(4000, 3000);
    const display = Size(800, 600);

    test('低 zoom 1.5x（dpr1）→ L1（½ 足够清晰）', () {
      final k = selectPyramidLevel(
        zoom: 1.5,
        devicePixelRatio: 1.0,
        displaySize: display,
        fullOutSize: full,
      );
      expect(k, 1);
    });

    test('中 zoom 3x（dpr1）→ L0（需接近全分辨率）', () {
      final k = selectPyramidLevel(
        zoom: 3.0,
        devicePixelRatio: 1.0,
        displaySize: display,
        fullOutSize: full,
      );
      expect(k, 0);
    });

    test('zoom 2.0（dpr1）→ L1（1:1 阈值下无需全尺寸）', () {
      final k = selectPyramidLevel(
        zoom: 2.0,
        devicePixelRatio: 1.0,
        displaySize: display,
        fullOutSize: full,
      );
      expect(k, 1);
    });

    test('100% zoom 5x → L0（真实像素）', () {
      final k = selectPyramidLevel(
        zoom: 5.0,
        devicePixelRatio: 1.0,
        displaySize: display,
        fullOutSize: full,
      );
      expect(k, 0);
    });

    test('高 dpr（视网膜）→ 更倾向高分辨率 L0', () {
      final k = selectPyramidLevel(
        zoom: 1.5,
        devicePixelRatio: 2.0,
        displaySize: display,
        fullOutSize: full,
      );
      expect(k, 0);
    });

    test('小图 2000×1500 在 1.5x → L0（半尺寸仍不够）', () {
      final k = selectPyramidLevel(
        zoom: 1.5,
        devicePixelRatio: 1.0,
        displaySize: display,
        fullOutSize: const Size(2000, 1500),
      );
      expect(k, 0);
    });

    test('结果不超过最大层级', () {
      final k = selectPyramidLevel(
        zoom: 1.0,
        devicePixelRatio: 1.0,
        displaySize: display,
        fullOutSize: full,
      );
      expect(k, inInclusiveRange(0, pyramidLevelCount(full) - 1));
    });
  });
}
