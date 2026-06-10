import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 取色读数：某点的 RGB（0-255）
@immutable
class PickedColor {
  final int r, g, b;
  final double nx, ny; // 归一化位置（用于浮层定位参考）
  const PickedColor(this.r, this.g, this.b, this.nx, this.ny);

  int get luma => ((r * 299 + g * 587 + b * 114) / 1000).round(); // Rec.601
  String get hex =>
      '#${r.toRadixString(16).padLeft(2, '0')}'
              '${g.toRadixString(16).padLeft(2, '0')}'
              '${b.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();
}

/// 取色模式开关
class ColorPickerModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void set(bool v) => state = v;
}

final colorPickerModeProvider = NotifierProvider<ColorPickerModeNotifier, bool>(
  ColorPickerModeNotifier.new,
);

/// 当前读数
class PickedColorNotifier extends Notifier<PickedColor?> {
  @override
  PickedColor? build() => null;
  void set(PickedColor? c) => state = c;
}

final pickedColorProvider = NotifierProvider<PickedColorNotifier, PickedColor?>(
  PickedColorNotifier.new,
);
