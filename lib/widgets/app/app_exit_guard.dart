import 'dart:ui' show AppExitResponse;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// 全局退出拦截器：拦截窗口关闭请求，若有必要则弹出确认对话框
///
/// 通过 [MaterialApp.builder] 放置在 Navigator 上方，确保任何界面下都能
/// 拦截退出请求 Android 返回键/手势由各页面的 [PopScope] 调用
/// [showExitConfirmDialog] 复用同一套确认逻辑
class AppExitGuard extends ConsumerStatefulWidget {
  const AppExitGuard({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppExitGuard> createState() => _AppExitGuardState();

  /// 通用退出确认弹窗，可从任何 [ConsumerState] 中调用
  ///
  /// 返回 `true` 表示用户确认退出，`false` 表示取消
  /// 会自动检查：
  /// - 是否有正在进行的导出任务（如有则显示警告）
  /// - 用户是否勾选了「不再询问」
  static Future<bool> showExitConfirmDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // 检查是否有正在进行的导出任务
    final exportQueue = ref.read(exportQueueProvider);
    final hasActiveExports = exportQueue.where((j) => !j.isFinished).isNotEmpty;

    if (hasActiveExports) {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('exitConfirmTitle')),
          content: Text(tr('exitWithActiveExports')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('exit')),
            ),
          ],
        ),
      );
      return result ?? false;
    }

    // 检查是否跳过确认
    final skip = ref.read(skipExitConfirmProvider);
    if (skip) return true;

    bool dontAskAgain = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('exitConfirmTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('exitConfirmBody')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: dontAskAgain,
                    onChanged: (v) {
                      setDialogState(() => dontAskAgain = v ?? false);
                    },
                  ),
                  GestureDetector(
                    onTap: () =>
                        setDialogState(() => dontAskAgain = !dontAskAgain),
                    child: Text(tr('exitConfirmDontAskAgain')),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('exit')),
            ),
          ],
        ),
      ),
    );

    if (result == true && dontAskAgain) {
      ref.read(skipExitConfirmProvider.notifier).set(true);
    }
    return result ?? false;
  }
}

class _AppExitGuardState extends ConsumerState<AppExitGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!mounted) return AppExitResponse.exit;
    final confirmed = await AppExitGuard.showExitConfirmDialog(context, ref);
    return confirmed ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
