import 'dart:io' show File, Platform;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:liino_api/liino_api.dart';
import 'package:liino_app/l10n/app_localizations.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'features/home/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_nativeLibPath()));
    debugPrint('[liino] Rust core loaded');
  } catch (e) {
    debugPrint('[liino] Rust core unavailable: $e');
  }
  runApp(const LiinoApp());
}

String _nativeLibPath() {
  final override = Platform.environment['LIINO_NATIVE_LIB'];
  if (override != null && override.isNotEmpty) {
    return override;
  }
  // macOS: <App>.app/Contents/MacOS/<executable> -> Contents/Frameworks/
  final contents = File(Platform.resolvedExecutable).parent.parent;
  return '${contents.path}/Frameworks/libliino_api.dylib';
}

class LiinoApp extends StatelessWidget {
  const LiinoApp({super.key});

  static const Color _seedColor = Color(0xFF006A6A);

  @override
  Widget build(BuildContext context) {
    return M3EMaterialApp(
      title: 'liino',
      debugShowCheckedModeBanner: false,
      data: M3EThemeData.light(seedColor: _seedColor),
      autoTheming: true,
      dynamicColoring: true,
      drawUnderSystemBars: true,
      // Follow the system language: Chinese systems resolve to zh, all others
      // fall back to en. Leaving `locale` unset enables this default behavior.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const LiinoHomePage(),
    );
  }
}
