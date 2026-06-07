import 'package:flutter_riverpod/legacy.dart';

/// 用户是否正在拖滑块
final isUserDraggingSliderProvider = StateProvider<bool>((ref) => false);

/// 全屏预览模式开关
final fullscreenPreviewProvider = StateProvider<bool>((ref) => false);
