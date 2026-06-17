import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/tethered_shot.dart';
import '../../core/theme/app_typography.dart';
import '../../screens/settings_screen.dart';
import '../../state/providers.dart';
import '../export/export_queue_panel.dart';

class DevelopTopBar extends ConsumerWidget {
  final VoidCallback onExport;
  final VoidCallback onSync;
  final VoidCallback onTetherFolder;
  final VoidCallback onTetherCamera;
  final VoidCallback onStopTether;
  final VoidCallback onAI;
  final VoidCallback onAILongPress;

  const DevelopTopBar({
    super.key,
    required this.onExport,
    required this.onSync,
    required this.onTetherFolder,
    required this.onTetherCamera,
    required this.onStopTether,
    required this.onAI,
    required this.onAILongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(imageNotifierProvider).value;
    final program = ref.watch(shaderProgramProvider).value;
    final session = ref.watch(tetherSessionNotifierProvider);
    final cameraState = ref.watch(cameraNotifierProvider);
    final selection = ref.watch(exportSelectionNotifierProvider);
    final shots = ref.watch(shotsNotifierProvider);
    final hist = ref.watch(historyNotifierProvider);
    final notifier = ref.read(historyNotifierProvider.notifier);
    final filterActive = ref.watch(shotFilterProvider).isActive;
    final compareMode = ref.watch(compareViewModeProvider);

    final hasImage = image != null && program != null;
    final isVertical = MediaQuery.of(context).size.shortestSide < 600;
    final primary = Theme.of(context).colorScheme.primary;

    // 自适应区
    final actions = <_BarAction>[
      if (hasImage)
        _BarAction(
          icon: Icons.crop,
          tooltip: tr('crop'),
          menuKey: 'crop',
          onPressed: () => enterCropMode(ref),
          priority: 95,
        ),
      if (hasImage)
        _BarAction(
          icon: Icons.colorize,
          tooltip: tr('colorPicker'),
          menuKey: 'colorpicker',
          color: ref.watch(colorPickerModeProvider) ? primary : null,
          onPressed: () => ref.read(colorPickerModeProvider.notifier).toggle(),
          priority: 55,
        ),
      if (hasImage)
        _BarAction(
          icon: Icons.ios_share_rounded,
          tooltip: tr('export'),
          menuKey: 'export',
          onPressed: onExport,
          alwaysVisible: true,
          onLongPress: () => _showQueuePanel(context),

          priority: 100,
          badgeCount: ref.watch(exportQueuePendingCountProvider),
        ),
      if (hasImage)
        _BarAction(
          icon: selection.multiSelectMode
              ? Icons.checklist_rtl_rounded
              : Icons.checklist_rounded,
          tooltip: selection.multiSelectMode
              ? tr('multiSelectExit')
              : tr('multiSelect'),
          menuKey: 'multiselect',
          color: selection.multiSelectMode ? primary : null,
          onPressed: shots.isEmpty
              ? null
              : () => ref
                    .read(exportSelectionNotifierProvider.notifier)
                    .toggleMode(),
          priority: 90,
        ),
      if (hasImage)
        _BarAction(
          icon: Icons.auto_awesome,
          tooltip: tr('aiColorSuggestionHint'),
          menuKey: 'ai',
          color: primary,
          onPressed: onAI,
          onLongPress: onAILongPress,
          priority: 60,
        ),
      if (hasImage)
        _BarAction(
          icon: Icons.fullscreen,
          tooltip: tr('fullscreenPreviewBtnHint'),
          menuKey: 'fullscreen',
          onPressed: () =>
              ref.read(fullscreenPreviewProvider.notifier).state = true,
          priority: 40,
        ),
      if (session == null)
        _BarAction(
          icon: Icons.cable_rounded,
          tooltip: tr('tetherFolderMonitor'),
          menuKey: 'tether_folder',
          onPressed: onTetherFolder,
          priority: 35,
        ),
      if (!cameraState.isActive && session == null)
        _BarAction(
          icon: Icons.photo_camera_outlined,
          tooltip: tr('tetherCamera'),
          menuKey: 'tether_camera',
          onPressed: onTetherCamera,
          priority: 30,
        ),
      _BarAction(
        icon: Icons.settings_outlined,
        tooltip: tr('settings'),
        menuKey: 'settings',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        priority: 20,
      ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isVertical ? 8 : 16,
        vertical: isVertical ? 3 : 8,
      ),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Row(
        children: [
          if (hasImage) ...[
            _iconBtn(
              Icons.undo,
              tr('undo'),
              hist.canUndo ? notifier.undo : null,
              isVertical,
            ),
            _iconBtn(
              Icons.redo,
              tr('redo'),
              hist.canRedo ? notifier.redo : null,
              isVertical,
            ),

            _iconBtn(
              compareMode == CompareViewMode.split
                  ? Icons.vertical_split
                  : Icons.compare,
              compareMode == CompareViewMode.split
                  ? tr('splitCompareExit')
                  : tr('compareHint'),
              () => ref.read(compareViewModeProvider.notifier).toggleSplit(),
              isVertical,
              onLongPressStart: (_) =>
                  ref.read(compareViewModeProvider.notifier).startHold(),
              onLongPressEnd: (_) =>
                  ref.read(compareViewModeProvider.notifier).endHold(),
              color: compareMode != CompareViewMode.off
                  ? AppColors.textPrimary
                  : AppColors.mediumText,
            ),
            if (shots.isNotEmpty)
              _buildFilterButton(ref, isVertical, primary, filterActive),
            if (!isVertical)
              const VerticalDivider(width: 1, indent: 8, endIndent: 8),
          ],
          if (cameraState.isActive)
            _iconBtn(
              Icons.photo_camera,
              tr(
                'cameraConnected',
                args: [cameraState.modelName ?? tr('cameraModelUnknown')],
              ),
              onStopTether,
              isVertical,
              color: cameraState.shutterFlash
                  ? AppColors.semanticSuccess
                  : AppColors.textPrimary,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) => _buildAdaptiveActions(
                actions,
                constraints.maxWidth,
                isVertical,
              ),
            ),
          ),
          if (selection.multiSelectMode)
            ..._buildMultiSelectBar(context, ref, selection, shots, isVertical),
        ],
      ),
    );
  }

  Widget _buildFilterButton(
    WidgetRef ref,
    bool isVertical,
    Color primary,
    bool filterActive,
  ) {
    return SizedBox(
      width: _barBtnSize(isVertical),
      height: _barBtnSize(isVertical),
      child: PopupMenuButton<String>(
        icon: Icon(
          Icons.filter_alt,
          size: _barIconSize(isVertical),
          color: filterActive ? primary : null,
        ),
        padding: EdgeInsets.zero,
        tooltip: tr('filter'),
        itemBuilder: (_) => [
          for (int r = 0; r <= 5; r++)
            CheckedPopupMenuItem(
              value: 'rating_$r',
              checked: ref.read(shotFilterProvider).minRating == r,
              child: Text(r == 0 ? tr('filterAllRatings') : '★ ≥ $r'),
            ),
          const PopupMenuDivider(),
          CheckedPopupMenuItem(
            value: 'flag_all',
            checked: ref.read(shotFilterProvider).flag == FlagFilter.all,
            child: Text(tr('filterAllFlags')),
          ),
          CheckedPopupMenuItem(
            value: 'flag_pick',
            checked: ref.read(shotFilterProvider).flag == FlagFilter.pickOnly,
            child: Text(tr('filterPickOnly')),
          ),
          CheckedPopupMenuItem(
            value: 'flag_hidereject',
            checked:
                ref.read(shotFilterProvider).flag == FlagFilter.rejectHidden,
            child: Text(tr('filterHideReject')),
          ),
        ],
        onSelected: (key) {
          final n = ref.read(shotFilterProvider.notifier);
          if (key.startsWith('rating_')) {
            n.setMinRating(int.parse(key.split('_')[1]));
          } else if (key == 'flag_all') {
            n.setFlag(FlagFilter.all);
          } else if (key == 'flag_pick') {
            n.setFlag(FlagFilter.pickOnly);
          } else if (key == 'flag_hidereject') {
            n.setFlag(FlagFilter.rejectHidden);
          }
        },
      ),
    );
  }

  void _showQueuePanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.elevatedBg,
      showDragHandle: true,
      builder: (_) => const ExportQueuePanel(),
    );
  }

  Widget _iconBtn(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed,
    bool isVertical, {
    VoidCallback? onLongPress,
    GestureLongPressStartCallback? onLongPressStart,
    GestureLongPressEndCallback? onLongPressEnd,
    Color? color,
    int badgeCount = 0,
  }) {
    final box = _barBtnSize(isVertical);
    Widget iconWidget = Icon(
      icon,
      size: _barIconSize(isVertical),
      color: color,
    );

    // 角标
    if (badgeCount > 0) {
      iconWidget = Badge(
        label: Text('$badgeCount', style: AppTypography.labelSmall),
        backgroundColor: AppColors.semanticWarning,
        child: iconWidget,
      );
    }

    final btn = SizedBox(
      width: box,
      height: box,
      child: IconButton(
        icon: iconWidget,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: const ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        constraints: BoxConstraints(
          minWidth: box,
          minHeight: box,
          maxWidth: box,
          maxHeight: box,
        ),
      ),
    );

    if (onLongPress != null ||
        onLongPressStart != null ||
        onLongPressEnd != null) {
      return GestureDetector(
        onLongPress: onLongPress,
        onLongPressStart: onLongPressStart,
        onLongPressEnd: onLongPressEnd,
        child: Tooltip(
          message: tooltip,
          triggerMode: TooltipTriggerMode.manual,
          child: btn,
        ),
      );
    } else {
      return Tooltip(message: tooltip, child: btn);
    }
  }

  Widget _buildAdaptiveActions(
    List<_BarAction> actions,
    double maxWidth,
    bool isVertical,
  ) {
    final btnW = isVertical ? 34.0 : 48.0;
    const menuW = 44.0;

    final always = actions.where((a) => a.alwaysVisible).toList();
    final rest = actions.where((a) => !a.alwaysVisible).toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));

    final budget = maxWidth - always.length * btnW - menuW;
    final canShow = rest.isEmpty
        ? 0
        : (budget / btnW).floor().clamp(0, rest.length);

    final shownRest = rest.take(canShow).toList();
    final overflow = rest.skip(canShow).toList();

    final shown = [...always, ...shownRest]
      ..sort((a, b) => b.priority.compareTo(a.priority));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in shown)
          _iconBtn(
            a.icon,
            a.tooltip,
            a.onPressed,
            isVertical,
            onLongPress: a.onLongPress,
            color: a.color,
            badgeCount: a.badgeCount,
          ),
        if (overflow.isNotEmpty)
          SizedBox(
            width: _barBtnSize(isVertical),
            height: _barBtnSize(isVertical),
            child: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: _barIconSize(isVertical)),
              padding: EdgeInsets.zero,
              tooltip: '',
              itemBuilder: (_) => [
                for (final a in overflow)
                  PopupMenuItem(
                    value: a.menuKey,
                    enabled: a.onPressed != null,
                    child: Row(
                      children: [
                        Icon(a.icon, size: 18, color: a.color),
                        const SizedBox(width: 12),
                        Text(a.tooltip),
                      ],
                    ),
                  ),
              ],
              onSelected: (key) {
                final a = overflow.firstWhere((x) => x.menuKey == key);
                a.onPressed?.call();
              },
            ),
          ),
      ],
    );
  }

  double _barBtnSize(bool isVertical) => isVertical ? 30 : 40;
  double _barIconSize(bool isVertical) => isVertical ? 17 : 20;

  List<Widget> _buildMultiSelectBar(
    BuildContext context,
    WidgetRef ref,
    ExportSelection selection,
    List<TetheredShot> shots,
    bool isVertical,
  ) {
    return [
      if (selection.selectedPaths.isNotEmpty) ...[
        _iconBtn(
          Icons.sync,
          tr('syncAdjustments'),
          onSync,
          isVertical,
          color: Theme.of(context).colorScheme.primary,
        ),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tr('selectedShots', args: ['${selection.selectedPaths.length}']),
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      TextButton(
        onPressed: () {
          final n = ref.read(exportSelectionNotifierProvider.notifier);
          if (selection.selectedPaths.length == shots.length) {
            n.clearSelection();
          } else {
            n.selectAll(shots.map((s) => s.path));
          }
        },
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
        ),
        child: Text(
          selection.selectedPaths.length == shots.length
              ? tr('selectNone')
              : tr('selectAll'),
          style: AppTypography.labelSmall,
        ),
      ),
    ];
  }
}

class _BarAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Color? color;
  final bool alwaysVisible;
  final int priority;
  final String menuKey;
  final int badgeCount;

  const _BarAction({
    required this.icon,
    required this.tooltip,
    required this.menuKey,
    this.onPressed,
    this.onLongPress,
    this.color,
    this.alwaysVisible = false,
    this.priority = 0,
    this.badgeCount = 0,
  });
}
