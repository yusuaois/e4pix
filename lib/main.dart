import 'package:e4pix/services/debug/debug_log_service.dart';
import 'package:e4pix/services/notifications/notification_manager.dart';
import 'package:e4pix/widgets/app/app_exit_guard.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import './core/theme/app_colors.dart';
import './core/theme/app_typography.dart';
import 'screens/develop_screen.dart';
import '../../state/providers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 拦截 debugPrint，捕获日志到 DebugLogService
  debugPrint = (String? message, {int? wrapWidth}) {
    DebugLogService.instance.add(message ?? '');
  };

  await EasyLocalization.ensureInitialized();
  await DebugLogService.instance.ensureLoaded();
  await NotificationManager.instance.init();

  runApp(
    ProviderScope(
      child: ExcludeSemantics(
        child: EasyLocalization(
          supportedLocales: [Locale('en', 'US'), Locale('zh', 'CN')],
          path: 'assets/translations',
          fallbackLocale: Locale('en', 'US'),
          child: E4pixApp(),
        ),
      ),
    ),
  );
}

/// 从灰度 seed 构建纯中性 ColorScheme
ColorScheme _grayScheme(int seed) {
  final c = Color(seed);
  final v = (c.r * 0.299 + c.g * 0.587 + c.b * 0.114).round();
  final primary = Color.fromARGB(255, v, v, v);
  return ColorScheme(
    brightness: Brightness.dark,
    primary: primary,
    onPrimary: AppColors.scaffoldBg,
    secondary: primary,
    onSecondary: AppColors.scaffoldBg,
    surface: AppColors.panelBg,
    onSurface: AppColors.textPrimary,
    error: AppColors.semanticError,
    onError: AppColors.scaffoldBg,
  );
}

class E4pixApp extends ConsumerWidget {
  const E4pixApp({super.key});
  static const _scaffoldBg = AppColors.scaffoldBg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 尽早触发 shader 预热（8 个 shader 并行加载编译），不阻塞 UI
    ref.watch(shaderWarmupProvider);

    final dynamicEnabled = ref.watch(dynamicColorEnabledProvider);
    final seed = ref.watch(seedColorProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final ColorScheme scheme = (dynamicEnabled && darkDynamic != null)
            ? darkDynamic.copyWith(brightness: Brightness.dark)
            : _grayScheme(seed);

        return MaterialApp(
          title: 'e4pix',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: scheme,
            scaffoldBackgroundColor: _scaffoldBg,
            // ── 对话框：统一 elevatedBg 背景 ──
            dialogTheme: const DialogThemeData(
              backgroundColor: AppColors.elevatedBg,
            ),
            // ── SnackBar：统一浮动样式 ──
            snackBarTheme: SnackBarThemeData(
              backgroundColor: AppColors.elevatedBg,
              contentTextStyle: AppTypography.bodyLarge.copyWith(
                color: AppColors.textPrimary,
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            // ── 交互反馈：桌面端 hover/焦点 ──
            hoverColor: Colors.white.withValues(alpha: 0.08),
            splashColor: Colors.white.withValues(alpha: 0.06),
            highlightColor: Colors.white.withValues(alpha: 0.04),
            focusColor: Colors.white.withValues(alpha: 0.12),
            // ── 页面过渡 ──
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              },
            ),
            // ── 滑块：灰阶细轨道 ──
            sliderTheme: SliderThemeData(
              trackHeight: 2.0,
              activeTrackColor: AppColors.textSecondary,
              inactiveTrackColor: AppColors.inactiveTrack,
              thumbColor: AppColors.active,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayColor: AppColors.subtleBorder,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
          ),
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: const AppExitGuard(child: DevelopScreen()),
        );
      },
    );
  }
}
