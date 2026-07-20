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

ColorScheme _customScheme(int seed) {
  return ColorScheme.fromSeed(
    seedColor: Color(seed),
    brightness: Brightness.dark,
  ).copyWith(surface: AppColors.panelBg, onSurface: AppColors.textPrimary);
}

class E4pixApp extends ConsumerWidget {
  const E4pixApp({super.key});
  static const _scaffoldBg = AppColors.scaffoldBg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // shader 预热
    ref.watch(shaderWarmupProvider);

    final dynamicEnabled = ref.watch(dynamicColorEnabledProvider);
    final seed = ref.watch(seedColorProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final ColorScheme scheme = (dynamicEnabled && darkDynamic != null)
            ? darkDynamic.copyWith(brightness: Brightness.dark)
            : _customScheme(seed);

        return MaterialApp(
          title: 'e4pix',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: scheme,
            scaffoldBackgroundColor: _scaffoldBg,
            dialogTheme: const DialogThemeData(
              backgroundColor: AppColors.elevatedBg,
            ),
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
            hoverColor: Colors.white.withValues(alpha: 0.08),
            splashColor: Colors.white.withValues(alpha: 0.06),
            highlightColor: Colors.white.withValues(alpha: 0.04),
            focusColor: Colors.white.withValues(alpha: 0.12),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              },
            ),
            sliderTheme: SliderThemeData(
              trackHeight: 2.0,
              inactiveTrackColor: AppColors.inactiveTrack,
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
