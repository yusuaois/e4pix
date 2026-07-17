import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brush_manifest.dart';
import '../../state/providers.dart';

/// 当 develop tool 切换时，自动退出上一个工具的活跃状态
///
/// 遍历 [brushManifests] 检查 [prev] 是否匹配某个画笔，匹配则调用其 [BrushManifest.deactivate]；
/// 同时处理 `DevelopTool.local` 退出
void exitToolOnChange(
  WidgetRef ref, {
  required DevelopTool? prev,
  required DevelopTool next,
}) {
  if (prev == null || prev == next) return;
  if (prev == DevelopTool.local) exitLocalTool(ref);
  for (final m in brushManifests) {
    if (prev == m.tool) deactivateBrush(m.id, ref);
  }
}

/// 切换工具时停用画笔，通过 manifest 泛型分发
void deactivateBrush(String brushId, WidgetRef ref) {
  final m = manifestForId(brushId);
  m?.deactivate(ref);
}

/// 退出本地调整工具：清除选中 ID，重置画笔模式为 paint
void exitLocalTool(WidgetRef ref) {
  ref.read(selectedLocalIdProvider.notifier).set(null);
  final mode = ref.read(brushSettingsProvider).mode;
  if (mode != BrushMode.paint) {
    ref.read(brushSettingsProvider.notifier).setMode(BrushMode.paint);
  }
}
