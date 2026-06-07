import 'package:flutter_riverpod/legacy.dart';

/// 用户是否正在拖滑块
final isUserDraggingSliderProvider = StateProvider<bool>((ref) => false);

/// 全屏预览模式开关
final fullscreenPreviewProvider = StateProvider<bool>((ref) => false);

/// 对分屏对比模式
enum CompareViewMode { off, hold, split }

final compareViewModeProvider = StateProvider<CompareViewMode>((ref) => CompareViewMode.off);

/// 分屏分隔线位置（0.0=最左，1.0=最右）
final splitDividerProvider = StateProvider<double>((ref) => 0.5);