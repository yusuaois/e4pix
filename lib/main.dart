import 'dart:async';

import 'package:flutter/material.dart';
import 'core/cache/raw_cache_cleaner.dart';
import 'screens/develop_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  unawaited(RawCacheCleaner.cleanOld());

  runApp(
    ProviderScope(
      child: EasyLocalization(
        // en-US.json, zh-CN.json
        supportedLocales: [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: Locale('en', 'US'),
        child: E4pixApp(),
      ),
    ),
  );
}

class E4pixApp extends StatelessWidget {
  const E4pixApp({super.key});
  static const _fallbackSeed = Color(0xFF6B5BFF);
  static const _scaffoldBg = Color(0xFF0E0E12);

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final ColorScheme scheme =
            (darkDynamic ??
                    ColorScheme.fromSeed(
                      seedColor: _fallbackSeed,
                      brightness: Brightness.dark,
                    ))
                .copyWith(brightness: Brightness.dark);

        return MaterialApp(
          title: 'e4pix',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: scheme,
            scaffoldBackgroundColor: _scaffoldBg,
          ),
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: const DevelopScreen(),
        );
      },
    );
  }
}
