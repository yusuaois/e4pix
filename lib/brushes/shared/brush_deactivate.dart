import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brush_manifest.dart';
import '../../state/providers.dart';

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
