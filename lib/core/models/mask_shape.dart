import 'dart:ui';

import 'package:flutter/foundation.dart';

sealed class MaskShape {
  const MaskShape();

  Map<String, dynamic> toJson();

  static MaskShape fromJson(Map<String, dynamic> j) {
    final type = j['type'] as String;
    switch (type) {
      case 'linear':
        return LinearGradientMask.fromJson(j);
      case 'radial':
        return RadialGradientMask.fromJson(j);
      case 'brush':
        return BrushMask.fromJson(j);
      default:
        throw FormatException('Unknown mask type: $type');
    }
  }
}

@immutable
class LinearGradientMask extends MaskShape {
  /// 起点 归一化 [0..1]
  final double startX;
  final double startY;
  final double endX;
  final double endY;

  const LinearGradientMask({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
  });

  static const defaultTopToBottom = LinearGradientMask(
    startX: 0.5,
    startY: 0.0,
    endX: 0.5,
    endY: 0.5,
  );

  LinearGradientMask copyWith({
    double? startX,
    double? startY,
    double? endX,
    double? endY,
  }) => LinearGradientMask(
    startX: startX ?? this.startX,
    startY: startY ?? this.startY,
    endX: endX ?? this.endX,
    endY: endY ?? this.endY,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'linear',
    'startX': startX,
    'startY': startY,
    'endX': endX,
    'endY': endY,
  };

  factory LinearGradientMask.fromJson(Map<String, dynamic> j) =>
      LinearGradientMask(
        startX: (j['startX'] as num).toDouble(),
        startY: (j['startY'] as num).toDouble(),
        endX: (j['endX'] as num).toDouble(),
        endY: (j['endY'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinearGradientMask &&
          startX == other.startX &&
          startY == other.startY &&
          endX == other.endX &&
          endY == other.endY);

  @override
  int get hashCode => Object.hash(startX, startY, endX, endY);
}

@immutable
class RadialGradientMask extends MaskShape {
  final double centerX;
  final double centerY;
  final double radiusX; // 在 x 轴方向的半径 [0..1]
  final double radiusY;
  final double rotation; // 弧度
  final double feather; // [0..1]，软化程度，0=硬边，1=最软
  final bool inverted; // true: mask 是椭圆外部

  const RadialGradientMask({
    required this.centerX,
    required this.centerY,
    required this.radiusX,
    required this.radiusY,
    this.rotation = 0.0,
    this.feather = 0.5,
    this.inverted = false,
  });

  static const defaultCircle = RadialGradientMask(
    centerX: 0.5,
    centerY: 0.5,
    radiusX: 0.25,
    radiusY: 0.25,
  );

  RadialGradientMask copyWith({
    double? centerX,
    double? centerY,
    double? radiusX,
    double? radiusY,
    double? rotation,
    double? feather,
    bool? inverted,
  }) => RadialGradientMask(
    centerX: centerX ?? this.centerX,
    centerY: centerY ?? this.centerY,
    radiusX: radiusX ?? this.radiusX,
    radiusY: radiusY ?? this.radiusY,
    rotation: rotation ?? this.rotation,
    feather: feather ?? this.feather,
    inverted: inverted ?? this.inverted,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'radial',
    'centerX': centerX,
    'centerY': centerY,
    'radiusX': radiusX,
    'radiusY': radiusY,
    'rotation': rotation,
    'feather': feather,
    'inverted': inverted,
  };

  factory RadialGradientMask.fromJson(Map<String, dynamic> j) =>
      RadialGradientMask(
        centerX: (j['centerX'] as num).toDouble(),
        centerY: (j['centerY'] as num).toDouble(),
        radiusX: (j['radiusX'] as num).toDouble(),
        radiusY: (j['radiusY'] as num).toDouble(),
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
        feather: (j['feather'] as num?)?.toDouble() ?? 0.5,
        inverted: j['inverted'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RadialGradientMask &&
          centerX == other.centerX &&
          centerY == other.centerY &&
          radiusX == other.radiusX &&
          radiusY == other.radiusY &&
          rotation == other.rotation &&
          feather == other.feather &&
          inverted == other.inverted);

  @override
  int get hashCode => Object.hash(
    centerX,
    centerY,
    radiusX,
    radiusY,
    rotation,
    feather,
    inverted,
  );
}

@immutable
class BrushStroke {
  final List<Offset> points; // 归一化 [0..1]，相对裁剪后输出
  final double radius; // 归一化（相对宽度）
  final double hardness; // 0..1，1=硬边
  final double flow; // 流量 0..1，每笔沉积量
  final bool erase; // true=擦除
  final bool autoMask; // 自动蒙版（边缘吸附）
  final double tolerance; // 颜色容差 0..1，越大吸附范围越宽
  final double edgeStrength; // 边缘强度 0..1（导向滤波贴边强度）

  const BrushStroke({
    required this.points,
    required this.radius,
    this.hardness = 0.8,
    this.flow = 1.0,
    this.erase = false,
    this.autoMask = false,
    this.tolerance = 0.15,
    this.edgeStrength = 0.6,
  });

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    'radius': radius,
    'hardness': hardness,
    'flow': flow,
    'erase': erase,
    'autoMask': autoMask,
    'tolerance': tolerance,
    'edgeStrength': edgeStrength,
  };

  factory BrushStroke.fromJson(Map<String, dynamic> j) => BrushStroke(
    points: (j['points'] as List).map((e) {
      final l = e as List;
      return Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
    }).toList(),
    radius: (j['radius'] as num).toDouble(),
    hardness: (j['hardness'] as num?)?.toDouble() ?? 0.8,
    flow: (j['flow'] as num?)?.toDouble() ?? 1.0,
    erase: j['erase'] as bool? ?? false,
    autoMask: j['autoMask'] as bool? ?? false,
    tolerance: (j['tolerance'] as num?)?.toDouble() ?? 0.15,
    edgeStrength: (j['edgeStrength'] as num?)?.toDouble() ?? 0.6,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BrushStroke &&
          radius == other.radius &&
          hardness == other.hardness &&
          flow == other.flow &&
          erase == other.erase &&
          autoMask == other.autoMask &&
          tolerance == other.tolerance &&
          edgeStrength == other.edgeStrength &&
          listEquals(points, other.points));

  @override
  int get hashCode => Object.hash(
    radius,
    hardness,
    flow,
    erase,
    autoMask,
    tolerance,
    edgeStrength,
    Object.hashAll(points),
  );
}

@immutable
class BrushMask extends MaskShape {
  final List<BrushStroke> strokes;

  const BrushMask({this.strokes = const []});

  BrushMask copyWith({List<BrushStroke>? strokes}) =>
      BrushMask(strokes: strokes ?? this.strokes);

  BrushMask addStroke(BrushStroke s) => BrushMask(strokes: [...strokes, s]);

  bool get isEmpty => strokes.isEmpty;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'brush',
    'strokes': strokes.map((s) => s.toJson()).toList(),
  };

  factory BrushMask.fromJson(Map<String, dynamic> j) => BrushMask(
    strokes:
        (j['strokes'] as List?)
            ?.map(
              (e) => BrushStroke.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList() ??
        const [],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BrushMask && listEquals(strokes, other.strokes));

  @override
  int get hashCode => Object.hashAll(strokes);
}
