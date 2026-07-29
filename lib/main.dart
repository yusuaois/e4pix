import 'package:e4pix/services/debug/debug_log_service.dart';
import 'package:e4pix/services/notifications/notification_manager.dart';
import 'package:e4pix/widgets/app/app_exit_guard.dart';
import 'package:flutter/material.dart';
import './core/theme/app_theme.dart';
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
          supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en', 'US'),
          child: const E4pixApp(),
        ),
      ),
    ),
  );
}

class E4pixApp extends ConsumerWidget {
  const E4pixApp({super.key});

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
            : customColorScheme(seed);

        return MaterialApp(
          title: 'e4pix',
          debugShowCheckedModeBanner: false,
          theme: appTheme(scheme),
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: const AppExitGuard(child: DevelopScreen()),
        );
      },
    );
  }
}
