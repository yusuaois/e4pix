import 'package:e4pix/services/notifications/notification_manager.dart';
import 'package:e4pix/widgets/app/app_exit_guard.dart';
import 'package:flutter/material.dart';
import './core/theme/app_colors.dart';
import 'screens/develop_screen.dart';
import '../../state/providers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
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
            // 全局 Slider 默认样式
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
