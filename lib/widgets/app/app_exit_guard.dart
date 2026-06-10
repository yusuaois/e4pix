import 'dart:ui' show AppExitResponse;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// 全局退出拦截器：拦截窗口关闭请求，若有必要则弹出确认对话框。
///
/// 通过 [MaterialApp.builder] 放置在 Navigator 上方，确保任何界面下都能
/// 拦截退出请求。不负责返回键拦截——返回键由各页面的 [PopScope] 管理。
class AppExitGuard extends ConsumerStatefulWidget {
  const AppExitGuard({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppExitGuard> createState() => _AppExitGuardState();
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
    // 检查是否有正在进行的导出任务
    final exportQueue = ref.read(exportQueueProvider);
    final hasActiveExports = exportQueue.where((j) => !j.isFinished).isNotEmpty;

    if (hasActiveExports) {
      if (!mounted) return AppExitResponse.exit;
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
      return (result ?? false) ? AppExitResponse.exit : AppExitResponse.cancel;
    }

    // 检查是否跳过确认
    final skip = ref.read(skipExitConfirmProvider);
    if (skip) return AppExitResponse.exit;

    if (!mounted) return AppExitResponse.exit;
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

    if (result == true) {
      if (dontAskAgain) {
        ref.read(skipExitConfirmProvider.notifier).set(true);
      }
      return AppExitResponse.exit;
    }
    return AppExitResponse.cancel;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
