import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'features/home/home_page.dart';

void main() {
  runApp(const LiinoApp());
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
      home: const LiinoHomePage(),
    );
  }
}
