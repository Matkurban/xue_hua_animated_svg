import 'package:example/pages/main_tab_page.dart';
import 'package:example/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const AnimatedSvgShowcaseApp());
}

/// Example app entry: bottom tabs → showcase & fullscreen gallery, themed with [AppTheme].
class AnimatedSvgShowcaseApp extends StatelessWidget {
  const AnimatedSvgShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '动态 SVG 引擎示例',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const MainTabPage(),
    );
  }
}
