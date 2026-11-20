import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

void main() {
  group('Phase 1 (P0): <a>, <switch>, <set>, <animateColor>, nested <svg>, <symbol>, <use>', () {
    test('parses and renders graphic-level <a> container with style and transform inheritance', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <a id="linkGroup" href="https://example.com" target="_blank" fill="#FF0000" transform="translate(10, 10)">
    <rect id="linkRect" x="0" y="0" width="40" height="40" />
  </a>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final link = scene.document.elementsById['linkGroup'] as SvgAnchorNode;
      final rect = scene.document.elementsById['linkRect'] as SvgRectNode;

      expect(link.href, equals('https://example.com'));
      expect(link.target, equals('_blank'));
      expect(
        rect.style.currentFillColor.toARGB32(),
        equals(const ui.Color(0xFFFF0000).toARGB32()),
      );

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // Pixel at (25, 25) is inside translated [10..50, 10..50] red rect
      final idx = (25 * 100 + 25) * 4;
      expect(bytes[idx], equals(255));
      expect(bytes[idx + 1], equals(0));
      expect(bytes[idx + 2], equals(0));
      expect(bytes[idx + 3], equals(255));

      image.dispose();
      picture.dispose();
      scene.dispose();
    });

    test('evaluates <switch> and renders only the first matching conditional branch', () {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <switch id="sw">
    <rect id="extBranch" requiredExtensions="http://example.com/custom" x="0" y="0" width="100" height="100" fill="#FF0000" />
    <rect id="unmatchedLang" systemLanguage="zz-ZZ" x="0" y="0" width="100" height="100" fill="#00FF00" />
    <rect id="fallbackBranch" x="0" y="0" width="50" height="50" fill="#0000FF" />
    <rect id="neverReached" x="50" y="50" width="50" height="50" fill="#FFFF00" />
  </switch>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final sw = scene.document.elementsById['sw'] as SvgSwitchNode;
      final fallback = scene.document.elementsById['fallbackBranch']!;

      expect(sw.selectedChild, same(fallback));
      expect(sw.cachedBounds, equals(const ui.Rect.fromLTWH(0, 0, 50, 50)));

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      recorder.endRecording().dispose();
      scene.dispose();
    });

    test('supports SMIL <set> for visibility, display, fill, scalar attributes, and <animateColor>', () {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <rect id="rVis" x="0" y="0" width="20" height="20" visibility="hidden" fill="#111111">
    <set attributeName="visibility" to="visible" begin="0.5s" dur="1s" fill="remove" />
    <set attributeName="fill" to="#00FF00" begin="0.5s" fill="freeze" />
  </rect>
  <rect id="rColor" x="30" y="0" width="20" height="20" fill="#FF0000">
    <animateColor attributeName="fill" from="#FF0000" to="#0000FF" dur="1s" fill="freeze" />
  </rect>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final rVis = scene.document.elementsById['rVis'] as SvgRectNode;
      final rColor = scene.document.elementsById['rColor'] as SvgRectNode;

      // t = 0.2s: before begin="0.5s" -> rVis stays hidden & #111111
      scene.timeline.seekMicroseconds(200000);
      expect(rVis.style.visibilityHidden, isTrue);
      expect(
        rVis.style.currentFillColor.toARGB32(),
        equals(const ui.Color(0xFF111111).toARGB32()),
      );

      // t = 0.8s: active -> rVis visible & #00FF00
      scene.timeline.seekMicroseconds(800000);
      expect(rVis.style.visibilityHidden, isFalse);
      expect(
        rVis.style.currentFillColor.toARGB32(),
        equals(const ui.Color(0xFF00FF00).toARGB32()),
      );

      // t = 2.0s: visibility <set> ended with fill="remove" -> hidden again;
      // fill <set> had omitted dur (indefinite) -> still #00FF00
      scene.timeline.seekMicroseconds(2000000);
      expect(rVis.style.visibilityHidden, isTrue);
      expect(
        rVis.style.currentFillColor.toARGB32(),
        equals(const ui.Color(0xFF00FF00).toARGB32()),
      );

      // <animateColor> at t = 1.0s -> #0000FF
      scene.timeline.seekMicroseconds(1000000);
      expect(
        rColor.style.currentFillColor.toARGB32(),
        equals(const ui.Color(0xFF0000FF).toARGB32()),
      );

      scene.dispose();
    });

    test('supports nested <svg> viewBox/clipping, non-rendered <symbol>, and <use> width/height + cycle guard', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <symbol id="badgeSym" viewBox="0 0 10 10">
    <rect x="0" y="0" width="10" height="10" fill="#00FF00" />
  </symbol>
  <svg id="nested" x="50" y="0" width="50" height="50" viewBox="0 0 10 10">
    <rect x="0" y="0" width="20" height="20" fill="#0000FF" />
  </svg>
  <use id="symInstance" href="#badgeSym" x="0" y="50" width="40" height="40" />
  <use id="selfCycle" href="#selfCycle" x="0" y="0" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final sym = scene.document.defsById['badgeSym'];
      final nested = scene.document.elementsById['nested'];
      expect(sym, isA<SvgSymbolNode>());
      expect(nested, isA<SvgNestedSvgNode>());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // (5, 5): <symbol> itself must NOT be rendered directly -> transparent
      final symOriginIdx = (5 * 100 + 5) * 4;
      expect(bytes[symOriginIdx + 3], equals(0));

      // (20, 70): <use href="#badgeSym" x="0" y="50" width="40" height="40" /> -> green
      final useIdx = (70 * 100 + 20) * 4;
      expect(bytes[useIdx], equals(0));
      expect(bytes[useIdx + 1], equals(255));
      expect(bytes[useIdx + 2], equals(0));
      expect(bytes[useIdx + 3], equals(255));

      // (75, 25): inside nested <svg x="50" y="0" width="50" height="50"> -> blue
      final nestedIdx = (25 * 100 + 75) * 4;
      expect(bytes[nestedIdx], equals(0));
      expect(bytes[nestedIdx + 1], equals(0));
      expect(bytes[nestedIdx + 2], equals(255));
      expect(bytes[nestedIdx + 3], equals(255));

      // (75, 75): outside nested <svg> clip rect (rect was 20x20 in 10x10 viewBox) -> clipped transparent
      final clippedIdx = (75 * 100 + 75) * 4;
      expect(bytes[clippedIdx + 3], equals(0));

      image.dispose();
      picture.dispose();
      scene.dispose();
    });
  });
}
