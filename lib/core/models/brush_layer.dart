import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// 一个画笔图层的渲染结果。
///
/// [texture] 为全分辨率 RGBA 纹理，alpha 通道编码贡献遮罩：
/// 1.0 = 该像素被画笔修改，0.0 = 透过底层。
@immutable
class BrushLayer {
  final String id;
  final ui.Image? texture;
  final bool active;

  const BrushLayer({
    required this.id,
    this.texture,
    this.active = false,
  });
}
