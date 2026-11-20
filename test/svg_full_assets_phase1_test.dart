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
  group('Phase 1 (P0): CSS Color 4, <use>/<symbol> isolation, shape-rendering', () {
    test(
      'parses hsl(), hsla(), CSS Color 4 space syntax, angle units, and hwb()',
      () {
        // Pure red: hsl(0, 100%, 50%)
        expect(
          SvgCssParser.parseColor('hsl(0, 100%, 50%)'),
          equals(const ui.Color(0xFFFF0000)),
        );
        // Pure green via turn unit: hsl(0.333333turn 100% 50%)
        final green = SvgCssParser.parseColor('hsl(0.333333turn 100% 50%)');
        expect(green, isNotNull);
        expect((green!.g * 255).round(), greaterThan(250));
        expect((green.r * 255).round(), lessThan(5));
        // Alpha via slash syntax: hsl(240 100% 50% / 50%)
        final halfBlue = SvgCssParser.parseColor('hsl(240 100% 50% / 50%)');
        expect(halfBlue, isNotNull);
        expect((halfBlue!.b * 255).round(), equals(255));
        expect((halfBlue.a * 255).round(), inInclusiveRange(126, 129));
        // Negative hue wrapping: hsl(-120, 100%, 50%) == hsl(240, 100%, 50%)
        expect(
          SvgCssParser.parseColor('hsl(-120, 100%, 50%)'),
          equals(const ui.Color(0xFF0000FF)),
        );
        // HWB: hwb(0 0% 0%) == pure red; hwb(120 50% 50%) == mid gray
        expect(
          SvgCssParser.parseColor('hwb(0 0% 0%)'),
          equals(const ui.Color(0xFFFF0000)),
        );
        final gray = SvgCssParser.parseColor('hwb(120 50% 50%)');
        expect(gray, isNotNull);
        expect((gray!.r * 255).round(), inInclusiveRange(127, 128));
      },
    );

    test(
      'supports currentColor inheritance from parent color attribute',
      () async {
        const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <g color="hsl(120, 100%, 50%)">
    <rect x="0" y="0" width="100" height="100" fill="currentColor" />
  </g>
</svg>
''';
        final scene = SvgParser.compile(svg);
        final bytes = await _renderRgba(scene, 100, 100);
        final idx = (50 * 100 + 50) * 4;
        expect(bytes[idx], lessThan(10));
        expect(bytes[idx + 1], greaterThan(245));
        expect(bytes[idx + 2], lessThan(10));
        scene.dispose();
      },
    );

    test('isolates per-instance fill colors and single-width aspect scaling on <use> -> <symbol>', () async {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <symbol id="sq" viewBox="0 0 20 10">
      <rect x="0" y="0" width="20" height="10" />
    </symbol>
  </defs>
  <use href="#sq" x="0" y="0" width="40" fill="hsl(0, 100%, 50%)" />
  <use href="#sq" x="50" y="0" width="40" fill="hsl(240, 100%, 50%)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 100, 100);

      // First <use>: width=40 -> height=20 (proportional to 20:10), pure red
      final idx1 = (10 * 100 + 20) * 4;
      expect(bytes[idx1], greaterThan(240));
      expect(bytes[idx1 + 2], lessThan(15));

      // Below proportional height (y=30): must remain transparent (not stretched to 40)
      final idxBelow = (30 * 100 + 20) * 4;
      expect(bytes[idxBelow + 3], equals(0));

      // Second <use>: same <symbol> must be pure blue (no cachedPicture color bleed)
      final idx2 = (10 * 100 + 70) * 4;
      expect(bytes[idx2], lessThan(15));
      expect(bytes[idx2 + 2], greaterThan(240));

      scene.dispose();
    });

    test('renders real full_svg assets (bbblurry, ccchaos, iiisometric, bbburst) with vibrant non-black colors', () async {
      for (final asset in const [
        'example/assets/full_svg/bbblurry.svg',
        'example/assets/full_svg/ccchaos.svg',
        'example/assets/full_svg/iiisometric.svg',
        'example/assets/full_svg/bbburst.svg',
      ]) {
        final file = File(asset);
        if (!file.existsSync()) continue;
        final scene = SvgParser.compile(file.readAsStringSync());
        final bytes = await _renderRgba(scene, 120, 120);
        int colorfulPixels = 0;
        for (int i = 0; i < bytes.length; i += 4) {
          final a = bytes[i + 3];
          if (a > 20) {
            final r = bytes[i];
            final g = bytes[i + 1];
            final b = bytes[i + 2];
            if ((r - g).abs() > 20 ||
                (g - b).abs() > 20 ||
                (r - b).abs() > 20) {
              colorfulPixels++;
            }
          }
        }
        expect(
          colorfulPixels,
          greaterThan(50),
          reason: '$asset should render colorful non-black pixels',
        );
        scene.dispose();
      }
    });
  });
}
