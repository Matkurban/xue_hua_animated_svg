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
  scene.document.paint(canvas, ui.Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  group('Stage 1: W3C CSS Selectors, Custom Properties (var), !important, SVG 2 CSS Geometry & Transforms', () {
    test('resolves CSS custom properties (--var) with inheritance and nested var() fallbacks', () async {
      const svg = '''
<svg viewBox="0 0 100 50" xmlns="http://www.w3.org/2000/svg">
  <style>
    :root { --primary: #00FF00; }
    .box { fill: var(--missing, var(--primary, #FF0000)); }
    .override { --primary: #0000FF; }
  </style>
  <rect class="box" x="0" y="0" width="50" height="50" />
  <g class="override">
    <rect class="box" x="50" y="0" width="50" height="50" />
  </g>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 100, 50);

      // Left rect: inherited :root --primary (#00FF00)
      final leftIdx = (25 * 100 + 25) * 4;
      expect(bytes[leftIdx + 1], greaterThan(240));
      expect(bytes[leftIdx], lessThan(15));

      // Right rect: overridden by ancestor .override (#0000FF)
      final rightIdx = (25 * 100 + 75) * 4;
      expect(bytes[rightIdx + 2], greaterThan(240));
      expect(bytes[rightIdx + 1], lessThan(15));

      scene.dispose();
    });

    test('matches complex CSS selectors (combinators, attribute, :first-child, :nth-child, :not)', () async {
      const svg = '''
<svg viewBox="0 0 120 40" xmlns="http://www.w3.org/2000/svg">
  <style>
    g.cards > rect:first-child { fill: #FF0000; }
    g.cards > rect:nth-child(2) { fill: #00FF00; }
    g.cards > rect[data-role="last"]:not(.skip) { fill: #0000FF; }
  </style>
  <g class="cards">
    <rect x="0" y="0" width="40" height="40" />
    <rect x="40" y="0" width="40" height="40" />
    <rect x="80" y="0" width="40" height="40" data-role="last" />
  </g>
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 120, 40);

      expect(bytes[(20 * 120 + 20) * 4], greaterThan(240)); // red
      expect(bytes[(20 * 120 + 60) * 4 + 1], greaterThan(240)); // green
      expect(bytes[(20 * 120 + 100) * 4 + 2], greaterThan(240)); // blue
      scene.dispose();
    });

    test('honors W3C !important cascade over inline style', () async {
      const svg = '''
<svg viewBox="0 0 60 60" xmlns="http://www.w3.org/2000/svg">
  <style>
    rect { fill: #00FF00 !important; }
  </style>
  <rect x="0" y="0" width="60" height="60" style="fill: #FF0000" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 60, 60);
      final idx = (30 * 60 + 30) * 4;
      expect(bytes[idx + 1], greaterThan(240));
      expect(bytes[idx], lessThan(15));
      scene.dispose();
    });

    test('supports SVG 2 CSS geometry properties (x, y, width, height, d: path(...)) and standalone translate/scale', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <style>
    #r { x: 10px; y: 10px; width: 30px; height: 30px; fill: #FF0000; translate: 10px 0px; }
    #p { d: path("M60 10 H90 V40 H60 Z"); fill: #0000FF; }
  </style>
  <rect id="r" />
  <path id="p" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 100, 100);

      // #r shifted from x=10..40 to x=20..50 by CSS `translate: 10px 0px`
      final rIdx = (25 * 100 + 35) * 4;
      expect(bytes[rIdx], greaterThan(240));
      expect(bytes[(25 * 100 + 12) * 4 + 3], equals(0));

      // #p drawn from CSS `d: path(...)` at (60..90, 10..40)
      final pIdx = (25 * 100 + 75) * 4;
      expect(bytes[pIdx + 2], greaterThan(240));

      scene.dispose();
    });
  });
}
