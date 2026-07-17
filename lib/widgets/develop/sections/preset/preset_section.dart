import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../services/export/xmp_export.dart';
import '../../../../services/export/xmp_import.dart';
import '../../../../state/providers.dart';

class PresetBar extends ConsumerStatefulWidget {
  const PresetBar({super.key});

  @override
  ConsumerState<PresetBar> createState() => _PresetBarState();
}

class _PresetBarState extends ConsumerState<PresetBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(presetNotifierProvider);
    final notifier = ref.read(presetNotifierProvider.notifier);

    return asyncList.when(
      loading: () => const SizedBox(height: 40),
      error: (e, _) => Text(tr('presetLoadFailed', namedArgs: {'error': '$e'})),
      data: (presets) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.style, size: 16, color: AppColors.mediumText),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 28,
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
                        final offset = signal.scrollDelta.dy;
                        final target = _scrollController.offset + offset;
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
                      itemCount: presets.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (ctx, i) => PresetChip(
                        preset: presets[i],
                        onTap: () => notifier.apply(presets[i].id),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: tr("saveCurrentAsPreset"),
              onPressed: () => showSavePresetDialog(context, notifier),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            IconButton(
              icon: const Icon(Icons.input, size: 18),
              tooltip: tr("xmpImport"),
              onPressed: () => importXmpPreset(context, ref),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            IconButton(
              icon: const Icon(Icons.file_download_outlined, size: 18),
              tooltip: tr("exportPreset"),
              onPressed: () => exportXmpPreset(context, ref),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
      ),
    );
  }
}

/// 预设网格 2 列卡片 + 顶部操作按钮
class PresetGrid extends ConsumerWidget {
  const PresetGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(presetNotifierProvider);
    final notifier = ref.read(presetNotifierProvider.notifier);
    final primary = Theme.of(context).colorScheme.primary;
    final thumbs = ref.watch(thumbnailCacheProvider).thumbs;
    final cacheNotifier = ref.read(thumbnailCacheProvider.notifier);

    return asyncList.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (presets) {
        for (final p in presets) {
          cacheNotifier.requestPreset(p.id, p.params);
        }

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel(title: 'Preset'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        onPressed: () =>
                            showSavePresetDialog(context, notifier),
                        child: Text(
                          tr("saveCurrentAsPreset"),
                          style: AppTypography.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        onPressed: () => importXmpPreset(context, ref),
                        child: Text(
                          tr("xmpImport"),
                          style: AppTypography.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        onPressed: () => exportXmpPreset(context, ref),
                        child: Text(
                          tr("exportPreset"),
                          style: AppTypography.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.4,
                ),
                itemCount: presets.length,
                itemBuilder: (ctx, i) => _PresetCard(
                  preset: presets[i],
                  primary: primary,
                  thumb: thumbs['preset:${presets[i].id}'],
                  onTap: () => notifier.apply(presets[i].id),
                  onLongPress: presets[i].isBuiltin
                      ? null
                      : () => showPresetOptions(context, ref, presets[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PresetCard extends StatelessWidget {
  final Preset preset;
  final Color primary;
  final ui.Image? thumb;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _PresetCard({
    required this.preset,
    required this.primary,
    this.thumb,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: primary.withValues(alpha: 0.15)),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: thumb != null
                    ? RawImage(
                        image: thumb,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    : Container(
                        width: double.infinity,
                        color: Colors.black.withValues(alpha: 0.2),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.style,
                          size: 20,
                          color: primary.withValues(alpha: 0.2),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    preset.name,
                    style: AppTypography.labelMedium.copyWith(color: primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (preset.isBuiltin)
                  Icon(
                    Icons.lock,
                    size: 9,
                    color: primary.withValues(alpha: 0.4),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 共用
class PresetChip extends ConsumerWidget {
  final Preset preset;
  final VoidCallback onTap;
  const PresetChip({super.key, required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: onTap,
      onLongPress: preset.isBuiltin
          ? null
          : () => showPresetOptions(context, ref, preset),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: preset.isBuiltin ? AppColors.subtleBorder : AppColors.activeBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: preset.isBuiltin
                ? AppColors.dividerLine
                : AppColors.lightBorder,
            width: 0.6,
          ),
        ),
        child: Text(
          preset.name,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

Future<void> showSavePresetDialog(
  BuildContext ctx,
  PresetNotifier notifier,
) async {
  final controller = TextEditingController();
  try {
    final name = await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(tr("saveCurrentAsPreset")),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: tr("presetNameHint")),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr("cancel")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(tr("save")),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await notifier.saveCurrentAs(name);
    }
  } finally {
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }
}

Future<void> showPresetOptions(
  BuildContext ctx,
  WidgetRef ref,
  Preset preset,
) async {
  final action = await showModalBottomSheet<String>(
    context: ctx,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(tr("rename")),
            onTap: () => Navigator.pop(ctx, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: AppColors.semanticError),
            title: Text(
              tr("delete"),
              style: TextStyle(color: AppColors.semanticError),
            ),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!ctx.mounted) return;
  if (action == 'delete') {
    await ref.read(presetNotifierProvider.notifier).delete(preset.id);
  } else if (action == 'rename') {
    final controller = TextEditingController(text: preset.name);
    try {
      final newName = await showDialog<String>(
        context: ctx,
        builder: (_) => AlertDialog(
          title: Text(tr("rename")),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr("cancel")),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(tr("confirm")),
            ),
          ],
        ),
      );
      if (newName != null && newName.isNotEmpty && newName != preset.name) {
        await ref
            .read(presetNotifierProvider.notifier)
            .rename(preset.id, newName);
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  }
}

bool _exportingXmp = false;
Future<void> exportXmpPreset(BuildContext ctx, WidgetRef ref) async {
  if (_exportingXmp) return;
  _exportingXmp = true;
  try {
    final params = ref.read(currentParamsNotifierProvider);
    final xmp = XmpExport.serialize(params);
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: tr("exportPreset"),
    );
    if (dir == null) return;
    final file = File('$dir/e4pix_preset.xmp');
    await file.writeAsString(xmp);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(tr('xmpExported', args: [file.path])),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } finally {
    _exportingXmp = false;
  }
}

Future<void> importXmpPreset(BuildContext ctx, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(ctx);
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xmp'],
  );
  if (result == null || result.files.isEmpty) return;
  final path = result.files.first.path;
  if (path == null) return;

  try {
    final content = await File(path).readAsString();
    final base = ref.read(currentParamsNotifierProvider);
    final (newParams, hit) = XmpImport.parse(content, base);
    if (hit.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(tr('xmpNoFields'))));
      return;
    }
    ref.read(currentParamsNotifierProvider.notifier).update(newParams);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tr('xmpImported', args: ['${hit.length}', hit.join('、')]),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(tr('xmpImportFailed', args: [e.toString()]))),
    );
  }
}
