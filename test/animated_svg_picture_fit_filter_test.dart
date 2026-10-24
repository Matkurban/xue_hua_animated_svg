import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

const _squareSvg = '''
<svg viewBox="0 0 40 40" width="40" height="40" xmlns="http://www.w3.org/2000/svg">
  <circle cx="20" cy="20" r="12" fill="#22C55E">
    <animate attributeName="r" values="8;16;8" dur="1s" repeatCount="indefinite"/>
  </circle>
</svg>
''';

void main() {
  testWidgets('defaults to BoxFit.contain and paints without ColorFiltered', (
    tester,
  ) async {
    final controller = AnimatedSvgController(autoPlay: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: AnimatedSvgPicture.string(
            _squareSvg,
            controller: controller,
            width: 80,
            height: 40,
          ),
        ),
      ),
    );

    expect(find.byType(ColorFiltered), findsNothing);
    final paint = tester.widget<CustomPaint>(find.byType(CustomPaint).first);
    final painter = paint.painter! as AnimatedSvgPainter;
    expect(painter.fit, BoxFit.contain);
    expect(paint.size, const Size(80, 40));
  });

  testWidgets('fit parameter is forwarded for each BoxFit value', (tester) async {
    final controller = AnimatedSvgController(autoPlay: false);
    addTearDown(controller.dispose);

    for (final fit in BoxFit.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: AnimatedSvgPicture.string(
              _squareSvg,
              controller: controller,
              width: 120,
              height: 60,
              fit: fit,
            ),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(find.byType(CustomPaint).first);
      expect((paint.painter! as AnimatedSvgPainter).fit, fit);
    }
  });

  testWidgets('colorFilter wraps CustomPaint in ColorFiltered', (tester) async {
    final controller = AnimatedSvgController(autoPlay: false);
    addTearDown(controller.dispose);
    const filter = ColorFilter.mode(Color(0xFFFF0000), BlendMode.srcIn);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: AnimatedSvgPicture.string(
            _squareSvg,
            controller: controller,
            width: 40,
            height: 40,
            colorFilter: filter,
          ),
        ),
      ),
    );

    expect(find.byType(ColorFiltered), findsOneWidget);
    final filtered = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
    expect(filtered.colorFilter, filter);
    expect(find.descendant(
      of: find.byType(ColorFiltered),
      matching: find.byType(CustomPaint),
    ), findsWidgets);
  });

  testWidgets('colorFilter remains across seek and play state changes', (tester) async {
    final controller = AnimatedSvgController(autoPlay: true, speed: 1.0);
    addTearDown(controller.dispose);
    const filter = ColorFilter.mode(Color(0xFF0000FF), BlendMode.srcIn);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: AnimatedSvgPicture.string(
            _squareSvg,
            controller: controller,
            width: 40,
            height: 40,
            colorFilter: filter,
          ),
        ),
      ),
    );

    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(controller.isPlaying, isTrue);

    controller.seek(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(controller.elapsedMicroseconds, greaterThan(0));

    controller.pause();
    await tester.pump();
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(controller.isPlaying, isFalse);

    controller.play();
    await tester.pump();
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(controller.isPlaying, isTrue);
  });

  testWidgets('constraint change keeps fit and colorFilter', (tester) async {
    final controller = AnimatedSvgController(autoPlay: false);
    addTearDown(controller.dispose);
    const filter = ColorFilter.mode(Color(0xFF00FF00), BlendMode.srcIn);

    Future<void> pumpAt(Size size) {
      return tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: AnimatedSvgPicture.string(
              _squareSvg,
              controller: controller,
              width: size.width,
              height: size.height,
              fit: BoxFit.cover,
              colorFilter: filter,
            ),
          ),
        ),
      );
    }

    await pumpAt(const Size(40, 40));
    await pumpAt(const Size(160, 80));

    final paint = tester.widget<CustomPaint>(find.byType(CustomPaint).first);
    expect(paint.size, const Size(160, 80));
    expect((paint.painter! as AnimatedSvgPainter).fit, BoxFit.cover);
    expect(find.byType(ColorFiltered), findsOneWidget);
  });

  test('AnimatedSvgPainter applyBoxFit cover fills wide viewport', () {
    final scene = SvgParser.compile(_squareSvg);
    addTearDown(scene.dispose);
    final controller = AnimatedSvgController(autoPlay: false);
    addTearDown(controller.dispose);

    final painter = AnimatedSvgPainter(
      scene: scene,
      controller: controller,
      fit: BoxFit.cover,
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // Should not throw for a non-square destination.
    painter.paint(canvas, const ui.Size(200, 80));
    recorder.endRecording().dispose();
  });

  testWidgets('named constructors accept fit and colorFilter', (tester) async {
    final controller = AnimatedSvgController(autoPlay: false);
    addTearDown(controller.dispose);
    const filter = ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn);
    final scene = SvgParser.compile(_squareSvg);
    addTearDown(scene.dispose);

    for (final child in <Widget>[
      AnimatedSvgPicture.string(
        _squareSvg,
        controller: controller,
        width: 20,
        height: 20,
        fit: BoxFit.fill,
        colorFilter: filter,
      ),
      AnimatedSvgPicture.compiled(
        scene,
        controller: controller,
        width: 20,
        height: 20,
        fit: BoxFit.fitWidth,
        colorFilter: filter,
      ),
    ]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: child),
        ),
      );
      expect(find.byType(ColorFiltered), findsOneWidget);
      final paint = tester.widget<CustomPaint>(find.byType(CustomPaint).first);
      expect((paint.painter! as AnimatedSvgPainter).fit, isNot(BoxFit.contain));
    }
  });
}
