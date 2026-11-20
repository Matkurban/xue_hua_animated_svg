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
  group('Stage 3: Filter Effects Level 1 remaining 5 primitives (feImage, feTile, feComposite arithmetic, feConvolveMatrix, feDiffuseLighting/feSpecularLighting)', () {
    test(
      'renders <feImage href="#id"> referencing an internal defs element',
      () async {
        const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <rect id="srcShape" x="10" y="10" width="80" height="80" fill="#00FF00" />
    <filter id="imgFilter" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
      <feImage href="#srcShape" />
    </filter>
  </defs>
  <rect x="0" y="0" width="100" height="100" fill="#FF0000" filter="url(#imgFilter)" />
</svg>
''';
        final scene = SvgParser.compile(svg);
        final bytes = await _renderRgba(scene, 100, 100);
        final idx = (50 * 100 + 50) * 4;
        expect(bytes[idx + 1], greaterThan(240)); // green from #srcShape
        expect(bytes[idx], lessThan(15));
        scene.dispose();
      },
    );

    test(
      'renders <feTile> repeating a subregion tile across the filter region',
      () async {
        const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="tileFilter" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
      <feTile in="SourceGraphic" x="0" y="0" width="25" height="25" />
    </filter>
  </defs>
  <rect x="0" y="0" width="25" height="25" fill="#0000FF" filter="url(#tileFilter)" />
</svg>
''';
        final scene = SvgParser.compile(svg);
        final bytes = await _renderRgba(scene, 100, 100);
        // Tiled at (75, 75) far outside the original 25x25 rect -> blue
        final idx = (75 * 100 + 75) * 4;
        expect(bytes[idx + 2], greaterThan(220));
        expect(bytes[idx + 3], greaterThan(220));
        scene.dispose();
      },
    );

    test('renders <feConvolveMatrix> and <feComposite operator="arithmetic"> over turbulence fields', () async {
      const svg = '''
<svg viewBox="0 0 80 80" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="convArith" filterUnits="userSpaceOnUse" x="0" y="0" width="80" height="80">
      <feTurbulence type="fractalNoise" baseFrequency="0.1" numOctaves="2" seed="3" result="n1" />
      <feConvolveMatrix in="n1" order="3" kernelMatrix="0 -1 0 -1 5 -1 0 -1 0" result="sharp" />
      <feComposite in="n1" in2="sharp" operator="arithmetic" k1="0" k2="0.5" k3="0.5" k4="0" />
    </filter>
  </defs>
  <rect x="0" y="0" width="80" height="80" fill="transparent" filter="url(#convArith)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 80, 80);
      int visible = 0;
      for (int i = 0; i < bytes.length; i += 4) {
        if (bytes[i + 3] > 20) visible++;
      }
      expect(visible, greaterThan(4000));
      scene.dispose();
    });

    test('renders <feDiffuseLighting> with <feDistantLight> and <feSpecularLighting> with <fePointLight>', () async {
      const svg = '''
<svg viewBox="0 0 100 50" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="diffLight" filterUnits="userSpaceOnUse" x="0" y="0" width="50" height="50">
      <feDiffuseLighting surfaceScale="4" diffuseConstant="1.2" lighting-color="#FFCC88">
        <feDistantLight azimuth="45" elevation="55" />
      </feDiffuseLighting>
    </filter>
    <filter id="specLight" filterUnits="userSpaceOnUse" x="50" y="0" width="50" height="50">
      <feSpecularLighting surfaceScale="4" specularConstant="1.5" specularExponent="16" lighting-color="#FFFFFF">
        <fePointLight x="75" y="25" z="40" />
      </feSpecularLighting>
    </filter>
  </defs>
  <rect x="0" y="0" width="50" height="50" fill="#808080" filter="url(#diffLight)" />
  <rect x="50" y="0" width="50" height="50" fill="#808080" filter="url(#specLight)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final bytes = await _renderRgba(scene, 100, 50);

      // Left rect: warm diffuse lighting (R > B)
      final diffIdx = (25 * 100 + 25) * 4;
      expect(bytes[diffIdx], greaterThan(100));
      expect(bytes[diffIdx], greaterThan(bytes[diffIdx + 2]));

      // Right rect: specular highlight near point light (75, 25)
      final specIdx = (25 * 100 + 75) * 4;
      expect(bytes[specIdx], greaterThan(100));
      expect(bytes[specIdx + 3], greaterThan(100));

      scene.dispose();
    });
  });
}
