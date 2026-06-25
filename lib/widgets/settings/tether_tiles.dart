import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/providers.dart';

class TetherFolderTile extends ConsumerWidget {
  final BorderRadius? tileBorderRadius;
  const TetherFolderTile({super.key, this.tileBorderRadius});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(tetherFolderProvider);

    Future<void> pick() async {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: tr("settingsTetherFolderChoose"),
      );
      if (path != null && path.isNotEmpty) {
        await ref.read(tetherFolderProvider.notifier).set(path);
      }
    }

    return ListTile(
      shape: tileBorderRadius != null
          ? RoundedRectangleBorder(borderRadius: tileBorderRadius!)
          : null,
      leading: const Icon(Icons.folder_outlined, size: 20),
      title: Text(tr("settingsTetherFolder"), style: AppTypography.titleMedium),
      subtitle: Text(
        folder ?? tr("settingsTetherFolderNone"),
        style: AppTypography.bodySmall.copyWith(
          fontFamily: folder != null ? 'monospace' : null,
          color: folder == null ? AppColors.disabledText : AppColors.mediumText,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (folder != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: tr("settingsTetherFolderClear"),
              visualDensity: VisualDensity.compact,
              onPressed: () => ref.read(tetherFolderProvider.notifier).clear(),
            ),
          TextButton(
            onPressed: pick,
            child: Text(tr("browse"), style: AppTypography.bodyLarge),
          ),
        ],
      ),
    );
  }
}
