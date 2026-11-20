import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

Future<List<int>> _renderRgba(
  CompiledSvgScene scene,
  int width,
  int height,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  scene.document.paint(
    canvas,
    ui.Size(width.toDouble(), height.toDouble()),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  group('Stage 2: CSS Color 4, CSS Math, CSS clip-path shapes, Fallback Paint, Non-scaling Stroke & 3-layer paint-order', () {
    test('parses oklch(), oklab(), lab(), lch(), and color-mix()', () {
      // oklab(1 0 0) == white, oklab(0 0 0) == black
      expect(
        SvgCssParser.parseColor('oklab(1 0 0)'),
        equals(const ui.Color(0xFFFFFFFF)),
      );
      expect(
        SvgCssParser.parseColor('oklab(0 0 0)'),
        equals(const ui.Color(0xFF000000)),
      );
      // oklch red-ish hue
      final okRed = SvgCssParser.parseColor('oklch(0.628 0.258 29.23)');
      expect(okRed, isNotNull);
      expect((okRed!.r * 255).round(), greaterThan(230));
      expect((okRed.g * 255).round(), lessThan(40));

      // lab(100 0 0) == white
      expect(
        SvgCssParser.parseColor('lab(100 0 0)'),
        equals(const ui.Color(0xFFFFFFFF)),
      );
      // lch(0 0 0) == black
      expect(
        SvgCssParser.parseColor('lch(0 0 0)'),
        equals(const ui.Color(0xFF000000)),
      );

      // color-mix(in srgb, #ff0000 50%, #0000ff 50%) -> purple (128, 0, 128)
      final purple = SvgCssParser.parseColor(
        'color-mix(in srgb, #ff0000 50%, #0000ff 50%)',
      );
      expect(purple, isNotNull);
      expect((purple!.r * 255).round(), inInclusiveRange(126, 129));
      expect((purple.g * 255).round(), equals(0));
      expect((purple.b * 255).round(), inInclusiveRange(126, 129));
    });

    test('evaluates calc(), min(), max(), and clamp() lengths & percentages', () {
      expect(
        SvgCssParser.parseNumberOrPercent('calc(50% + 10px)', referenceExtent: 200),
        closeTo(110.0, 1e-6),
      );
      expect(
        SvgCssParser.parseLength('min(40px, 20px + 5px)'),
        closeTo(25.0, 1e-6),
      );
      expect(
        SvgCssParser.parseLength('max(10px, 30px * 2)'),
        closeTo(60.0, 1e-6),
      );
      expect(
        SvgCssParser.parseLength('clamp(10px, 50px, 30px)'),
        closeTo(30.0, 1e-6),
      );
    });

    test('clips elements with CSS clip-path basic shapes (circle, inset, polygon)', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="0" width="100" height="100" fill="#FF0000"
    style="clip-path: circle(25px at 50% 50%)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 100, 100);

      // Center (50, 50) inside circle -> red
      expect(bytes[(50 * 100 + 50) * 4], greaterThan(240));
      // Corner (5, 5) outside circle -> clipped transparent
      expect(bytes[(5 * 100 + 5) * 4 + 3], equals(0));
      scene.dispose();
    });

    test('uses Paint Server fallback color when url(#missing) is absent and supports chained gradient href', () async {
      const svg = '''
<svg viewBox="0 0 100 50" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="gBase">
      <stop offset="0%" stop-color="#0000FF" />
      <stop offset="100%" stop-color="#0000FF" />
    </linearGradient>
    <linearGradient id="gMid" href="#gBase" />
    <linearGradient id="gTop" href="#gMid" />
  </defs>
  <rect x="0" y="0" width="50" height="50" fill="url(#missing) #00FF00" />
  <rect x="50" y="0" width="50" height="50" fill="url(#gTop)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 100, 50);

      // Left rect: fallback green
      expect(bytes[(25 * 100 + 25) * 4 + 1], greaterThan(240));
      // Right rect: chained 3-level gradient blue
      expect(bytes[(25 * 100 + 75) * 4 + 2], greaterThan(240));
      scene.dispose();
    });

    test('supports vector-effect="non-scaling-stroke" and 3-layer paint-order', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <g transform="scale(5)">
    <line x1="2" y1="10" x2="18" y2="10" stroke="#FF0000" stroke-width="2"
      vector-effect="non-scaling-stroke" />
  </g>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 100, 100);

      // Line is at y=50 (10*5) with non-scaling stroke-width=2px (y=49..51),
      // NOT scaled to 10px (y=45..55).
      expect(bytes[(50 * 100 + 50) * 4], greaterThan(200));
      expect(bytes[(46 * 100 + 50) * 4 + 3], equals(0));
      scene.dispose();
    });
  });
}
