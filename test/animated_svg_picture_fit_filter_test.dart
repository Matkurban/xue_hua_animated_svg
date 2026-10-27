import 'dart:io';
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
  testWidgets(
    'defaults to BoxFit.contain, Alignment.center, no ColorFiltered',
    (tester) async {
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
      expect(painter.alignment, Alignment.center);
      expect(paint.size, const Size(80, 40));
    },
  );

  testWidgets('fit parameter is forwarded for each BoxFit value', (
    tester,
  ) async {
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
    expect(
      find.descendant(
        of: find.byType(ColorFiltered),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
  });

  testWidgets('colorFilter remains across seek and play state changes', (
    tester,
  ) async {
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

  testWidgets('constraint change keeps fit, alignment, and colorFilter', (
    tester,
  ) async {
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
              alignment: Alignment.topLeft,
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
    expect((paint.painter! as AnimatedSvgPainter).alignment, Alignment.topLeft);
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

  testWidgets('named constructors accept fit, alignment, and colorFilter', (
    tester,
  ) async {
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
        alignment: Alignment.bottomRight,
        colorFilter: filter,
      ),
      AnimatedSvgPicture.compiled(
        scene,
        controller: controller,
        width: 20,
        height: 20,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
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
      final painter = paint.painter! as AnimatedSvgPainter;
      expect(painter.fit, isNot(BoxFit.contain));
      expect(painter.alignment, isNot(Alignment.center));
    }
  });

  testWidgets('alignment is forwarded for common Alignment values', (
    tester,
  ) async {
    final controller = AnimatedSvgController(autoPlay: false);
    addTearDown(controller.dispose);

    for (final alignment in const [
      Alignment.topLeft,
      Alignment.topCenter,
      Alignment.topRight,
      Alignment.centerLeft,
      Alignment.center,
      Alignment.centerRight,
      Alignment.bottomLeft,
      Alignment.bottomCenter,
      Alignment.bottomRight,
      Alignment(-1.0, 0.0),
    ]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: AnimatedSvgPicture.string(
              _squareSvg,
              controller: controller,
              width: 120,
              height: 60,
              fit: BoxFit.contain,
              alignment: alignment,
            ),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(find.byType(CustomPaint).first);
      expect((paint.painter! as AnimatedSvgPainter).alignment, alignment);
    }
  });

  testWidgets('AlignmentDirectional resolves against Directionality', (
    tester,
  ) async {
    final controller = AnimatedSvgController(autoPlay: false);
    addTearDown(controller.dispose);

    Future<void> pumpDir(TextDirection dir) {
      return tester.pumpWidget(
        Directionality(
          textDirection: dir,
          child: Center(
            child: AnimatedSvgPicture.string(
              _squareSvg,
              controller: controller,
              width: 120,
              height: 60,
              fit: BoxFit.contain,
              alignment: AlignmentDirectional.centerStart,
            ),
          ),
        ),
      );
    }

    await pumpDir(TextDirection.ltr);
    var paint = tester.widget<CustomPaint>(find.byType(CustomPaint).first);
    expect(
      (paint.painter! as AnimatedSvgPainter).alignment,
      Alignment.centerLeft,
    );

    await pumpDir(TextDirection.rtl);
    paint = tester.widget<CustomPaint>(find.byType(CustomPaint).first);
    expect(
      (paint.painter! as AnimatedSvgPainter).alignment,
      Alignment.centerRight,
    );
  });

  test(
    'alignment_banner.svg (280x64) shifts vertically for topCenter, center, and bottomCenter under BoxFit.contain in 320x200',
    () async {
      final bannerXml = File(
        'example/assets/svgs/alignment_banner.svg',
      ).readAsStringSync();
      final scene = SvgParser.compile(bannerXml);
      addTearDown(scene.dispose);
      final controller = AnimatedSvgController(autoPlay: false);
      addTearDown(controller.dispose);

      expect(scene.document.intrinsicSize, const ui.Size(280, 64));

      // Under BoxFit.contain in 320x200, destination height is 64 * (320 / 280) = 73.1428,
      // leaving ~126.86px of vertical slack so topCenter, center, and bottomCenter place pixels at different Y bands.
      for (final alignment in const [
        Alignment.topCenter,
        Alignment.center,
        Alignment.bottomCenter,
      ]) {
        final fitted = applyBoxFit(
          BoxFit.contain,
          scene.document.intrinsicSize,
          const ui.Size(320, 200),
        );
        final outRect = alignment.inscribe(
          fitted.destination,
          ui.Offset.zero & const ui.Size(320, 200),
        );
        if (alignment == Alignment.topCenter) {
          expect(outRect.top, closeTo(0.0, 1e-4));
        } else if (alignment == Alignment.center) {
          expect(
            outRect.top,
            closeTo((200.0 - fitted.destination.height) * 0.5, 1e-4),
          );
        } else if (alignment == Alignment.bottomCenter) {
          expect(
            outRect.bottom,
            closeTo(200.0, 1e-4),
          );
        }

        final painter = AnimatedSvgPainter(
          scene: scene,
          controller: controller,
          fit: BoxFit.contain,
          alignment: alignment,
        );
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        painter.paint(canvas, const ui.Size(320, 200));
        recorder.endRecording().dispose();
      }
    },
  );

  test(
    'alignment_badge.svg (110x70) shifts in all 9 grid positions (both X and Y) under BoxFit.scaleDown in 320x200',
    () {
      final badgeXml = File(
        'example/assets/svgs/alignment_badge.svg',
      ).readAsStringSync();
      final scene = SvgParser.compile(badgeXml);
      addTearDown(scene.dispose);
      final controller = AnimatedSvgController(autoPlay: false);
      addTearDown(controller.dispose);

      expect(scene.document.intrinsicSize, const ui.Size(110, 70));

      final fitted = applyBoxFit(
        BoxFit.scaleDown,
        scene.document.intrinsicSize,
        const ui.Size(320, 200),
      );
      expect(fitted.destination, const ui.Size(110, 70));

      final topCenterRect = Alignment.topCenter.inscribe(
        fitted.destination,
        ui.Offset.zero & const ui.Size(320, 200),
      );
      final centerRect = Alignment.center.inscribe(
        fitted.destination,
        ui.Offset.zero & const ui.Size(320, 200),
      );
      final bottomCenterRect = Alignment.bottomCenter.inscribe(
        fitted.destination,
        ui.Offset.zero & const ui.Size(320, 200),
      );

      expect(topCenterRect.left, closeTo(105.0, 1e-4));
      expect(topCenterRect.top, closeTo(0.0, 1e-4));
      expect(centerRect.left, closeTo(105.0, 1e-4));
      expect(centerRect.top, closeTo(65.0, 1e-4));
      expect(bottomCenterRect.left, closeTo(105.0, 1e-4));
      expect(bottomCenterRect.top, closeTo(130.0, 1e-4));

      for (final alignment in const [
        Alignment.topLeft,
        Alignment.topCenter,
        Alignment.topRight,
        Alignment.centerLeft,
        Alignment.center,
        Alignment.centerRight,
        Alignment.bottomLeft,
        Alignment.bottomCenter,
        Alignment.bottomRight,
      ]) {
        final painter = AnimatedSvgPainter(
          scene: scene,
          controller: controller,
          fit: BoxFit.scaleDown,
          alignment: alignment,
        );
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        painter.paint(canvas, const ui.Size(320, 200));
        recorder.endRecording().dispose();
      }
    },
  );

  testWidgets(
    'default Alignment.center matches prior centered-fit visual contract',
    (tester) async {
      final controller = AnimatedSvgController(autoPlay: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: AnimatedSvgPicture.string(
              _squareSvg,
              controller: controller,
              width: 200,
              height: 80,
              // omit alignment → default center
              fit: BoxFit.contain,
            ),
          ),
        ),
      );

      final paint = tester.widget<CustomPaint>(find.byType(CustomPaint).first);
      final painter = paint.painter! as AnimatedSvgPainter;
      expect(painter.alignment, Alignment.center);
      expect(painter.fit, BoxFit.contain);
    },
  );
}
