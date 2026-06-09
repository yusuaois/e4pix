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
  watermark,
  info,
}

final developToolProvider = StateProvider<DevelopTool>(
  (ref) => DevelopTool.light,
);
