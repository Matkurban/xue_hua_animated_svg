import 'dart:io';
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
  group('Phase 3 (P2): CSS filter chains, geometry paint-order, and 42 full_svg regression', () {
    test('executes CSS filter function chains (grayscale, invert, drop-shadow)', () async {
      const svg = '''
<svg viewBox="0 0 120 60" xmlns="http://www.w3.org/2000/svg">
  <rect x="5" y="10" width="30" height="30" fill="#FF0000" style="filter: grayscale(100%)" />
  <rect x="45" y="10" width="30" height="30" fill="#FF0000" style="filter: invert(100%)" />
  <rect x="85" y="10" width="20" height="20" fill="#00FF00" style="filter: drop-shadow(8px 8px 0px #0000FF)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 120, 60);

      // (20, 25): grayscale red -> R == G == B
      final gIdx = (25 * 120 + 20) * 4;
      expect((bytes[gIdx] - bytes[gIdx + 1]).abs(), lessThanOrEqualTo(2));
      expect((bytes[gIdx + 1] - bytes[gIdx + 2]).abs(), lessThanOrEqualTo(2));

      // (60, 25): inverted red (#FF0000) -> cyan (#00FFFF)
      final iIdx = (25 * 120 + 60) * 4;
      expect(bytes[iIdx], lessThan(10));
      expect(bytes[iIdx + 1], greaterThan(245));
      expect(bytes[iIdx + 2], greaterThan(245));

      // (108, 33): blue drop-shadow behind green rect
      final sIdx = (33 * 120 + 108) * 4;
      expect(bytes[sIdx + 2], greaterThan(240));
      expect(bytes[sIdx + 3], greaterThan(240));

      scene.dispose();
    });

    test('honors paint-order="stroke fill" vs default fill stroke on geometry nodes', () async {
      const svg = '''
<svg viewBox="0 0 100 50" xmlns="http://www.w3.org/2000/svg">
  <rect x="10" y="10" width="30" height="30" fill="#FF0000" stroke="#0000FF" stroke-width="12" />
  <rect x="60" y="10" width="30" height="30" fill="#FF0000" stroke="#0000FF" stroke-width="12" paint-order="stroke fill" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 100, 50);

      // Inside stroke overlap (x=13, y=25) on left rect: stroke on top -> blue
      final leftOverlap = (25 * 100 + 13) * 4;
      expect(bytes[leftOverlap + 2], greaterThan(200));

      // Inside stroke overlap (x=63, y=25) on right rect: fill on top -> red
      final rightOverlap = (25 * 100 + 63) * 4;
      expect(bytes[rightOverlap], greaterThan(200));
      expect(bytes[rightOverlap + 2], lessThan(20));

      scene.dispose();
    });

    test('compiles and renders all 42 assets in example/assets/full_svg/ without error or blank output', () async {
      final dir = Directory('example/assets/full_svg');
      if (!dir.existsSync()) return;

      final svgFiles = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.svg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(svgFiles.length, greaterThanOrEqualTo(40));

      for (final file in svgFiles) {
        final scene = SvgParser.compile(file.readAsStringSync());
        final bytes = await _renderRgba(scene, 80, 80);
        int visiblePixels = 0;
        for (int i = 0; i < bytes.length; i += 4) {
          if (bytes[i + 3] > 5) visiblePixels++;
        }
        expect(
          visiblePixels,
          greaterThan(20),
          reason: '${file.path} should render visible non-empty pixels',
        );
        scene.dispose();
      }
    });

    test('clips root <svg> viewport by default (overflow: hidden) unless overflow="visible"', () async {
      // Root <svg> with content extending past viewBox bottom (like sssurf.svg)
      const clippedSvg = '''
<svg viewBox="0 0 100 50" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="0" width="100" height="100" fill="#0088FF" />
</svg>
''';
      final scene = SvgParser.compile(clippedSvg);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      // Paint the 100x50 intrinsic SVG at top of a taller 100x100 canvas
      scene.document.paint(canvas, const ui.Size(100, 50));
      final pic = recorder.endRecording();
      final img = await pic.toImage(100, 100);
      final bytes = (await img.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // Inside viewport (y=25): blue
      final insideIdx = (25 * 100 + 50) * 4;
      expect(bytes[insideIdx + 2], greaterThan(240));
      expect(bytes[insideIdx + 3], greaterThan(240));

      // Below viewport bottom (y=75): must be clipped transparent
      final outsideIdx = (75 * 100 + 50) * 4;
      expect(bytes[outsideIdx + 3], equals(0));

      img.dispose();
      pic.dispose();
      scene.dispose();
    });
  });
}
