import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 画笔模式：手绘 / 智能区域(颜色) / 主体(模型分割)
enum BrushMode { paint, wand, subject }

@immutable
class BrushSettings {
  // ── 画笔参数 ──
  final double radius; // 归一化半径，默认 0.03
  final double hardness; // 0..1，默认 0.7
  final double flow; // 0..1，默认 1.0
  final bool erase; // 加/擦
  final bool autoMask; // 边缘吸附开关
  final double tolerance; // 自动蒙版颜色容差 0..1
  final double edgeStrength; // 导向滤波贴边强度 0..1
  final BrushMode mode; // paint / wand / subject

  // ── 智能区域(wand)参数 ──
  final double wandTolerance; // 0..1，默认 0.08
  final bool wandInvert; // 反选（选背景）

  // ── 瞬态 UI 标志 ──
  final bool wandBusy; // 智能区域计算中
  final bool samBusy; // 主体分割计算中
  final bool samUnavailable; // 模型不可用
  final bool samNegative; // 当前落点为排除点

  const BrushSettings({
    this.radius = 0.03,
    this.hardness = 0.7,
    this.flow = 1.0,
    this.erase = false,
    this.autoMask = false,
    this.tolerance = 0.15,
    this.edgeStrength = 0.6,
    this.mode = BrushMode.paint,
    this.wandTolerance = 0.08,
    this.wandInvert = false,
    this.wandBusy = false,
    this.samBusy = false,
    this.samUnavailable = false,
    this.samNegative = false,
  });

  static const neutral = BrushSettings();

  BrushSettings copyWith({
    double? radius,
    double? hardness,
    double? flow,
    bool? erase,
    bool? autoMask,
    double? tolerance,
    double? edgeStrength,
    BrushMode? mode,
    double? wandTolerance,
    bool? wandInvert,
    bool? wandBusy,
    bool? samBusy,
    bool? samUnavailable,
    bool? samNegative,
  }) => BrushSettings(
    radius: radius ?? this.radius,
    hardness: hardness ?? this.hardness,
    flow: flow ?? this.flow,
    erase: erase ?? this.erase,
    autoMask: autoMask ?? this.autoMask,
    tolerance: tolerance ?? this.tolerance,
    edgeStrength: edgeStrength ?? this.edgeStrength,
    mode: mode ?? this.mode,
    wandTolerance: wandTolerance ?? this.wandTolerance,
    wandInvert: wandInvert ?? this.wandInvert,
    wandBusy: wandBusy ?? this.wandBusy,
    samBusy: samBusy ?? this.samBusy,
    samUnavailable: samUnavailable ?? this.samUnavailable,
    samNegative: samNegative ?? this.samNegative,
  );
}

class BrushSettingsNotifier extends Notifier<BrushSettings> {
  @override
  BrushSettings build() => BrushSettings.neutral;

  void setRadius(double v) => state = state.copyWith(radius: v);
  void setHardness(double v) => state = state.copyWith(hardness: v);
  void setFlow(double v) => state = state.copyWith(flow: v);
  void setErase(bool v) => state = state.copyWith(erase: v);
  void setAutoMask(bool v) => state = state.copyWith(autoMask: v);
  void setTolerance(double v) => state = state.copyWith(tolerance: v);
  void setEdgeStrength(double v) => state = state.copyWith(edgeStrength: v);
  void setMode(BrushMode v) => state = state.copyWith(mode: v);
  void setWandTolerance(double v) => state = state.copyWith(wandTolerance: v);
  void setWandInvert(bool v) => state = state.copyWith(wandInvert: v);
  void setWandBusy(bool v) => state = state.copyWith(wandBusy: v);
  void setSamBusy(bool v) => state = state.copyWith(samBusy: v);
  void setSamUnavailable(bool v) => state = state.copyWith(samUnavailable: v);
  void setSamNegative(bool v) => state = state.copyWith(samNegative: v);
}

final brushSettingsProvider =
    NotifierProvider<BrushSettingsNotifier, BrushSettings>(
      BrushSettingsNotifier.new,
    );
