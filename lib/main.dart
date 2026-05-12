import 'package:flutter/material.dart';
import 'screens/develop_screen.dart';
import 'package:easy_localization/easy_localization.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      // en-US.json, zh-CN.json
      supportedLocales: [Locale('en', 'US'), Locale('zh', 'CN')],
      path: 'assets/translations',
      fallbackLocale: Locale('en', 'US'),
      child: E4pixApp(),
    ),
  );
}

class E4pixApp extends StatelessWidget {
  const E4pixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'e4pix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B5BFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E0E12),
      ),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: const DevelopScreen(),
    );
  }
}
