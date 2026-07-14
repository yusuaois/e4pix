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

/// 当前画面缩放比例（InteractiveViewer）
///
/// 画笔光标绘制时需要除以该值，抵消 InteractiveViewer 的缩放，保持屏幕像素固定大小
class ZoomScaleNotifier extends Notifier<double> {
  @override
  double build() => 1.0;
  void set(double v) => state = v;
}

final zoomScaleProvider = NotifierProvider<ZoomScaleNotifier, double>(
  ZoomScaleNotifier.new,
);
