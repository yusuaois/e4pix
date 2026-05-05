import 'package:flutter/material.dart';
import 'screens/raw_smoke_test_screen.dart';

void main() {
  runApp(const E4pixApp());
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
      home: const RawSmokeTestScreen(),
    );
  }
}
