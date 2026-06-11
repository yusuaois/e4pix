import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/tethered_shot.dart';
import '../../native/raw_bridge.dart';
import '../../state/providers.dart';
import '../develop/develop_misc_widgets.dart';

/// 显示当前图片的文件名、分辨率、加载状态，以及导入按钮和评分旗标
/// 自动适配手机紧凑布局和桌面宽布局
class ImageInfoBar extends ConsumerWidget {
  final VoidCallback? onImport;

  const ImageInfoBar({super.key, this.onImport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(imageNotifierProvider).value;
    final isLoading = ref.watch(imageNotifierProvider).isLoading;
    final path = ref.watch(activeFilePathProvider);
    final active = ref.watch(activeShotProvider);
    final m = image?.metadata;
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;

    if (isPhone) {
      return _buildPhone(context, ref, image, isLoading, path, m, active);
    } else {
      return _buildDesktop(context, ref, image, isLoading, path, m, active);
    }
  }

  // ── 手机紧凑布局（原 _buildVerticalInfoBar） ──

  Widget _buildPhone(
    BuildContext context,
    WidgetRef ref,
    DecodedImageState? image,
    bool isLoading,
    String? path,
    RawMetadata? m,
    TetheredShot? active,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.panelBg,
        border: Border(
          top: BorderSide(color: AppColors.subtleBorder),
          bottom: BorderSide(color: AppColors.subtleBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m?.summary.isNotEmpty == true
                      ? m!.summary
                      : (path != null
                            ? p.basename(path)
                            : tr('imageNotChosen')),
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (image != null) ...[
                Text(
                  '${image.width}×${image.height}',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.greenAccent.withValues(alpha: 0.8),
                  ),
                ),
                if (image.isPreliminary) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.2,
                      color: Colors.amberAccent.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'HD…',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.amberAccent.withValues(alpha: 0.7),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Platform.isAndroid
                        ? Icons.folder_copy_outlined
                        : Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  tooltip: Platform.isAndroid
                      ? tr("folderImport")
                      : tr("imageChoose"),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: isLoading ? null : onImport,
                ),
              ],
            ],
          ),
          if (image != null)
            RatingFlagBar(
              key: ValueKey('phone_${active?.rating}_${active?.flag}'),
            ),
        ],
      ),
    );
  }

  // ── 桌面宽布局（原 _buildHorizontalInfoBar） ──

  Widget _buildDesktop(
    BuildContext context,
    WidgetRef ref,
    DecodedImageState? image,
    bool isLoading,
    String? path,
    RawMetadata? m,
    TetheredShot? active,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m?.summary.isNotEmpty == true
                ? m!.summary
                : (path != null ? p.basename(path) : tr('imageNotChosen')),
            style: const TextStyle(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (image != null) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${image.width}×${image.height} · '
                    '${image.bitsPerChannel}-bit · '
                    'decode ${image.decodeTime.inMilliseconds}ms · '
                    'convert ${image.convertTime.inMilliseconds}ms',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontFamily: 'monospace',
                      color: Colors.greenAccent.withValues(alpha: 0.75),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (image.isPreliminary) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.2,
                      color: Colors.amberAccent.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 6),
          RatingFlagBar(
            key: ValueKey('desktop_${active?.rating}_${active?.flag}'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : onImport,
              icon: Icon(
                Platform.isAndroid
                    ? Icons.folder_copy_outlined
                    : Icons.folder_open,
                size: 16,
              ),
              label: Text(
                Platform.isAndroid ? tr("folderImport") : tr("imageChoose"),
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
