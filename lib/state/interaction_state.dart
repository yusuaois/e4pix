import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用户是否正在拖滑块
class IsUserDraggingSliderNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final isUserDraggingSliderProvider =
    NotifierProvider<IsUserDraggingSliderNotifier, bool>(
      IsUserDraggingSliderNotifier.new,
    );

/// 全屏预览模式开关
class FullscreenPreviewNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final fullscreenPreviewProvider =
    NotifierProvider<FullscreenPreviewNotifier, bool>(
      FullscreenPreviewNotifier.new,
    );
