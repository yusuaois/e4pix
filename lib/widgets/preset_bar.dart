import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/preset_state.dart';

// 桌面端：横向 chip 滚动条
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
      error: (e, _) => Text('Preset load failed: $e'),
      data: (presets) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.style, size: 16, color: Colors.white70),
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
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

// 手机端：在 tab 里的纵向 preset 列表
class PresetTabContent extends ConsumerWidget {
  const PresetTabContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(presetNotifierProvider);
    final notifier = ref.read(presetNotifierProvider.notifier);

    return asyncList.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (presets) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.bookmark_add, size: 16),
                label: Text(
                  tr("saveCurrentAsPreset"),
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () => showSavePresetDialog(context, notifier),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: presets.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.05),
              ),
              itemBuilder: (ctx, i) {
                final p = presets[i];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.style,
                    size: 16,
                    color: p.isBuiltin
                        ? Colors.blueGrey
                        : Colors.deepPurpleAccent,
                  ),
                  title: Text(p.name, style: const TextStyle(fontSize: 13)),
                  trailing: p.isBuiltin
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.more_vert, size: 18),
                          onPressed: () => _showPresetOptions(ctx, ref, p),
                        ),
                  onTap: () => notifier.apply(p.id),
                );
              },
            ),
          ),
        ],
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
          : () => _showPresetOptions(context, ref, preset),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: preset.isBuiltin
              ? Colors.blueGrey.withValues(alpha: 0.3)
              : Colors.deepPurple.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: preset.isBuiltin ? Colors.blueGrey : Colors.deepPurpleAccent,
            width: 0.6,
          ),
        ),
        child: Text(
          preset.name,
          style: const TextStyle(fontSize: 12, color: Colors.white),
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
}

Future<void> _showPresetOptions(
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
            leading: const Icon(Icons.delete, color: Colors.redAccent),
            title: Text(
              tr("delete"),
              style: TextStyle(color: Colors.redAccent),
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
    final newName = await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(tr("rename")),
        content: TextField(controller: controller, autofocus: true),
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
  }
}
