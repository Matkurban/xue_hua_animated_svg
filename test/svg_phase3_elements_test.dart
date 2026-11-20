import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

/// Valid 1x1 solid red PNG encoded as base64.
const _red1x1PngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

void main() {
  group('Phase 3 (P2): <image>, <view>, and <radialGradient fr>', () {
    test('renders <image> from embedded base64 PNG data URI and embedded SVG data URI', () async {
      const svg =
          '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <image id="pngImg" x="0" y="0" width="50" height="50"
    href="data:image/png;base64,$_red1x1PngBase64" preserveAspectRatio="none" />
  <image id="svgImg" x="50" y="50" width="50" height="50"
    href="data:image/svg+xml;utf8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20viewBox%3D%220%200%2010%2010%22%3E%3Crect%20width%3D%2210%22%20height%3D%2210%22%20fill%3D%22%230000FF%22%2F%3E%3C%2Fsvg%3E" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      expect(scene.document.imageNodes.length, equals(2));

      // Wait for async raster codec decode before offscreen paint
      await scene.document.precacheImages();
      final pngNode = scene.document.elementsById['pngImg'] as SvgImageNode;
      final svgNode = scene.document.elementsById['svgImg'] as SvgImageNode;
      expect(pngNode.isLoaded, isTrue);
      expect(svgNode.isLoaded, isTrue);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.document.paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // (25, 25): inside red PNG <image>
      final pngIdx = (25 * 100 + 25) * 4;
      expect(bytes[pngIdx], greaterThan(200));
      expect(bytes[pngIdx + 3], greaterThan(200));

      // (75, 75): inside blue nested SVG <image>
      final svgIdx = (75 * 100 + 75) * 4;
      expect(bytes[svgIdx + 2], greaterThan(200));
      expect(bytes[svgIdx + 3], greaterThan(200));

      image.dispose();
      picture.dispose();
      scene.dispose();
    });

    test(
      'switches active viewport using named <view id="..." viewBox="...">',
      () async {
        const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <view id="rightSprite" viewBox="50 0 50 100" preserveAspectRatio="none" />
  <rect x="0" y="0" width="50" height="100" fill="#FF0000" />
  <rect x="50" y="0" width="50" height="100" fill="#00FF00" />
</svg>
''';
        final scene = SvgParser.compile(svg);
        expect(scene.document.viewsById['rightSprite'], isNotNull);

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        scene.document.paint(
          canvas,
          const ui.Size(100, 100),
          viewId: 'rightSprite',
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 100);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();

        // Entire canvas should show the green right half
        final leftIdx = (50 * 100 + 10) * 4;
        expect(bytes[leftIdx], equals(0));
        expect(bytes[leftIdx + 1], equals(255));
        expect(bytes[leftIdx + 3], equals(255));

        image.dispose();
        picture.dispose();
        scene.dispose();
      },
    );

    test('supports SVG 2 <radialGradient fr> and SMIL animation on fr', () {
      const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="focalRad" cx="50%" cy="50%" r="50%" fx="30%" fy="30%" fr="10%">
      <animate attributeName="fr" from="0.1" to="0.3" dur="1s" fill="freeze" />
      <stop offset="0%" stop-color="#FFFFFF" />
      <stop offset="100%" stop-color="#000000" />
    </radialGradient>
  </defs>
  <circle cx="50" cy="50" r="40" fill="url(#focalRad)" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      final grad =
          scene.document.gradientsById['focalRad'] as SvgRadialGradientNode;
      expect(grad.baseFr, closeTo(0.1, 1e-6));

      scene.timeline.seekMicroseconds(500000);
      expect(grad.currentFr, closeTo(0.2, 1e-4));
      expect(
        grad.createShader(const ui.Rect.fromLTWH(10, 10, 80, 80)),
        isNotNull,
      );
      scene.dispose();
    });

    test('invalidates static ui.Picture cache when async <image> finishes decoding', () async {
      // Static SVG (no animations) -> rootGroup records cachedPicture on first paint
      const svg =
          '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="0" width="100" height="100" fill="#0F172A" />
  <image x="10" y="10" width="80" height="80"
    href="data:image/png;base64,$_red1x1PngBase64" preserveAspectRatio="none" />
</svg>
''';
      final scene = SvgParser.compile(svg);
      expect(scene.timeline.hasAnimations, isFalse);

      // Paint frame 0 synchronously BEFORE async image decode completes
      final rec0 = ui.PictureRecorder();
      scene.document.paint(ui.Canvas(rec0), const ui.Size(100, 100));
      rec0.endRecording().dispose();
      expect(scene.document.rootGroup.cachedPicture, isNotNull);

      // Wait for async decode -> notifyAsyncAssetLoaded() must invalidate cachedPicture
      await scene.document.precacheImages();
      expect(scene.document.rootGroup.cachedPicture, isNull);

      // Repaint after decode -> center pixel must now be red from the PNG
      final rec1 = ui.PictureRecorder();
      scene.document.paint(ui.Canvas(rec1), const ui.Size(100, 100));
      final pic1 = rec1.endRecording();
      final img1 = await pic1.toImage(100, 100);
      final bytes = (await img1.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();

      final idx = (50 * 100 + 50) * 4;
      expect(bytes[idx], greaterThan(200)); // R
      expect(bytes[idx + 1], lessThan(30)); // G
      expect(bytes[idx + 2], lessThan(30)); // B

      img1.dispose();
      pic1.dispose();
      scene.dispose();
    });
  });
}
