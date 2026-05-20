import 'package:flutter_riverpod/legacy.dart';

/// 笔刷半径（归一化，相对输出宽度）
final brushRadiusProvider = StateProvider<double>((ref) => 0.08);

/// 笔刷硬度 0..1（1=硬边，0=最柔）
final brushHardnessProvider = StateProvider<double>((ref) => 0.7);

/// 加(false) / 擦(true)
final brushEraseProvider = StateProvider<bool>((ref) => false);