import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/constants/lut_formats.dart';
import '../../../render/lut_texture_cache.dart';
import '../../../services/lut/lut_library.dart';
import '../../../state/providers.dart';
import '../tracked_slider.dart';
import 'shared.dart';

class LutSection extends ConsumerWidget {
  const LutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lut = ref.watch(lutNotifierProvider);
    final params = ref.watch(currentParamsNotifierProvider);
    final library = ref.watch(lutLibraryNotifierProvider).value ?? const [];

    LutTextureCache.instance.protect(lut.nameA, lut.nameB);

    final thumbState = ref.watch(thumbnailCacheProvider);
    final thumbs = thumbState.thumbs;
    final rendering = thumbState.rendering;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'LUT'),
        const SizedBox(height: 4),
        _LutSlot(
          slot: 0,
          label: 'LUT A',
          lutName: lut.nameA,
          intensity: params.lutIntensity,
          library: library,
          thumbs: thumbs,
          rendering: rendering,
          onItemVisible: (entry) =>
              ref.read(thumbnailCacheProvider.notifier).requestLut(entry),
        ),
        const SizedBox(height: 10),
        _LutSlot(
          slot: 1,
          label: 'LUT B',
          lutName: lut.nameB,
          intensity: params.lutIntensityB,
          library: library,
          thumbs: thumbs,
          rendering: rendering,
          onItemVisible: (entry) =>
              ref.read(thumbnailCacheProvider.notifier).requestLut(entry),
        ),
      ],
    );
  }
}

class _LutSlot extends ConsumerStatefulWidget {
  final int slot;
  final String label;
  final String? lutName;
  final double intensity;
  final List<LutEntry> library;
  final Map<String, ui.Image> thumbs;
  final Set<String> rendering;
  final Function(LutEntry) onItemVisible;

  const _LutSlot({
    required this.slot,
    required this.label,
    required this.lutName,
    required this.intensity,
    required this.library,
    required this.thumbs,
    required this.rendering,
    required this.onItemVisible,
  });

  @override
  ConsumerState<_LutSlot> createState() => _LutSlotState();
}

class _LutSlotState extends ConsumerState<_LutSlot> {
  final MenuController _menuController = MenuController();

  LutEntry? _findSelected() {
    if (widget.lutName == null) return null;
    final target = _stripExt(widget.lutName!).toLowerCase();
    for (final e in widget.library) {
      if (e.name.toLowerCase() == target) return e;
    }
    return null;
  }

  static String _stripExt(String n) {
    final dot = n.lastIndexOf('.');
    return dot < 0 ? n : n.substring(0, dot);
  }

  bool get _isVlt =>
      widget.lutName != null && LutFormats.isVlt(widget.lutName!);

