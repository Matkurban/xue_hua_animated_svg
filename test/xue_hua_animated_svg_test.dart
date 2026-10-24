import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

void main() {
  group('Phase 1: High-Performance AST & Static Subtree Picture Caching', () {
    test('bubbles isAnimated dirty flag bottom-up and caches static subtrees into ui.Picture', () {
      final scene = SvgParser.compile(
        AnimatedSvgShowcasePresets.cyberCoreCompositeSvg,
      );
      final doc = scene.document;

      final staticBackdrop = doc.elementsById['staticBackdrop']!;
      final growingRing = doc.elementsById['growingStrokeRing']!;
      final css3dGroup = doc.elementsById['css3dGroup']!;
      final morphingCore = doc.elementsById['morphingCore']!;
      final orbitingProbe = doc.elementsById['orbitingProbe']!;

      expect(staticBackdrop.isAnimated, isFalse);
      expect(growingRing.isAnimated, isTrue);
      expect(css3dGroup.isAnimated, isTrue);
      expect(morphingCore.isAnimated, isTrue);
      expect(orbitingProbe.isAnimated, isTrue);
      expect(doc.rootGroup.isAnimated, isTrue);

      // Before first paint, cachedPicture is null
      expect(staticBackdrop.cachedPicture, isNull);

      // Paint frame 0 -> staticBackdrop records and caches a ui.Picture
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      doc.paint(canvas, const ui.Size(240, 240));
      recorder.endRecording().dispose();

      expect(staticBackdrop.cachedPicture, isNotNull);
      expect(growingRing.cachedPicture, isNull);

      scene.dispose();
      expect(staticBackdrop.cachedPicture, isNull);
    });

    test('computes viewBox preserveAspectRatio matrix accurately', () {
      const par = SvgPreserveAspectRatio(
        align: SvgAspectRatioAlign.xMidYMid,
        meetOrSlice: SvgMeetOrSlice.meet,
      );
      final matrix = SvgMatrixMath.createIdentity();
      par.computeMatrixInPlace(
        const ui.Rect.fromLTWH(0, 0, 100, 100),
        const ui.Size(200, 400),
        matrix,
      );
      // Uniform scale = 2.0, X offset = 0, Y offset = (400 - 200)/2 = 100
      expect(matrix[0], closeTo(2.0, 1e-6));
      expect(matrix[5], closeTo(2.0, 1e-6));
      expect(matrix[12], closeTo(0.0, 1e-6));
      expect(matrix[13], closeTo(100.0, 1e-6));
    });
  });

  group('Phase 2: Precompiled Timeline & SMIL Interpolators', () {
    test('interpolates scalar, color, gradient stops, and additive animateTransform with Cubic keySplines', () {
      const svg = '''
<svg viewBox="0 0 100 100">
  <defs>
    <linearGradient id="g1">
      <stop id="s1" offset="0%" stop-color="#000000">
        <animate attributeName="offset" values="0;1" dur="2s" fill="freeze" />
        <animate attributeName="stop-color" values="#000000;#FFFFFF" dur="2s" fill="freeze" />
      </stop>
    </linearGradient>
  </defs>
  <rect id="box" x="10" y="10" width="40" height="40" fill="url(#g1)" opacity="0.2">
    <animate attributeName="opacity" from="0.2" to="1.0" dur="2s"
      calcMode="spline" keyTimes="0;1" keySplines="0.42 0 0.58 1" fill="freeze" />
    <animateTransform attributeName="transform" type="translate"
      from="0 0" to="20 40" dur="2s" fill="freeze" />
    <animateTransform attributeName="transform" type="scale"
      from="1 1" to="2 2" dur="2s" additive="sum" fill="freeze" />
  </rect>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final box = scene.document.elementsById['box']!;
      final grad = scene.document.gradientsById['g1']!;

      // Halfway at 1.0s (1,000,000 us)
      scene.timeline.seekMicroseconds(1000000);
      expect(box.style.currentOpacity, closeTo(0.6, 1e-3));
      expect(grad.stops.first.currentOffset, closeTo(0.5, 1e-3));
      // Translate(10, 20) * Scale(1.5, 1.5)
      expect(box.transformMatrix[12], closeTo(10.0, 1e-4));
      expect(box.transformMatrix[13], closeTo(20.0, 1e-4));
      expect(box.transformMatrix[0], closeTo(1.5, 1e-4));
      expect(box.transformMatrix[5], closeTo(1.5, 1e-4));

      // After 2.5s -> frozen at end state
      scene.timeline.seekMicroseconds(2500000);
      expect(box.style.currentOpacity, closeTo(1.0, 1e-4));
      expect(grad.stops.first.currentOffset, closeTo(1.0, 1e-4));
      expect(
        grad.stops.first.currentColor.toARGB32(),
        equals(const ui.Color(0xFFFFFFFF).toARGB32()),
      );
      scene.dispose();
    });
  });

  group('Phase 3: CSS @keyframes Precompiler & transform-origin Alignment', () {
    test('compiles @keyframes and resolves percentage transform-origin against node bounds', () {
      const svg = '''
<svg viewBox="0 0 200 200">
  <style>
    #spinner {
      transform-origin: 50% 50%;
      animation: spin 2s linear infinite;
    }
    @keyframes spin {
      0% { transform: rotate(0deg); opacity: 0.5; }
      50% { transform: rotate(90deg); opacity: 1.0; }
      100% { transform: rotate(180deg); opacity: 0.5; }
    }
  </style>
  <rect id="spinner" x="50" y="50" width="100" height="100" fill="#FF0000" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final spinner = scene.document.elementsById['spinner']!;

      // Bounds of spinner are (50, 50) -> (150, 150), so 50% 50% center is (100, 100)
      expect(
        spinner.cachedBounds,
        equals(const ui.Rect.fromLTWH(50, 50, 100, 100)),
      );

      // Seek to 1.0s (50% keyframe -> 90 deg rotation around (100, 100))
      scene.timeline.seekMicroseconds(1000000);
      expect(spinner.style.currentOpacity, closeTo(1.0, 1e-5));

      // Verify point (50, 50) rotated +90 deg around (100, 100) maps to (150, 50)
      final m = spinner.transformMatrix;
      final xOut = m[0] * 50.0 + m[4] * 50.0 + m[12];
      final yOut = m[1] * 50.0 + m[5] * 50.0 + m[13];
      expect(xOut, closeTo(150.0, 1e-4));
      expect(yOut, closeTo(50.0, 1e-4));
      scene.dispose();
    });
  });

  group('Phase 4: Stroke Dash Animation, <animateMotion>, and Isomorphic Path Morphing', () {
    test('handles stroke-dasharray with pathLength normalization, <animateMotion rotate="auto">, and d morphing', () {
      final scene = SvgParser.compile(
        AnimatedSvgShowcasePresets.cyberCoreCompositeSvg,
      );
      final morphNode =
          scene.document.elementsById['morphingCore'] as SvgPathNode;
      final probeNode = scene.document.elementsById['orbitingProbe']!;
      final ringNode =
          scene.document.elementsById['growingStrokeRing'] as SvgGeometryNode;

      expect(ringNode.cachedMetrics, isNotNull);
      expect(ringNode.totalPathLength, greaterThan(500.0));

      // Advance to 1.4s (halfway through 2.8s morph cycle)
      scene.timeline.seekMicroseconds(1400000);
      expect(morphNode.isMorphed, isTrue);
      expect(morphNode.morphedCoords[1], closeTo(92.0, 1e-3));

      // Orbiting probe should have non-identity motionMatrix from <animateMotion>
      expect(SvgMatrixMath.isIdentity(probeNode.motionMatrix), isFalse);

      // Render at 1.4s to verify dashed path extraction and morphing draw cleanly
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(240, 240));
      recorder.endRecording().dispose();

      expect(ringNode.dashedStrokePath.computeMetrics().isNotEmpty, isTrue);
      scene.dispose();
    });
  });

  group('Phase 5: AnimatedSvgController & AnimatedSvgPicture Widget', () {
    testWidgets(
      'renders AnimatedSvgPicture and responds to play, pause, seek, reset, and setSpeed',
      (tester) async {
        final controller = AnimatedSvgController(autoPlay: false);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: AnimatedSvgPicture.string(
                AnimatedSvgShowcasePresets.cyberCoreCompositeSvg,
                controller: controller,
                width: 240,
                height: 240,
              ),
            ),
          ),
        );

        expect(find.byType(AnimatedSvgPicture), findsOneWidget);
        expect(controller.isPlaying, isFalse);

        controller.seek(const Duration(milliseconds: 1500));
        await tester.pump();
        expect(controller.elapsed, equals(const Duration(milliseconds: 1500)));

        controller.setSpeed(2.0);
        expect(controller.speed, equals(2.0));

        controller.play();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          controller.elapsedMicroseconds,
          greaterThan(const Duration(milliseconds: 1500).inMicroseconds),
        );

        controller.pause();
        expect(controller.isPlaying, isFalse);

        controller.reset();
        expect(controller.elapsed, equals(Duration.zero));

        controller.dispose();
      },
    );
  });
}
