import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

void main() {
  group('SVG <text>, <tspan>, <textPath> specification compliance', () {
    test(
      'compiles and paints example/assets/svgs/text_svg.svg with stroke, rotation, and static picture caching',
      () async {
        final xml = File('example/assets/svgs/text_svg.svg').readAsStringSync();
        final scene = SvgParser.compile(xml);
        final doc = scene.document;

        expect(doc.viewBox, equals(const ui.Rect.fromLTWH(0, 0, 800, 800)));
        expect(doc.rootGroup.children.length, equals(1));
        expect(doc.rootGroup.children.first, isA<SvgTextNode>());

        final textNode = doc.rootGroup.children.first as SvgTextNode;
        expect(textNode.style.currentFontSize, closeTo(90.0, 1e-6));
        expect(textNode.style.currentFontFamily, equals('monospace'));
        expect(textNode.style.currentFontWeight, equals(ui.FontWeight.w700));
        expect(textNode.style.currentTextAnchor, equals(SvgTextAnchor.middle));
        expect(
          textNode.style.currentDominantBaseline,
          equals(SvgDominantBaseline.middle),
        );
        expect(textNode.style.resolvedFill.isVisible, isFalse);
        expect(textNode.style.resolvedStroke.isVisible, isTrue);
        expect(
          textNode.style.currentStrokeColor.toARGB32(),
          equals(const ui.Color(0xFFFF574D).toARGB32()),
        );
        expect(textNode.style.currentStrokeWidth, closeTo(4.0, 1e-6));
        expect(textNode.cachedBounds.width, greaterThan(0.0));
        expect(textNode.cachedBounds.height, greaterThan(0.0));
        expect(SvgMatrixMath.isIdentity(textNode.baseTransformMatrix), isFalse);
        expect(textNode.isAnimated, isFalse);

        // Paint to an offscreen image and verify non-transparent pixels are drawn
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        doc.paint(canvas, const ui.Size(400, 400));
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 400);
        final byteData = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(byteData, isNotNull);

        int coloredPixels = 0;
        final bytes = byteData!.buffer.asUint8List();
        for (int i = 0; i < bytes.length; i += 4) {
          if (bytes[i + 3] > 0) {
            coloredPixels++;
          }
        }
        expect(coloredPixels, greaterThan(100));

        // Verify static subtree Picture caching is active
        expect(doc.rootGroup.cachedPicture, isNotNull);

        image.dispose();
        picture.dispose();
        scene.dispose();
      },
    );

    test(
      'preserves mixed-content ordering for <text> with nested <tspan>, CSS rules, font shorthand, and xml:space',
      () {
        const svg = '''
<svg viewBox="0 0 400 200" xmlns="http://www.w3.org/2000/svg">
  <style>
    text { font: italic 24px sans-serif; fill: #222222; }
    .accent { font-weight: 700; fill: #FF0000; text-decoration: underline; }
  </style>
  <text id="mixed" x="20" y="60">
    Hello <tspan id="mid" class="accent" dy="-5">SVG</tspan> World &amp; &#x2605;!
  </text>
  <text id="preserved" x="20" y="120" xml:space="preserve">  A   B  </text>
</svg>
''';
        final scene = SvgParser.compile(svg);
        final doc = scene.document;

        final mixed = doc.elementsById['mixed'] as SvgTextNode;
        final mid = doc.elementsById['mid'] as SvgTextSpanNode;
        final preserved = doc.elementsById['preserved'] as SvgTextNode;

        expect(mixed.style.currentFontSize, closeTo(24.0, 1e-6));
        expect(mixed.style.currentFontStyle, equals(ui.FontStyle.italic));
        expect(mixed.contentItems.length, equals(3));
        expect(mixed.contentItems[0], isA<SvgTextLiteral>());
        expect(mixed.contentItems[1], same(mid));
        expect(mixed.contentItems[2], isA<SvgTextLiteral>());
        expect((mixed.contentItems[2] as SvgTextLiteral).text, contains('★'));

        expect(mid.style.currentFontWeight, equals(ui.FontWeight.w700));
        expect(
          mid.style.currentFillColor.toARGB32(),
          equals(const ui.Color(0xFFFF0000).toARGB32()),
        );
        expect(
          mid.style.currentTextDecoration,
          equals(ui.TextDecoration.underline),
        );
        expect(preserved.style.currentWhiteSpace, equals(SvgWhiteSpace.preserve));

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        doc.paint(canvas, const ui.Size(400, 200));
        recorder.endRecording().dispose();
        scene.dispose();
      },
    );

    test(
      'supports per-glyph x/y/dx/dy/rotate lists, textLength/lengthAdjust, gradients, paint-order, and <textPath>',
      () {
        const svg = '''
<svg viewBox="0 0 300 300" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="txtGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#00F5D4" />
      <stop offset="100%" stop-color="#9B5DE5" />
    </linearGradient>
    <path id="arcCurve" d="M 20 220 Q 150 120 280 220" />
  </defs>
  <text id="rotated" x="20" y="60" dx="0 4 4 4" rotate="0 -10 10"
    fill="url(#txtGrad)" stroke="#111111" stroke-width="2"
    paint-order="stroke fill" font-size="28">WAVE</text>
  <text id="stretched" x="20" y="120" textLength="200"
    lengthAdjust="spacingAndGlyphs" font-size="24">STRETCH</text>
  <text id="curved" font-size="20" fill="#333333">
    <textPath id="tp" href="#arcCurve" startOffset="50%" text-anchor="middle">
      Along the path
    </textPath>
  </text>
</svg>
''';
        final scene = SvgParser.compile(svg);
        final doc = scene.document;

        final rotated = doc.elementsById['rotated'] as SvgTextNode;
        final stretched = doc.elementsById['stretched'] as SvgTextNode;
        final tp = doc.elementsById['tp'] as SvgTextPathNode;

        expect(rotated.style.currentPaintOrder, equals(SvgPaintOrder.strokeFill));
        expect(rotated.rotateList.length, equals(3));
        expect(
          stretched.lengthAdjust,
          equals(SvgLengthAdjust.spacingAndGlyphs),
        );
        expect(tp.cachedTotalPathLength, greaterThan(200.0));

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        doc.paint(canvas, const ui.Size(300, 300));
        recorder.endRecording().dispose();
        scene.dispose();
      },
    );

    test(
      'supports SMIL <animate> and CSS @keyframes on <text> and <tspan>',
      () {
        const svg = '''
<svg viewBox="0 0 200 100" xmlns="http://www.w3.org/2000/svg">
  <text id="animText" x="10" y="50" font-size="20" fill="#FF0000">
    Animate
    <animate attributeName="x" from="10" to="90" dur="1s" fill="freeze" />
    <animate attributeName="font-size" from="20" to="40" dur="1s" fill="freeze" />
    <animate attributeName="fill" from="#FF0000" to="#0000FF" dur="1s" fill="freeze" />
  </text>
</svg>
''';
        final scene = SvgParser.compile(svg);
        final animText = scene.document.elementsById['animText'] as SvgTextNode;
        expect(animText.isAnimated, isTrue);

        scene.timeline.seekMicroseconds(500000);
        expect(animText.animatedX, closeTo(50.0, 1e-4));
        expect(animText.style.currentFontSize, closeTo(30.0, 1e-4));

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        scene.document.paint(canvas, const ui.Size(200, 100));
        recorder.endRecording().dispose();
        scene.dispose();
      },
    );
  });
}