  @override
  Widget build(BuildContext context) {
    final loaded = widget.lutName != null && widget.lutName!.isNotEmpty;
    final selected = _findSelected();
    final missing = loaded && selected == null;

    void writeLutName(String name) {
      final p = ref.read(currentParamsNotifierProvider);
      final np = widget.slot == 0
          ? p.copyWith(lutNameA: name)
          : p.copyWith(lutNameB: name);
      ref.read(currentParamsNotifierProvider.notifier).update(np);
    }

    Future<void> onSelect(LutEntry? entry) async {
      _menuController.close();
      if (entry != null) {
        await LutTextureCache.instance.load(entry.name);
      }
      writeLutName(entry?.name ?? '');
    }

    Future<void> onImport() async {
      _menuController.close();
      final entry = await ref
          .read(lutLibraryNotifierProvider.notifier)
          .importFromFile();
      if (entry != null) {
        await LutTextureCache.instance.load(entry.name);
        writeLutName(entry.name);
      }
    }

    Future<void> onDelete(LutEntry entry) async {
      final cur = ref.read(currentParamsNotifierProvider);
      final target = entry.name.toLowerCase();
      var np = cur;
      if (cur.lutNameA.toLowerCase() == target) {
        np = np.copyWith(lutNameA: '');
      }
      if (cur.lutNameB.toLowerCase() == target) {
        np = np.copyWith(lutNameB: '');
      }
      if (!identical(np, cur)) {
        ref.read(currentParamsNotifierProvider.notifier).update(np);
      }
      LutTextureCache.instance.invalidate(entry.name);
      await ref.read(lutLibraryNotifierProvider.notifier).delete(entry);
    }

    void onIntensityChanged(double v) {
      final p = ref.read(currentParamsNotifierProvider);
      final np = widget.slot == 0
          ? p.copyWith(lutIntensity: v)
          : p.copyWith(lutIntensityB: v);
      ref.read(currentParamsNotifierProvider.notifier).update(np);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: MenuAnchor(
                  controller: _menuController,
                  style: MenuStyle(
                    padding: WidgetStateProperty.all(EdgeInsets.zero),
                    minimumSize: WidgetStateProperty.all(const Size(280, 0)),
                    maximumSize: WidgetStateProperty.all(const Size(280, 360)),
                  ),
                  builder: (context, controller, child) {
                    return InkWell(
                      onTap: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selected != null
                                    ? selected.name
                                    : (widget.library.isEmpty
                                          ? tr("notImportedLUT")
                                          : tr("notChosen")),
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              size: 18,
                              color: Colors.white54,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  menuChildren: widget.library.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Center(
                              child: Text(
                                tr("notImportedLUT"),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ]
                      : [
                          ListTile(
                            dense: true,
                            title: Text(
                              tr("notChosen"),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                            onTap: () => onSelect(null),
                          ),
                          ...widget.library.map((entry) {
                            return _LutMenuItem(
                              entry: entry,
                              thumb: widget.thumbs['lut:${entry.name}'],
                              isRendering: widget.rendering.contains(
                                entry.name,
                              ),
                              onSelect: () => onSelect(entry),
                              onVisible: () => widget.onItemVisible(entry),
                            );
                          }),
                        ],
                ),
              ),
              if (selected != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: tr("deleteCurrentLUT"),
                  onPressed: () =>
                      _confirmDelete(context, ref, selected, onDelete),
                ),
              IconButton(
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: tr("importCube"),
                onPressed: onImport,
              ),
            ],
          ),
        ),
        if (missing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 13,
                  color: Colors.orangeAccent.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    tr('lutMissing', args: [widget.lutName!]),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.orangeAccent.withValues(alpha: 0.85),
                    ),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        if (_isVlt)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Text(
              tr("lutVltHint"),
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.orangeAccent.withValues(alpha: 0.75),
              ),
            ),
          ),
        if (loaded) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    tr("intensity"),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: TrackedSlider(
                      value: widget.intensity.clamp(0.0, 1.0),
                      onChanged: onIntensityChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(widget.intensity * 100).round()}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: AppColors.activeValue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext ctx,
    WidgetRef ref,
    LutEntry entry,
    Future<void> Function(LutEntry) onDelete,
  ) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(tr('deleteLUT')),
        content: Text(tr('confirmDeleteLUT', args: [entry.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr("cancel")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text(tr("delete")),
          ),
        ],
      ),
    );
    if (ok == true) await onDelete(entry);
  }
}

class _LutMenuItem extends StatefulWidget {
  final LutEntry entry;
  final ui.Image? thumb;
  final bool isRendering;
  final VoidCallback onSelect;
  final VoidCallback onVisible;

  const _LutMenuItem({
    required this.entry,
    required this.thumb,
    required this.isRendering,
    required this.onSelect,
    required this.onVisible,
  });

  @override
  State<_LutMenuItem> createState() => _LutMenuItemState();
}

class _LutMenuItemState extends State<_LutMenuItem> {
  bool _isVisible = false;
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _triggerVisible() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _isVisible) {
        widget.onVisible();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _LutMenuItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumb != null && widget.thumb == null && _isVisible) {
      _triggerVisible();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('lut_menu_item_${widget.entry.name}'),
      onVisibilityChanged: (VisibilityInfo info) {
        if (!mounted) return;

        final visible = info.visibleFraction > 0;

        if (visible != _isVisible) {
          _isVisible = visible;
          if (!_isVisible) {
            _debounceTimer?.cancel();
          }
        }

        if (_isVisible && widget.thumb == null && !widget.isRendering) {
          _triggerVisible();
        }
      },
      child: InkWell(
        onTap: widget.onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  width: 40,
                  height: 27,
                  child: widget.thumb != null
                      ? RawImage(image: widget.thumb, fit: BoxFit.cover)
                      : Container(
                          color: Colors.white.withValues(alpha: 0.06),
                          child: widget.isRendering
                              ? const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.white30,
                                  ),
                                )
                              : null,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.entry.name,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.entry.ext.toUpperCase(),
                style: TextStyle(
                  fontSize: 9.5,
                  fontFamily: 'monospace',
                  color: widget.entry.ext == 'vlt'
                      ? Colors.orangeAccent.withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
