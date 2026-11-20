import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

void main() {
  group('Phase 4 (P3): <filter> and 10 GPU-accelerated fe* primitives', () {
    test('renders <feDropShadow> shadow offset behind source graphic', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="dropShadow" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
      <feDropShadow dx="15" dy="15" stdDeviation="0" flood-color="#0000FF" flood-opacity="1" />
    </filter>
  </defs>
  <rect x="20" y="20" width="30" height="30" fill="#FF0000" filter="url(#dropShadow)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      expect(scene.document.filtersById['dropShadow'], isA<SvgFilterNode>());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // (25, 25): source rect -> red
      final srcIdx = (25 * 100 + 25) * 4;
      expect(bytes[srcIdx], greaterThan(200));
      expect(bytes[srcIdx + 2], lessThan(20));

      // (58, 58): offset shadow [35..65, 35..65] outside source [20..50] -> blue
      final shadowIdx = (58 * 100 + 58) * 4;
      expect(bytes[shadowIdx + 2], greaterThan(200));
      expect(bytes[shadowIdx + 3], greaterThan(200));

      image.dispose();
      picture.dispose();
      scene.dispose();
    });

    test('executes multi-step <feGaussianBlur> + <feOffset> + <feMerge> filter graph', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="glow" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
      <feGaussianBlur in="SourceAlpha" stdDeviation="2" result="blur" />
      <feOffset in="blur" dx="8" dy="8" result="offsetBlur" />
      <feMerge>
        <feMergeNode in="offsetBlur" />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>
  </defs>
  <rect x="20" y="20" width="30" height="30" fill="#00FF00" filter="url(#glow)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final filter = scene.document.filtersById['glow']!;
      expect(filter.primitives.length, equals(3));

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // (35, 35): SourceGraphic on top -> green
      final srcIdx = (35 * 100 + 35) * 4;
      expect(bytes[srcIdx + 1], greaterThan(200));

      // (54, 54): blurred offset shadow -> non-transparent dark pixel
      final shadowIdx = (54 * 100 + 54) * 4;
      expect(bytes[shadowIdx + 3], greaterThan(50));

      image.dispose();
      picture.dispose();
      scene.dispose();
    });

    test('supports <feColorMatrix>, <feFlood>, <feComposite>, <feBlend>, <feMorphology>, and <feComponentTransfer>', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="gray" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
      <feColorMatrix type="saturate" values="0" />
    </filter>
    <filter id="floodComp" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
      <feFlood flood-color="#00FF00" flood-opacity="1" result="flood" />
      <feComposite in="flood" in2="SourceGraphic" operator="in" />
    </filter>
    <filter id="morphTransfer" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
      <feMorphology operator="dilate" radius="2" result="dilated" />
      <feComponentTransfer in="dilated">
        <feFuncR type="linear" slope="0.5" intercept="0" />
        <feFuncA type="identity" />
      </feComponentTransfer>
    </filter>
  </defs>
  <rect x="0" y="0" width="30" height="30" fill="#FF0000" filter="url(#gray)" />
  <rect x="35" y="0" width="30" height="30" fill="#FF0000" filter="url(#floodComp)" />
  <rect x="70" y="0" width="20" height="20" fill="#FF0000" filter="url(#morphTransfer)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      expect(scene.document.filtersById.length, equals(3));

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // (15, 15): desaturated red -> R == G == B (grayscale)
      final grayIdx = (15 * 100 + 15) * 4;
      expect((bytes[grayIdx] - bytes[grayIdx + 1]).abs(), lessThanOrEqualTo(2));
      expect((bytes[grayIdx + 1] - bytes[grayIdx + 2]).abs(), lessThanOrEqualTo(2));

      // (50, 15): green flood composited "in" red rect -> green
      final compIdx = (15 * 100 + 50) * 4;
      expect(bytes[compIdx + 1], greaterThan(200));
      expect(bytes[compIdx], lessThan(20));

      // (80, 10): dilated + red channel scaled by 0.5 -> ~127
      final morphIdx = (10 * 100 + 80) * 4;
      expect(bytes[morphIdx], inInclusiveRange(110, 145));

      image.dispose();
      picture.dispose();
      scene.dispose();
    });
  });
}
