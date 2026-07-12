import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brush_manifest.dart';

/// 切换工具时停用画笔，通过 manifest 泛型分发
void deactivateBrush(String brushId, WidgetRef ref) {
  final m = manifestForId(brushId);
  m?.deactivate(ref);
}
