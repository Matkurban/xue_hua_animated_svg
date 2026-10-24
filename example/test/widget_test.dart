import 'package:example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('首页展示资源列表并可进入预览', (WidgetTester tester) async {
    await tester.pumpWidget(const AnimatedSvgShowcaseApp());
    await tester.pump();

    expect(find.text('动态 SVG 示例'), findsOneWidget);
    expect(find.text('大象描边'), findsOneWidget);
    expect(find.text('CyberCore 合成演示'), findsOneWidget);
    expect(find.text('呼吸圆'), findsOneWidget);
    expect(find.text('网络大象'), findsOneWidget);

    await tester.tap(find.text('大象描边'));
    // Infinite SVG animations prevent pumpAndSettle from ever finishing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // autoPlay defaults to true, so the primary control shows 暂停.
    expect(find.text('暂停'), findsOneWidget);
    expect(find.text('重置'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });
}
