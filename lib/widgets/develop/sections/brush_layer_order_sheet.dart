import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brushes/brush_manifest.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../state/providers.dart';

/// 弹出画笔图层排序弹窗，拖拽即生效
/// [order] 为 compose 数据顺序（index 0 = 底层），弹窗内反转显示（顶部 = 最高层）
Future<void> showBrushLayerOrderSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  // UI 显示反转：顶层在上
  final displayOrder = ref.read(brushLayerOrderProvider).reversed.toList();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.elevatedBg,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _BrushLayerOrderSheet(
      initialOrder: displayOrder,
      onOrderChanged: (displayOrder) {
        // 拖拽即写：反转回 compose 数据顺序
        ref
            .read(brushLayerOrderProvider.notifier)
            .setOrder(displayOrder.reversed.toList());
      },
    ),
  );
}

class _BrushLayerOrderSheet extends StatefulWidget {
  final List<String> initialOrder;
  final void Function(List<String> displayOrder) onOrderChanged;
  const _BrushLayerOrderSheet({
    required this.initialOrder,
    required this.onOrderChanged,
  });

  @override
  State<_BrushLayerOrderSheet> createState() => _BrushLayerOrderSheetState();
}

class _BrushLayerOrderSheetState extends State<_BrushLayerOrderSheet> {
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    _order = List.of(widget.initialOrder);
  }

  bool _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _order.removeAt(oldIndex);
      _order.insert(newIndex, item);
    });
    widget.onOrderChanged(_order);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.7;
    final isLast = _order.length - 1;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              tr('brushLayerOrder'),
              style: AppTypography.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _order.length,
              onReorderItem: _onReorder,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (_, child) => Material(
                    color: Colors.transparent,
                    elevation: 4,
                    shadowColor: Colors.black38,
                    child: child,
                  ),
                  child: child,
                );
              },
              itemBuilder: (_, index) {
                final id = _order[index];
                final manifest = brushManifests.firstWhere((m) => m.id == id);
                // 显示顺序：顶部=最顶层，底部=最底层
                final isTop = index == 0;
                final isBottom = index == isLast;
                String? subtitle;
                if (isTop && isBottom) {
                  subtitle = null;
                } else if (isTop) {
                  subtitle = tr('brushLayerOrderTop');
                } else if (isBottom) {
                  subtitle = tr('brushLayerOrderBottom');
                }

                return _LayerRow(
                  key: ValueKey(id),
                  index: index,
                  icon: manifest.icon,
                  title: tr(manifest.titleKey),
                  subtitle: subtitle,
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              tr('brushLayerOrderHint'),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 单行：拖拽手柄 + 图标 + 标题 + 副标题
class _LayerRow extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final String? subtitle;

  const _LayerRow({
    super.key,
    required this.index,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: AppColors.surfaceBg,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.drag_handle,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              Icon(icon, size: 18, color: AppColors.mediumText),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppTypography.bodyLarge)),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
