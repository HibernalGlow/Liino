import 'package:flutter/material.dart';
import 'design_system/tokens.dart';
import 'features/home/home_page.dart';

void main() {
  runApp(const LiinoApp());
}

class LiinoApp extends StatelessWidget {
  const LiinoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'liino',
      debugShowCheckedModeBanner: false,
      theme: LiinoDesignTokens.buildTheme(Brightness.light),
      darkTheme: LiinoDesignTokens.buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const LiinoHomePage(),
    );
  }
}
