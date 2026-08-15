import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:e4pix/core/models/crop_params.dart';
import 'package:e4pix/render/crop_transform.dart';

void main() {
  group('cropOutputSize', () {
    test('identity crop → 输出 = 源尺寸', () {
      final s = cropOutputSize(CropParams.identity, 4000, 3000);
      expect(s, const Size(4000, 3000));
    });

    test('orientation=1 轴交换 → 尺寸对调', () {
      final s = cropOutputSize(
        const CropParams(orientation: 1, width: 0.5, height: 0.5),
        4000,
        3000,
      );
      // orientedW=3000, orientedH=4000 → (1500, 2000)
      expect(s, const Size(1500, 2000));
    });

    test('非整除尺寸 round', () {
      final s = cropOutputSize(
        const CropParams(width: 0.7, height: 0.7),
        4001,
        3001,
      );
      // 0.7*4001 = 2800.7 → 2801 ; 0.7*3001 = 2100.7 → 2101
      expect(s, const Size(2801, 2101));
    });

    test('x/y/straighten/flip 不影响输出尺寸', () {
      final s = cropOutputSize(
        const CropParams(
          x: 0.1,
          y: 0.2,
          width: 0.5,
          height: 0.5,
          straighten: 10.0,
          flipH: true,
          flipV: true,
        ),
        4000,
        3000,
      );
      expect(s, const Size(2000, 1500));
    });
  });
}
