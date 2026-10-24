import 'package:example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AnimatedSvgShowcaseApp renders elephant.svg and controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnimatedSvgShowcaseApp());
    expect(find.text('elephant.svg (Asset)'), findsOneWidget);
    expect(find.text('CyberCore (3D + Morph)'), findsOneWidget);
  });
}
