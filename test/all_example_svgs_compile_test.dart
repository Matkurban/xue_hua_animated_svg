import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

void main() {
  test('All 112+ example SVGs compile successfully into animated scenes', () {
    final svgsDir = Directory('example/assets/svgs');
    expect(svgsDir.existsSync(), isTrue);

    final svgFiles = svgsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'))
        .toList();

    expect(svgFiles.length, greaterThanOrEqualTo(112));


    int animatedCount = 0;
    for (final file in svgFiles) {
      final xml = file.readAsStringSync();
      expect(xml.isNotEmpty, isTrue, reason: '${file.path} is empty');

      CompiledSvgScene? scene;
      try {
        scene = SvgParser.compile(xml);
        expect(scene, isNotNull, reason: 'Failed to compile ${file.path}');
        if (scene.timeline.hasAnimations) {
          animatedCount++;
          // Verify seeking timeline works without exception
          scene.timeline.seekMicroseconds(500000);
        }
      } catch (e, st) {
        fail('Exception compiling ${file.path}: $e\n$st');
      } finally {
        scene?.dispose();
      }
    }


    expect(animatedCount, greaterThanOrEqualTo(110));
  });
}
