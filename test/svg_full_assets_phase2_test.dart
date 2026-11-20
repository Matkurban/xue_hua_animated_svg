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
  group('Phase 2 (P1): mix-blend-mode, <feTurbulence>, <feDisplacementMap>, edgeMode', () {
    test(
      'applies CSS mix-blend-mode: multiply across overlapping shapes',
      () async {
        const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="0" width="100" height="100" fill="#FF0000" />
  <rect x="0" y="0" width="100" height="100" fill="#00FF00" style="mix-blend-mode: multiply" />
</svg>
''';
        final scene = SvgParser.compile(svg);
        final bytes = await _renderRgba(scene, 60, 60);
        final idx = (30 * 60 + 30) * 4;
        // Red multiplied with Green -> Black (0, 0, 0, 255)
        expect(bytes[idx], lessThan(10));
        expect(bytes[idx + 1], lessThan(10));
        expect(bytes[idx + 2], lessThan(10));
        expect(bytes[idx + 3], greaterThan(240));
        scene.dispose();
      },
    );

    test(
      'renders <feTurbulence> procedural noise field synchronously',
      () async {
        const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="noise" x="0%" y="0%" width="100%" height="100%">
      <feTurbulence type="fractalNoise" baseFrequency="0.1" numOctaves="2" seed="7" />
    </filter>
  </defs>
  <rect x="0" y="0" width="100" height="100" fill="transparent" filter="url(#noise)" />
</svg>
''';
        final scene = SvgParser.compile(svg);
        final bytes = await _renderRgba(scene, 80, 80);
        final uniqueLuma = <int>{};
        int visiblePixels = 0;
        for (int i = 0; i < bytes.length; i += 4) {
          if (bytes[i + 3] > 20) {
            visiblePixels++;
            uniqueLuma.add(bytes[i]);
          }
        }
        expect(visiblePixels, greaterThan(4000));
        expect(uniqueLuma.length, greaterThan(10));
        scene.dispose();
      },
    );

    test('renders real complex filter assets (ffflux, gggrain, ssspot) with rich output', () async {
      for (final asset in const [
        'example/assets/full_svg/ffflux.svg',
        'example/assets/full_svg/gggrain.svg',
        'example/assets/full_svg/ssspot.svg',
      ]) {
        final file = File(asset);
        if (!file.existsSync()) continue;
        final scene = SvgParser.compile(file.readAsStringSync());
        final bytes = await _renderRgba(scene, 120, 120);
        int nonTransparent = 0;
        final distinctColors = <int>{};
        for (int i = 0; i < bytes.length; i += 4) {
          if (bytes[i + 3] > 20) {
            nonTransparent++;
            distinctColors.add(
              ((bytes[i] >> 3) << 10) |
                  ((bytes[i + 1] >> 3) << 5) |
                  (bytes[i + 2] >> 3),
            );
          }
        }
        expect(nonTransparent, greaterThan(5000), reason: asset);
        expect(distinctColors.length, greaterThan(5), reason: asset);
        scene.dispose();
      }
    });
  });
}
