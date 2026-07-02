import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// GPU 纹理生命周期管理 mixin
///
/// 用于 [Notifier<ui.Image?>] 子类，提供"延迟一帧 dispose 旧纹理"的标准实现，
/// 避免 GPU 并发冲突（旧纹理可能仍在当前帧被 overlay 或其他组件读取）
///
/// 用法：
/// ```dart
/// class MyNotifier extends Notifier<ui.Image?> with TextureNotifier {
///   @override
///   ui.Image? build() => null;
///
///   void onNewImage(ui.Image? img) => updateTexture(img);
/// }
/// ```
///
/// 注意：如果 Notifier 涉及异步操作（如 async bake），调用方需自行处理
/// [_disposed] 守卫逻辑,参见 [CurveTextureNotifier] 的实现
mixin TextureNotifier on Notifier<ui.Image?> {
  /// 更新纹理并自动管理旧纹理的延迟 dispose
  ///
  /// 将 [newImage] 设为当前状态，旧纹理通过 [SchedulerBinding.addPostFrameCallback]
  /// 延迟一帧释放，确保 GPU 不再引用它
  void updateTexture(ui.Image? newImage) {
    final old = state;
    state = newImage;
    if (old != null && old != newImage) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        try {
          old.dispose();
        } catch (_) {}
      });
    }
  }
}
