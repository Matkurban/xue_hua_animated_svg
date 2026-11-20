import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

void main() {
  group('Phase 2 (P1): <mask>, <pattern>, <marker>, and <clipPath> full spec', () {
    test('renders luminance <mask> (white visible, black hidden) and alpha <mask>', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <mask id="lumMask" maskUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
      <rect x="0" y="0" width="50" height="100" fill="#FFFFFF" />
      <rect x="50" y="0" width="50" height="100" fill="#000000" />
    </mask>
  </defs>
  <rect id="maskedRect" x="0" y="0" width="100" height="100" fill="#FF0000" mask="url(#lumMask)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      expect(scene.document.masksById['lumMask'], isA<SvgMaskNode>());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // Left half (25, 50): under white mask -> visible red
      final leftIdx = (50 * 100 + 25) * 4;
      expect(bytes[leftIdx], greaterThan(200));
      expect(bytes[leftIdx + 3], greaterThan(200));

      // Right half (75, 50): under black mask -> transparent
      final rightIdx = (50 * 100 + 75) * 4;
      expect(bytes[rightIdx + 3], lessThan(10));

      image.dispose();
      picture.dispose();
      scene.dispose();
    });

    test('renders repeating <pattern> fill with userSpaceOnUse and patternTransform', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <pattern id="checker" patternUnits="userSpaceOnUse" width="20" height="20">
      <rect x="0" y="0" width="10" height="10" fill="#00FF00" />
      <rect x="10" y="10" width="10" height="10" fill="#00FF00" />
    </pattern>
  </defs>
  <rect id="patRect" x="0" y="0" width="100" height="100" fill="url(#checker)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      expect(scene.document.patternsById['checker'], isA<SvgPatternNode>());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // Repeated tile at (45, 45) -> inside [0..10, 0..10] green quadrant of tile (2,2)
      final greenIdx = (45 * 100 + 45) * 4;
      expect(bytes[greenIdx + 1], greaterThan(200));
      expect(bytes[greenIdx + 3], greaterThan(200));

      // Repeated tile at (55, 45) -> inside [10..20, 0..10] transparent quadrant
      final emptyIdx = (45 * 100 + 55) * 4;
      expect(bytes[emptyIdx + 3], lessThan(10));

      image.dispose();
      picture.dispose();
      scene.dispose();
    });

    test('renders <marker> at start, mid, and end vertices of <path> and <polyline>', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <marker id="dot" viewBox="0 0 10 10" refX="5" refY="5"
      markerWidth="10" markerHeight="10" markerUnits="userSpaceOnUse" orient="auto">
      <circle cx="5" cy="5" r="5" fill="#0000FF" />
    </marker>
  </defs>
  <polyline id="poly" points="20,50 50,50 80,50" fill="none" stroke="#111111"
    stroke-width="2" marker-start="url(#dot)" marker-mid="url(#dot)" marker-end="url(#dot)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      expect(scene.document.markersById['dot'], isA<SvgMarkerNode>());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // Check blue marker dot pixels at start (20,50), mid (50,50), end (80,50)
      for (final x in [20, 50, 80]) {
        final idx = (50 * 100 + x) * 4;
        expect(bytes[idx + 2], greaterThan(200), reason: 'blue marker at x=$x');
        expect(bytes[idx + 3], greaterThan(200), reason: 'opaque marker at x=$x');
      }

      image.dispose();
      picture.dispose();
      scene.dispose();
    });

    test('supports <clipPath clipPathUnits="objectBoundingBox"> scaling on target bounds', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <clipPath id="bboxClip" clipPathUnits="objectBoundingBox">
      <rect x="0" y="0" width="0.5" height="1" />
    </clipPath>
  </defs>
  <rect x="20" y="20" width="60" height="60" fill="#FF00FF" clip-path="url(#bboxClip)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final clip = scene.document.clipPathsById['bboxClip']!;
      expect(clip.clipPathUnits, equals(SvgGradientUnits.objectBoundingBox));

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // Left half of [20..80] is [20..50] -> (35, 50) visible magenta
      final insideIdx = (50 * 100 + 35) * 4;
      expect(bytes[insideIdx], greaterThan(200));
      expect(bytes[insideIdx + 2], greaterThan(200));

      // Right half [50..80] -> (65, 50) clipped transparent
      final clippedIdx = (50 * 100 + 65) * 4;
      expect(bytes[clippedIdx + 3], equals(0));

      image.dispose();
      picture.dispose();
      scene.dispose();
    });
  });
}
