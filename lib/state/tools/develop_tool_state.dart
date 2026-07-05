import 'package:flutter_riverpod/legacy.dart';

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
  watermark,
  lens,
  sr,
  info,
}

final developToolProvider = StateProvider<DevelopTool>(
  (ref) => DevelopTool.light,
);
