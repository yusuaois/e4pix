import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/crop_params.dart';
import '../state/crop_state.dart';
import '../state/image_state.dart';

class CropPanel extends ConsumerWidget {
  const CropPanel({super.key});

  static const _aspects = <(String, double?)>[
    ('Free', null),
    ('1:1', 1.0),
    ('3:2', 3 / 2),
    ('4:3', 4 / 3),
    ('5:4', 5 / 4),
    ('16:9', 16 / 9),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageState = ref.watch(imageNotifierProvider).value;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC0B0B10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in _aspects) ...[
            _AspectChip(
              label: entry.$1,
              targetAspect: entry.$2,
              imageWidth: imageState?.uiImage.width.toDouble() ?? 0,
              imageHeight: imageState?.uiImage.height.toDouble() ?? 0,
            ),
            const SizedBox(width: 4),
          ],
          const VerticalDivider(width: 14, color: Colors.white24),
          TextButton(
            onPressed: () => ref
                .read(cropDraftProvider.notifier)
                .update(CropParams.identity),
            child: const Text('Reset', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => cancelCrop(ref),
            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
          ),
          FilledButton(
            onPressed: () => commitCrop(ref),
            style: FilledButton.styleFrom(
              minimumSize: const Size(60, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Apply', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _AspectChip extends ConsumerWidget {
  final String label;
  final double? targetAspect;
  final double imageWidth;
  final double imageHeight;
  const _AspectChip({
    required this.label,
    required this.targetAspect,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _apply(ref),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  void _apply(WidgetRef ref) {
    if (targetAspect == null) {
      // Free
      return;
    }
    if (imageWidth <= 0 || imageHeight <= 0) return;

    // 在源图像的物理坐标里，找一个最大的、纵横比为 targetAspect、围绕中心的矩形
    final imgAspect = imageWidth / imageHeight;
    double w, h;
    if (targetAspect! >= imgAspect) {
      // 目标更宽 → 限制为宽 = 1.0，按比例算高
      w = 1.0;
      h = (imgAspect / targetAspect!);
    } else {
      h = 1.0;
      w = (targetAspect! / imgAspect);
    }
    final cx = 0.5, cy = 0.5;
    ref
        .read(cropDraftProvider.notifier)
        .update(CropParams(x: cx - w / 2, y: cy - h / 2, width: w, height: h));
  }
}
