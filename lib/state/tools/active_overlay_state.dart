import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/develop/sections/light/curve_micro_bar.dart';
import '../../widgets/develop/sections/light/curve_overlay.dart';

/// 当前活跃的浮层 / 覆盖模式
///
/// 每个子类通过 [buildOverlay]、[buildMicroBar] 注入 UI，
/// 调用方无需判断具体子类
///
/// 未来新增覆盖模式只需加一个新的 [ActiveOverlay] 子类
sealed class ActiveOverlay {
  const ActiveOverlay();

  /// 预览区域上方的浮层 widget，null 表示不渲染
  Widget? buildOverlay(BuildContext context) => null;

  /// 底部微缩栏 widget，null 表示使用默认 TabBar
  Widget? buildMicroBar(BuildContext context, VoidCallback onDone) => null;
}

/// 无活跃覆盖——正常 UI 模式
class NoActiveOverlay extends ActiveOverlay {
  const NoActiveOverlay();
}

/// 曲线编辑浮层：预览区上方半透明网格 + 底部微缩栏
class CurveActiveOverlay extends ActiveOverlay {
  /// 当前编辑的通道 (0=RGB, 1=R, 2=G, 3=B, 4=明度)
  final int channel;

  const CurveActiveOverlay({this.channel = 0});

  @override
  Widget buildOverlay(BuildContext context) =>
      const Positioned.fill(child: CurveOverlay());

  @override
  Widget buildMicroBar(BuildContext context, VoidCallback onDone) =>
      CurveMicroBar(onDone: onDone);
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ActiveOverlayNotifier extends Notifier<ActiveOverlay> {
  @override
  ActiveOverlay build() => const NoActiveOverlay();

  void open(ActiveOverlay overlay) => state = overlay;
  void close() => state = const NoActiveOverlay();

  /// 仅在当前为 [CurveActiveOverlay] 时切换通道
  void setChannel(int ch) {
    if (state is CurveActiveOverlay) {
      state = CurveActiveOverlay(channel: ch);
    }
  }
}

final activeOverlayProvider =
    NotifierProvider<ActiveOverlayNotifier, ActiveOverlay>(
  ActiveOverlayNotifier.new,
);
