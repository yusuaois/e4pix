import 'package:flutter_riverpod/legacy.dart';

/// 笔刷半径（归一化，相对输出宽度）
final brushRadiusProvider = StateProvider<double>((ref) => 0.08);

/// 笔刷硬度 0..1（1=硬边，0=最柔）
final brushHardnessProvider = StateProvider<double>((ref) => 0.7);

/// 笔刷流量 0..1（每笔沉积量，重复涂抹累积）
final brushFlowProvider = StateProvider<double>((ref) => 1.0);

/// 加(false) / 擦(true)
final brushEraseProvider = StateProvider<bool>((ref) => false);

/// 自动蒙版（边缘吸附）开关
final brushAutoMaskProvider = StateProvider<bool>((ref) => false);

/// 自动蒙版颜色容差 0..1（越大吸附范围越宽）
final brushToleranceProvider = StateProvider<double>((ref) => 0.15);
