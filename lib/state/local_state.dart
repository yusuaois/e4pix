import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/models/local_adjustment.dart';
import '../core/models/mask_shape.dart';
import 'params_state.dart';

/// 当前正在编辑的 LocalAdjustment 的 id；null 表示在编辑全局
final selectedLocalIdProvider = StateProvider<String?>((ref) => null);

/// 当前选中的 local
final selectedLocalProvider = Provider<LocalAdjustment?>((ref) {
  final id = ref.watch(selectedLocalIdProvider);
  if (id == null) return null;
  final all = ref.watch(currentParamsNotifierProvider).locals;
  for (final l in all) {
    if (l.id == id) return l;
  }
  return null;
});

class LocalAdjustmentActions {
  final WidgetRef ref;
  LocalAdjustmentActions(this.ref);

  static const int maxLocals = 4;

  String _newId() => 'm_${DateTime.now().millisecondsSinceEpoch}';

  bool _full() =>
      ref.read(currentParamsNotifierProvider).locals.length >= maxLocals;

  /// 添加一个 LinearGradient mask；返回新 id（如果已满返回 null）
  String? addLinear() {
    if (_full()) return null;
    final id = _newId();
    final cur = ref.read(currentParamsNotifierProvider);
    final next = cur.copyWith(
      locals: [
        ...cur.locals,
        LocalAdjustment(
          id: id,
          name: '渐变 ${cur.locals.length + 1}',
          mask: LinearGradientMask.defaultTopToBottom,
        ),
      ],
    );
    ref.read(currentParamsNotifierProvider.notifier).update(next);
    ref.read(selectedLocalIdProvider.notifier).state = id;
    return id;
  }

  /// 添加一个 RadialGradient mask
  String? addRadial() {
    if (_full()) return null;
    final id = _newId();
    final cur = ref.read(currentParamsNotifierProvider);
    final next = cur.copyWith(
      locals: [
        ...cur.locals,
        LocalAdjustment(
          id: id,
          name: '径向 ${cur.locals.length + 1}',
          mask: RadialGradientMask.defaultCircle,
        ),
      ],
    );
    ref.read(currentParamsNotifierProvider.notifier).update(next);
    ref.read(selectedLocalIdProvider.notifier).state = id;
    return id;
  }

  /// 添加一个空的画笔 mask
  String? addBrush() {
    if (_full()) return null;
    final id = _newId();
    final cur = ref.read(currentParamsNotifierProvider);
    final next = cur.copyWith(
      locals: [
        ...cur.locals,
        LocalAdjustment(
          id: id,
          name: '画笔 ${cur.locals.length + 1}',
          mask: const BrushMask(),
        ),
      ],
    );
    ref.read(currentParamsNotifierProvider.notifier).update(next);
    ref.read(selectedLocalIdProvider.notifier).state = id;
    return id;
  }

  /// 给指定画笔 mask 追加一笔（UI 涂抹时调用）
  void addStrokeTo(String id, BrushStroke stroke) {
    updateLocal(id, (l) {
      final m = l.mask;
      if (m is! BrushMask) return l;
      return l.copyWith(mask: m.addStroke(stroke));
    });
  }

  /// 更新指定 id 的局部（mask 或 params 或开关或名字）
  void updateLocal(String id, LocalAdjustment Function(LocalAdjustment) f) {
    final cur = ref.read(currentParamsNotifierProvider);
    final idx = cur.locals.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    final updated = f(cur.locals[idx]);
    final next = cur.copyWith(
      locals: [
        ...cur.locals.sublist(0, idx),
        updated,
        ...cur.locals.sublist(idx + 1),
      ],
    );
    ref.read(currentParamsNotifierProvider.notifier).update(next);
  }

  /// 删除指定 id
  void deleteLocal(String id) {
    final cur = ref.read(currentParamsNotifierProvider);
    final next = cur.copyWith(
      locals: cur.locals.where((l) => l.id != id).toList(),
    );
    ref.read(currentParamsNotifierProvider.notifier).update(next);
    if (ref.read(selectedLocalIdProvider) == id) {
      ref.read(selectedLocalIdProvider.notifier).state = null;
    }
  }

  /// 取消选中（返回到全局调整面板）
  void deselect() {
    ref.read(selectedLocalIdProvider.notifier).state = null;
  }
}

final localActionsProvider = Provider.family<LocalAdjustmentActions, WidgetRef>(
  (ref, widgetRef) => LocalAdjustmentActions(widgetRef),
);
