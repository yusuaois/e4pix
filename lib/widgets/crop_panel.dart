import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/crop_params.dart';
import '../state/crop_state.dart';
import '../state/image_state.dart';

class CropPanel extends ConsumerStatefulWidget {
  const CropPanel({super.key});

  @override
  ConsumerState<CropPanel> createState() => _CropPanelState();
}

class _CropPanelState extends ConsumerState<CropPanel> {
  final ScrollController _scrollController = ScrollController();

  static const _aspects = <(String, double?)>[
    ('Free', null),
    ('1:1', 1.0),
    ('3:2', 3 / 2),
    ('4:3', 4 / 3),
    ('5:4', 5 / 4),
    ('16:9', 16 / 9),
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageState = ref.watch(imageNotifierProvider).value;
    final imgW = imageState?.uiImage.width.toDouble() ?? 0;
    final imgH = imageState?.uiImage.height.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC0B0B10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 左：可横向滑动
          Expanded(
            child: SizedBox(
              height: 30,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.touch,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: Listener(
                  onPointerSignal: (signal) {
                    if (signal is PointerScrollEvent) {
                      final target =
                          _scrollController.offset + signal.scrollDelta.dy;
                      _scrollController.jumpTo(
                        target.clamp(
                          0.0,
                          _scrollController.position.maxScrollExtent,
                        ),
                      );
                    }
                  },
                  child: ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    itemCount: _aspects.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (ctx, i) {
                      final entry = _aspects[i];
                      return _AspectChip(
                        label: entry.$1,
                        targetAspect: entry.$2,
                        imageWidth: imgW,
                        imageHeight: imgH,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 22,
            color: Colors.white24,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          // 右：固定按钮
          TextButton(
            onPressed: () => ref
                .read(cropDraftProvider.notifier)
                .update(CropParams.identity),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(tr("reset"), style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => cancelCrop(ref),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(tr("cancel"), style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () => commitCrop(ref),
            style: FilledButton.styleFrom(
              minimumSize: const Size(54, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(tr("apply"), style: TextStyle(fontSize: 12)),
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
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  void _apply(WidgetRef ref) {
    if (targetAspect == null) return;
    if (imageWidth <= 0 || imageHeight <= 0) return;

    final imgAspect = imageWidth / imageHeight;
    double w, h;
    if (targetAspect! >= imgAspect) {
      w = 1.0;
      h = imgAspect / targetAspect!;
    } else {
      h = 1.0;
      w = targetAspect! / imgAspect;
    }
    ref
        .read(cropDraftProvider.notifier)
        .update(
          CropParams(x: 0.5 - w / 2, y: 0.5 - h / 2, width: w, height: h),
        );
  }
}
