import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/keybindings/app_action.dart';
import '../core/keybindings/keybinding_service.dart';

class KeybindingSettingsScreen extends ConsumerWidget {
  const KeybindingSettingsScreen({super.key});
  static const _groups = <String, List<AppAction>>{
    'keyGroupOps': [
      AppAction.toggleFullscreen,
      AppAction.compareHold,
      AppAction.enterCrop,
    ],
    'keyGroupRating': [
      AppAction.rate0,
      AppAction.rate1,
      AppAction.rate2,
      AppAction.rate3,
      AppAction.rate4,
      AppAction.rate5,
    ],
    'keyGroupFlag': [AppAction.flagPick, AppAction.flagReject],
    'keyGroupNav': [AppAction.prevImage, AppAction.nextImage],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(keybindingServiceProvider);
    final notifier = ref.read(keybindingServiceProvider.notifier);

    Future<void> record(AppAction action) async {
      final result = await showDialog(
        context: context,
        builder: (_) => _KeyRecordDialog(action: action),
      );
      if (!context.mounted) return;
      if (result == null) return; // 取消
      if (result == 'CLEAR') {
        await notifier.clearBinding(action);
        return;
      }
      final key = result as LogicalKeyboardKey;
      // 冲突预览
      final conflict = notifier.conflictFor(key, action);
      if (conflict != null) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.elevatedBg,
            title: Text(tr('keyConflictTitle')),
            content: Text(
              tr(
                'keyConflictBody',
                args: [keyDisplayName(key), tr(conflict.labelKey)],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr('keyConflictOverride')),
              ),
            ],
          ),
        );
        if (!context.mounted) return;
        if (ok != true) return;
      }
      await notifier.setBinding(action, key);
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(tr('settingsKeybindings')),
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppColors.elevatedBg,
                  title: Text(tr('keyResetTitle')),
                  content: Text(tr('keyResetBody')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(tr('cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(tr('reset')),
                    ),
                  ],
                ),
              );
              if (ok == true) await notifier.resetDefaults();
            },
            child: Text(tr('reset')),
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final entry in _groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(
                tr(entry.key).toUpperCase(),
                style: AppTypography.labelSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: AppColors.faintText,
                ),
              ),
            ),
            for (final action in entry.value)
              ListTile(
                dense: true,
                title: Text(
                  tr(action.labelKey),
                  style: AppTypography.titleMedium,
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: st.keyFor(action) == null
                        ? Colors.transparent
                        : AppColors.dividerLine,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: st.keyFor(action) == null
                          ? AppColors.semanticWarning.withValues(alpha: 0.5)
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Text(
                    keyDisplayName(st.keyFor(action)),
                    style: AppTypography.bodyLarge.copyWith(
                      fontFamily: 'monospace',
                      color: st.keyFor(action) == null
                          ? AppColors.semanticWarning
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                onTap: () => record(action),
              ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _KeyRecordDialog extends StatefulWidget {
  final AppAction action;
  const _KeyRecordDialog({required this.action});
  @override
  State<_KeyRecordDialog> createState() => _KeyRecordDialogState();
}

class _KeyRecordDialogState extends State<_KeyRecordDialog> {
  String? _error;

  /// 非 hold 型动作禁止绑定的键
  static final _forbiddenNonHold = {
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  /// hold 型动作只禁止 Esc / Enter
  static final _forbiddenHold = {
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };

  bool get _isHold => widget.action.isHold;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.elevatedBg,
      title: Text(tr(widget.action.labelKey)),
      content: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.handled;
          final key = event.logicalKey;

          // hold 型动作：允许修饰键，只禁止 Esc/Enter
          // 非 hold 型：禁止修饰键 + Esc/Enter
          final forbidden = _isHold ? _forbiddenHold : _forbiddenNonHold;
          if (forbidden.contains(key)) {
            setState(() => _error = tr('keyForbidden'));
            return KeyEventResult.handled;
          }
          // 非 hold 型：有修饰键组合时也禁止
          if (!_isHold &&
              (HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isAltPressed ||
                  HardwareKeyboard.instance.isMetaPressed ||
                  HardwareKeyboard.instance.isShiftPressed)) {
            setState(() => _error = tr('keyForbidden'));
            return KeyEventResult.handled;
          }

          Navigator.pop(context, key); // 返回捕获的键
          return KeyEventResult.handled;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('keyPressPrompt'),
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.mediumText,
              ),
            ),
            const SizedBox(height: 12),
            Icon(Icons.keyboard, size: 40, color: AppColors.disabledText),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.semanticWarning,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'CLEAR'), // 清除绑定
          child: Text(tr('keyClear')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, null), // 取消
          child: Text(tr('cancel')),
        ),
      ],
    );
  }
}
