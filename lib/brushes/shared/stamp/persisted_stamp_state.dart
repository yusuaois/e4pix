import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stamp_mark.dart';

/// 跨实例持久化的已提交 stamp 预览状态
///
/// 源-目标型画笔（图章、修复画笔）在工具切换时 widget 被卸载，
/// 但管线尚未完成渲染——committed preview 需在下一次挂载时恢复
/// 此 provider 统一管理持久化
@immutable
class PersistedStampState {
  final List<StampMark> marks;
  final int hash;
  final bool isCommitting;

  /// 哪个画笔拥有此持久化状态（'spot_removal' 或 'healing'）
  final String? brushId;

  const PersistedStampState({
    this.marks = const [],
    this.hash = 0,
    this.isCommitting = false,
    this.brushId,
  });
}

class PersistedStampNotifier extends Notifier<PersistedStampState> {
  @override
  PersistedStampState build() => const PersistedStampState();

  void persist(String brushId, List<StampMark> marks, int hash) {
    state = PersistedStampState(
      marks: marks,
      hash: hash,
      isCommitting: true,
      brushId: brushId,
    );
  }

  void clear() {
    state = const PersistedStampState();
  }
}

final persistedStampProvider =
    NotifierProvider<PersistedStampNotifier, PersistedStampState>(
      PersistedStampNotifier.new,
    );

/// 检查指定画笔是否有待渲染的 committed preview
bool hasPendingStampPreview(WidgetRef ref, String brushId) {
  final p = ref.watch(persistedStampProvider);
  return p.isCommitting && p.brushId == brushId && p.marks.isNotEmpty;
}
