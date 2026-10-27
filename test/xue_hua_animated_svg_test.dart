import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

class _MemorySvgAssetBundle extends CachingAssetBundle {
  final Map<String, String> assets;

  _MemorySvgAssetBundle(this.assets);

  @override
  Future<ByteData> load(String key) async {
    final content = assets[key];
    if (content == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    final bytes = Uint8List.fromList(content.codeUnits);
    return ByteData.view(bytes.buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final content = assets[key];
    if (content == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return content;
  }
}

void main() {
  group('Phase 1: High-Performance AST, ViewBox, Nodes & Picture Caching', () {
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

      expect(staticBackdrop.cachedPicture, isNull);

      // Paint frame 0 -> staticBackdrop records and caches a ui.Picture
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      doc.paint(canvas, const ui.Size(240, 240));
      recorder.endRecording().dispose();

      final firstCachedPicture = staticBackdrop.cachedPicture;
      expect(firstCachedPicture, isNotNull);
      expect(growingRing.cachedPicture, isNull);

      // Painting a subsequent frame reuses the exact same cached ui.Picture instance
      scene.timeline.seekMicroseconds(500000);
      final recorder2 = ui.PictureRecorder();
      final canvas2 = ui.Canvas(recorder2);
      doc.paint(canvas2, const ui.Size(240, 240));
      recorder2.endRecording().dispose();
      expect(
        identical(staticBackdrop.cachedPicture, firstCachedPicture),
        isTrue,
      );

      scene.dispose();
      expect(staticBackdrop.cachedPicture, isNull);
    });

    test('computes preserveAspectRatio matrices across all alignments and meet/slice modes', () {
      final matrix = SvgMatrixMath.createIdentity();

      // 1. xMidYMid meet (default)
      const SvgPreserveAspectRatio(
        align: SvgAspectRatioAlign.xMidYMid,
        meetOrSlice: SvgMeetOrSlice.meet,
      ).computeMatrixInPlace(
        const ui.Rect.fromLTWH(0, 0, 100, 100),
        const ui.Size(200, 400),
        matrix,
      );
      expect(matrix[0], closeTo(2.0, 1e-6));
      expect(matrix[5], closeTo(2.0, 1e-6));
      expect(matrix[12], closeTo(0.0, 1e-6));
      expect(matrix[13], closeTo(100.0, 1e-6));

      // 2. xMaxYMax slice
      const SvgPreserveAspectRatio(
        align: SvgAspectRatioAlign.xMaxYMax,
        meetOrSlice: SvgMeetOrSlice.slice,
      ).computeMatrixInPlace(
        const ui.Rect.fromLTWH(10, 20, 100, 100),
        const ui.Size(200, 400),
        matrix,
      );
      // scale = max(2, 4) = 4.0, spareX = 200 - 400 = -200, spareY = 0
      expect(matrix[0], closeTo(4.0, 1e-6));
      expect(matrix[5], closeTo(4.0, 1e-6));
      expect(matrix[12], closeTo(-200.0 - 10.0 * 4.0, 1e-6));
      expect(matrix[13], closeTo(0.0 - 20.0 * 4.0, 1e-6));

      // 3. none (non-uniform stretch)
      const SvgPreserveAspectRatio(align: SvgAspectRatioAlign.none)
          .computeMatrixInPlace(
            const ui.Rect.fromLTWH(0, 0, 100, 50),
            const ui.Size(300, 200),
            matrix,
          );
      expect(matrix[0], closeTo(3.0, 1e-6));
      expect(matrix[5], closeTo(4.0, 1e-6));
    });

    test('supports all geometry primitives, defs, use with style override, clipPath, and fill-rule', () {
      const svg = '''
<svg viewBox="0 0 200 200" width="100%" height="100%">
  <defs>
    <circle id="templateDot" cx="0" cy="0" r="8" />
    <clipPath id="halfClip">
      <rect x="0" y="0" width="100" height="200" transform="translate(10, 0)" />
    </clipPath>
  </defs>
  <g id="shapesGroup" clip-path="url(#halfClip)" opacity="0.85">
    <rect id="r1" x="10" y="12" width="50" height="30" rx="6" ry="6" fill="#FF0000" />
    <circle id="c1" cx="40" cy="70" r="15" fill="rgb(0, 255, 0)" />
    <ellipse id="e1" cx="50" cy="110" rx="25" ry="12" fill="rgba(0, 0, 255, 0.5)" />
    <line id="l1" x1="10" y1="140" x2="90" y2="155" stroke="gold" stroke-width="3" />
    <polyline id="pl1" points="10,160 30,175 50,160" fill="none" stroke="#00FFFF" />
    <polygon id="pg1" points="70,160 90,160 80,180" fill="#FF00FF" fill-rule="evenodd" />
    <use id="u1" href="#templateDot" x="30" y="30" fill="#123456">
      <animate attributeName="x" from="30" to="80" dur="1s" fill="freeze" />
    </use>
  </g>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final doc = scene.document;

      expect(doc.intrinsicSize, equals(const ui.Size(200, 200)));
      expect(doc.clipPathsById['halfClip'], isNotNull);
      expect(doc.elementsById['r1'], isA<SvgRectNode>());
      expect(doc.elementsById['c1'], isA<SvgCircleNode>());
      expect(doc.elementsById['e1'], isA<SvgEllipseNode>());
      expect(doc.elementsById['l1'], isA<SvgLineNode>());
      expect(doc.elementsById['pl1'], isA<SvgPolyNode>());
      expect(doc.elementsById['pg1'], isA<SvgPolyNode>());

      final pg1 = doc.elementsById['pg1'] as SvgPolyNode;
      expect(pg1.style.currentFillRule, equals(ui.PathFillType.evenOdd));

      final u1 = doc.elementsById['u1'] as SvgUseNode;
      scene.timeline.seekMicroseconds(500000);
      expect(u1.currentX, closeTo(55.0, 1e-4));

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      doc.paint(canvas, const ui.Size(200, 200));
      recorder.endRecording().dispose();

      scene.dispose();
    });

    test('parses all SVG path commands (M/m, L/l, H/h, V/v, C/c, S/s, Q/q, T/t, A/a, Z/z) and scientific notation', () {
      const d =
          'M 10,10 l 20,0 H 50 h 10 V 30 v 10 '
          'C 60,50 70,50 80,40 S 100,30 110,40 '
          'c 5,5 10,5 15,0 s 10,-5 15,0 '
          'Q 150,20 160,40 T 180,40 '
          'q 5,-10 10,0 t 10,0 '
          'A 25,25 -30 01220,20 a 1e1,1.5e1 0 1010,10 z';
      final parsed = SvgPathParser.parse(d);
      expect(parsed.commands.first, equals(SvgPathCmdType.moveTo));
      expect(parsed.commands.last, equals(SvgPathCmdType.close));
      expect(parsed.commands.contains(SvgPathCmdType.cubicTo), isTrue);
      expect(parsed.commands.contains(SvgPathCmdType.quadTo), isTrue);
      expect(parsed.commands.contains(SvgPathCmdType.arcTo), isTrue);

      final path = ui.Path();
      parsed.buildUiPath(path);
      expect(path.getBounds().width, greaterThan(100.0));
    });
  });

  group('Phase 2: Gradients, Timeline Timing & SMIL Core Interpolators', () {
    test('supports linearGradient and radialGradient template inheritance, focal points, and animated coordinates', () {
      const svg = '''
<svg viewBox="0 0 100 100">
  <defs>
    <linearGradient id="baseStops">
      <stop offset="0%" stop-color="#FF0000" stop-opacity="0.5">
        <animate attributeName="stop-opacity" values="0.5;1.0" dur="1s" fill="freeze" />
      </stop>
      <stop offset="100%" stop-color="#0000FF" />
    </linearGradient>
    <radialGradient id="radGrad" href="#baseStops" gradientUnits="userSpaceOnUse"
      cx="50" cy="50" r="30" fx="40" fy="40" spreadMethod="repeat">
      <animate attributeName="r" from="30" to="50" dur="1s" fill="freeze" />
      <animate attributeName="fx" from="40" to="60" dur="1s" fill="freeze" />
    </radialGradient>
  </defs>
  <circle id="c" cx="50" cy="50" r="45" fill="url(#radGrad)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final radGrad =
          scene.document.gradientsById['radGrad'] as SvgRadialGradientNode;
      final c = scene.document.elementsById['c']!;

      expect(radGrad.stops.length, equals(2));
      expect(radGrad.isAnimated, isTrue);
      expect(c.isAnimated, isTrue);

      scene.timeline.seekMicroseconds(500000);
      expect(radGrad.currentR, closeTo(40.0, 1e-4));
      expect(radGrad.currentFx, closeTo(50.0, 1e-4));
      expect(radGrad.stops.first.currentOpacity, closeTo(0.75, 1e-4));

      final shader = radGrad.createShader(c.cachedBounds);
      expect(shader, isNotNull);
      scene.dispose();
    });

    test('handles calcMode discrete, linear, paced, spline, multiple begin offsets, end, and fill remove vs freeze', () {
      const svg = '''
<svg viewBox="0 0 100 100">
  <rect id="discreteRect" x="0" y="0" width="20" height="20">
    <animate attributeName="x" values="10;50;90" keyTimes="0;0.5;1"
      calcMode="discrete" dur="1s" fill="freeze" />
  </rect>
  <rect id="pacedRect" x="0" y="25" width="20" height="20">
    <animate attributeName="x" values="0;10;100"
      calcMode="paced" dur="1s" fill="freeze" />
  </rect>
  <rect id="multiBeginRect" x="5" y="50" width="20" height="20">
    <animate attributeName="x" from="10" to="60"
      begin="0.5s; 2s" end="2.5s" dur="1s" fill="remove" />
  </rect>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final discreteRect =
          scene.document.elementsById['discreteRect'] as SvgRectNode;
      final pacedRect = scene.document.elementsById['pacedRect'] as SvgRectNode;
      final multiBeginRect =
          scene.document.elementsById['multiBeginRect'] as SvgRectNode;

      // At t = 0.25s: discrete is at first value (10), paced is at 25% of total distance 100 -> 25.0
      // multiBeginRect has not started yet (begin=0.5s) -> stays at baseX = 5
      scene.timeline.seekMicroseconds(250000);
      expect(discreteRect.currentX, closeTo(10.0, 1e-4));
      expect(pacedRect.currentX, closeTo(25.0, 1e-4));
      expect(multiBeginRect.currentX, closeTo(5.0, 1e-4));

      // At t = 0.6s: discrete is at second value (50), multiBeginRect is 0.1s into [0.5s, 1.5s] -> 15.0
      scene.timeline.seekMicroseconds(600000);
      expect(discreteRect.currentX, closeTo(50.0, 1e-4));
      expect(multiBeginRect.currentX, closeTo(15.0, 1e-4));

      // At t = 1.6s: multiBeginRect first run ended and fill="remove" -> back to baseX = 5.0
      scene.timeline.seekMicroseconds(1600000);
      expect(multiBeginRect.currentX, closeTo(5.0, 1e-4));

      // At t = 2.25s: multiBeginRect second run [2.0s..2.5s] is at 0.25s -> 22.5
      scene.timeline.seekMicroseconds(2250000);
      expect(multiBeginRect.currentX, closeTo(22.5, 1e-4));

      // At t = 2.6s: past explicit end="2.5s" with fill="remove" -> back to 5.0
      scene.timeline.seekMicroseconds(2600000);
      expect(multiBeginRect.currentX, closeTo(5.0, 1e-4));

      scene.dispose();
    });

    test('supports skewX, skewY, by-animations, and parent-to-child animated style inheritance', () {
      const svg = '''
<svg viewBox="0 0 100 100">
  <g id="parentGroup" fill="#FF0000" stroke-width="2">
    <animate attributeName="fill" to="#00FF00" dur="1s" fill="freeze" />
    <animate attributeName="stroke-width" by="6" dur="1s" fill="freeze" />
    <rect id="childRect" x="10" y="10" width="30" height="30" stroke="#000000">
      <animateTransform attributeName="transform" type="skewX" from="0" to="45" dur="1s" fill="freeze" />
      <animateTransform attributeName="transform" type="skewY" from="0" to="45" dur="1s" additive="sum" fill="freeze" />
    </rect>
  </g>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final parentGroup = scene.document.elementsById['parentGroup']!;
      final childRect = scene.document.elementsById['childRect']!;

      scene.timeline.seekMicroseconds(1000000);
      expect(
        parentGroup.style.currentFillColor.toARGB32(),
        equals(const ui.Color(0xFF00FF00).toARGB32()),
      );
      expect(parentGroup.style.currentStrokeWidth, closeTo(8.0, 1e-4));

      // Paint to trigger parent-to-child animated style synchronization
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      recorder.endRecording().dispose();

      expect(
        childRect.style.currentFillColor.toARGB32(),
        equals(const ui.Color(0xFF00FF00).toARGB32()),
      );
      expect(childRect.style.currentStrokeWidth, closeTo(8.0, 1e-4));
      // tan(45 deg) = 1.0 in skewX and skewY
      expect(childRect.transformMatrix[4], closeTo(1.0, 1e-4));
      expect(childRect.transformMatrix[1], closeTo(1.0, 1e-4));

      scene.dispose();
    });
  });

  group(
    'Phase 3: CSS Selectors, @keyframes, Blur Filter & transform-origin',
    () {
      test('enforces CSS selector specificity (#id > .class > tag) and inline style override', () {
        const svg = '''
<svg viewBox="0 0 100 100">
  <style>
    rect { fill: #111111; stroke-width: 1px; }
    .highlight { fill: #222222; stroke-width: 4px; }
    #special { fill: #333333; }
  </style>
  <rect id="special" class="highlight" x="0" y="0" width="50" height="50" style="opacity: 0.75;" />
</svg>
''';
        final scene = SvgParser.compile(svg);
        final special = scene.document.elementsById['special']!;
        expect(
          special.style.currentFillColor.toARGB32(),
          equals(const ui.Color(0xFF333333).toARGB32()),
        );
        expect(special.style.currentStrokeWidth, closeTo(4.0, 1e-5));
        expect(special.style.currentOpacity, closeTo(0.75, 1e-5));
        scene.dispose();
      });

      test('compiles @keyframes with alternate direction, backwards/both fill-mode, blur filter, and keyword transform-origin', () {
        const svg = '''
<svg viewBox="0 0 200 200">
  <style>
    #card {
      transform-origin: bottom right;
      animation: pulseBlur 1s linear 0.5s 2 alternate both;
    }
    @keyframes pulseBlur {
      from {
        transform: scale(0.5);
        filter: blur(2px);
      }
      to {
        transform: scale(1.5);
        filter: blur(10px);
      }
    }
  </style>
  <rect id="card" x="20" y="40" width="80" height="60" fill="#00F5D4" />
</svg>
''';
        final scene = SvgParser.compile(svg);
        final card = scene.document.elementsById['card']!;

        // Bounds are (20, 40) -> (100, 100), so "bottom right" anchor is (100, 100)
        // Before delay (t = 0.2s): backwards fill applies 0% keyframe (scale 0.5, blur 2px)
        scene.timeline.seekMicroseconds(200000);
        expect(card.style.currentBlurSigma, closeTo(2.0, 1e-4));
        expect(card.transformMatrix[0], closeTo(0.5, 1e-4));
        // Point (100, 100) is fixed under scale around (100, 100):
        final m = card.transformMatrix;
        expect(m[0] * 100.0 + m[4] * 100.0 + m[12], closeTo(100.0, 1e-4));
        expect(m[1] * 100.0 + m[5] * 100.0 + m[13], closeTo(100.0, 1e-4));

        // At t = 1.0s (0.5s into cycle 0): halfway -> scale 1.0, blur 6px
        scene.timeline.seekMicroseconds(1000000);
        expect(card.style.currentBlurSigma, closeTo(6.0, 1e-4));
        expect(card.transformMatrix[0], closeTo(1.0, 1e-4));

        // At t = 1.5s (end of cycle 0 / start of alternate reverse cycle 1): scale 1.5, blur 10px
        scene.timeline.seekMicroseconds(1500000);
        expect(card.style.currentBlurSigma, closeTo(10.0, 1e-4));
        expect(card.transformMatrix[0], closeTo(1.5, 1e-4));

        // At t = 3.0s (after 2 alternate cycles complete, fill-mode: both): frozen at end of cycle 1 (0% state)
        scene.timeline.seekMicroseconds(3000000);
        expect(card.style.currentBlurSigma, closeTo(2.0, 1e-4));
        expect(card.transformMatrix[0], closeTo(0.5, 1e-4));

        scene.dispose();
      });
    },
  );

  group('Phase 4: Stroke Dash Animation, <animateMotion>, Path Morphing & Real Assets', () {
    test('normalizes odd-length stroke-dasharray keyframes via LCM and wraps negative dashoffset', () {
      const svg = '''
<svg viewBox="0 0 100 100">
  <line id="dashLine" x1="0" y1="50" x2="100" y2="50"
    stroke="#00FF00" stroke-width="4" pathLength="50"
    stroke-dasharray="5" stroke-dashoffset="-25">
    <animate attributeName="stroke-dasharray" values="5; 10 20 30" dur="1s" fill="freeze" />
  </line>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final dashLine = scene.document.elementsById['dashLine'] as SvgLineNode;

      // "5" (odd len 1 -> even 2) and "10 20 30" (odd len 3 -> even 6) -> LCM length is 6
      scene.timeline.seekMicroseconds(500000);
      final dash = dashLine.style.currentStrokeDasharray!;
      expect(dash.length, equals(6));
      expect(dash[0], closeTo(7.5, 1e-4)); // lerp(5, 10, 0.5)
      expect(dash[1], closeTo(12.5, 1e-4)); // lerp(5, 20, 0.5)
      expect(dash[2], closeTo(17.5, 1e-4)); // lerp(5, 30, 0.5)

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      recorder.endRecording().dispose();
      expect(dashLine.dashedStrokePath.computeMetrics().isNotEmpty, isTrue);
      scene.dispose();
    });

    test('supports <animateMotion> with inline path, values/from/to, auto-reverse, and keyPoints', () {
      const svg = '''
<svg viewBox="0 0 200 200">
  <circle id="runner1" r="5" fill="#FF0000">
    <animateMotion path="M 0 0 L 100 0" dur="1s" rotate="auto-reverse"
      keyPoints="1;0" keyTimes="0;1" calcMode="linear" fill="freeze" />
  </circle>
  <circle id="runner2" r="5" fill="#00FF00">
    <animateMotion from="10,20" to="90,100" dur="1s" rotate="45deg" fill="freeze" />
  </circle>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final runner1 = scene.document.elementsById['runner1']!;
      final runner2 = scene.document.elementsById['runner2']!;

      // At t = 0.25s: runner1 has keyPoints="1;0" -> at 75% of (0,0)->(100,0) = (75, 0)
      // with auto-reverse tangent (180 deg -> cos = -1)
      scene.timeline.seekMicroseconds(250000);
      expect(runner1.motionMatrix[12], closeTo(75.0, 1e-3));
      expect(runner1.motionMatrix[0], closeTo(-1.0, 1e-3));

      // runner2 at t = 0.5s -> halfway between (10, 20) and (90, 100) = (50, 60)
      scene.timeline.seekMicroseconds(500000);
      expect(runner2.motionMatrix[12], closeTo(50.0, 1e-3));
      expect(runner2.motionMatrix[13], closeTo(60.0, 1e-3));

      scene.dispose();
    });

    test('compiles and animates example/assets/svgs/elephant.svg, solar_orbit.svg, and neon_equalizer.svg smoothly', () {
      final elephantXml = File('example/assets/svgs/elephant.svg')
          .readAsStringSync();
      final elephantScene = SvgParser.compile(elephantXml);

      expect(
        elephantScene.document.intrinsicSize,
        equals(const ui.Size(1080, 1080)),
      );
      expect(elephantScene.timeline.hasAnimations, isTrue);
      expect(
        elephantScene.timeline.cycleDuration,
        equals(const Duration(seconds: 2)),
      );

      final sceneScale = elephantScene.document.elementsById['scene-scale']!;
      final rotatingCard =
          elephantScene.document.elementsById['rotating-card']!;
      final elephantMotion =
          elephantScene.document.elementsById['elephant-motion']!;

      // Sample across multiple timestamps in the 2-second cycle and paint each frame
      for (final us in [0, 416200, 1000000, 1415200, 2000000]) {
        elephantScene.timeline.seekMicroseconds(us);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        elephantScene.document.paint(canvas, const ui.Size(300, 300));
        recorder.endRecording().dispose();
      }

      // At t = 1.0s (50% of 2s): scene-scale is 0.9 around (540, 540), rotating-card is at 45 deg
      elephantScene.timeline.seekMicroseconds(1000000);
      expect(sceneScale.transformMatrix[0], closeTo(0.9, 1e-3));
      expect(SvgMatrixMath.isIdentity(rotatingCard.transformMatrix), isFalse);

      // At t = 0.4162s (keyTime 0.2081): elephant-motion translates Y by 44
      elephantScene.timeline.seekMicroseconds(416200);
      expect(elephantMotion.transformMatrix[13], closeTo(44.0, 0.5));

      elephantScene.dispose();

      // Also verify solar_orbit.svg and neon_equalizer.svg compile and paint cleanly
      for (final path in [
        'example/assets/svgs/solar_orbit.svg',
        'example/assets/svgs/neon_equalizer.svg',
      ]) {
        final xml = File(path).readAsStringSync();
        final scene = SvgParser.compile(xml);
        expect(scene.timeline.hasAnimations, isTrue);
        scene.timeline.seekMicroseconds(600000);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        scene.document.paint(canvas, const ui.Size(260, 260));
        recorder.endRecording().dispose();
        scene.dispose();
      }
    });
  });

  group('Phase 5: AnimatedSvgController & AnimatedSvgPicture Widget (.string, .asset, .compiled)', () {
    testWidgets(
      'renders AnimatedSvgPicture.string, .asset, and .compiled and responds to controller commands',
      (tester) async {
        final controller = AnimatedSvgController(autoPlay: false);
        final elephantXml = File('example/assets/svgs/elephant.svg')
            .readAsStringSync();
        final bundle = _MemorySvgAssetBundle({
          'assets/svgs/elephant.svg': elephantXml,
        });

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: AnimatedSvgPicture.asset(
                'assets/svgs/elephant.svg',
                bundle: bundle,
                controller: controller,
                width: 240,
                height: 240,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AnimatedSvgPicture), findsOneWidget);
        expect(controller.isPlaying, isFalse);
        expect(controller.cycleDuration, equals(const Duration(seconds: 2)));

        controller.seek(const Duration(milliseconds: 1000));
        await tester.pump();
        expect(controller.elapsed, equals(const Duration(milliseconds: 1000)));
        expect(controller.cycleProgress, closeTo(0.5, 1e-4));

        controller.setSpeed(2.0);
        expect(controller.speed, equals(2.0));

        controller.play();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          controller.elapsedMicroseconds,
          greaterThan(const Duration(milliseconds: 1000).inMicroseconds),
        );

        controller.pause();
        expect(controller.isPlaying, isFalse);

        controller.reset();
        expect(controller.elapsed, equals(Duration.zero));

        // Switch to AnimatedSvgPicture.compiled
        final compiledScene = SvgParser.compile(
          AnimatedSvgShowcasePresets.cyberCoreCompositeSvg,
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: AnimatedSvgPicture.compiled(
                compiledScene,
                controller: controller,
                width: 240,
                height: 240,
              ),
            ),
          ),
        );
        await tester.pump();

        compiledScene.dispose();
        controller.dispose();
      },
    );
  });
}
