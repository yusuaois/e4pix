import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// 用户是否正在拖滑块。所有 develop / hsl / local / lut 的 Slider 都会更新它。
/// MultiPassPreview / LiveHistogramPanel 监听它来降级渲染。
final isUserDraggingSliderProvider = StateProvider<bool>((ref) => false);