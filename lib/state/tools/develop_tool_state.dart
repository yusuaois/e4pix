import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 右侧工具栏当前选中的功能页
enum DevelopTool {
  light,
  color,
  curve,
  hsl,
  lut,
  detail,
  preset,
  local,
  spotRemove,
  healing,
  spotHeal,
  dodgeBurn,
  sponge,
  historyBrush,
  watermark,
  lens,
  sr,
  info,
}

class DevelopToolNotifier extends Notifier<DevelopTool> {
  @override
  DevelopTool build() => DevelopTool.light;
  void set(DevelopTool v) => state = v;
}

final developToolProvider = NotifierProvider<DevelopToolNotifier, DevelopTool>(
  DevelopToolNotifier.new,
);
