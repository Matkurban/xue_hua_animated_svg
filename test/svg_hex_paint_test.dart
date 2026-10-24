import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

void main() {
  group('hex fill and stroke colors stay solid paints', () {
    test('parsePaintServer resolves hex colors before url(#id) gradients', () {
      expectSolid('#ffffff', 255, 255, 255, 255);
      expectSolid('#194fe4', 255, 0x19, 0x4f, 0xe4);
      expectSolid('#cae1eb', 255, 0xca, 0xe1, 0xeb);
      expectSolid('#b4d3ff', 255, 0xb4, 0xd3, 0xff);

      final gradient = SvgCssParser.parsePaintServer('url(#grad1)');
      expect(gradient, isNotNull);
      expect(gradient!.type, SvgPaintType.gradient);
      expect(gradient.gradientId, 'grad1');

      expect(SvgCssParser.extractUrlId('#ffffff'), isNull);
      expect(SvgCssParser.extractUrlId('url(#ffffff)'), 'ffffff');
      expect(SvgCssParser.extractUrlId('#clip1'), 'clip1');

      expect(SvgCssParser.parsePaintServer('none')!.type, SvgPaintType.none);
      final transparent = SvgCssParser.parsePaintServer('transparent')!;
      expect(transparent.type, SvgPaintType.color);
      expect(transparent.color.toARGB32(), 0x00000000);
    });

    test('compiling elephant.svg keeps board and strokes as solid colors', () {
      final svg = File('example/assets/svgs/elephant.svg').readAsStringSync();
      final scene = SvgParser.compile(svg);
      final nodes = <SvgElement>[];
      void walk(SvgElement element) {
        nodes.add(element);
        for (final child in element.children) {
          walk(child);
        }
      }

      walk(scene.document.rootGroup);

      final strokes = nodes
          .where((element) => element.classes.contains('elephant-stroke'))
          .toList();
      expect(strokes, isNotEmpty);
      for (final path in strokes) {
        expect(path.style.baseFill!.type, SvgPaintType.none);
        expect(path.style.resolvedFill.type, SvgPaintType.none);
        expectSolidPaint(path.style.baseStroke, 255, 255, 255, 255);
        expectSolidPaint(path.style.resolvedStroke, 255, 255, 255, 255);
      }

      final board = nodes.whereType<SvgRectNode>().singleWhere(
        (rect) => rect.baseX == 252.36 && rect.baseY == 252.36,
      );
      expectSolidPaint(board.style.baseFill, 255, 0x19, 0x4f, 0xe4);
      expectSolidPaint(board.style.resolvedFill, 255, 0x19, 0x4f, 0xe4);

      final rotating = nodes.whereType<SvgRectNode>().where((rect) {
        return rect.baseX == 234 && rect.baseY == 234 && rect.baseWidth == 612;
      }).toList();
      expect(rotating, hasLength(2));
      final filled = rotating.singleWhere(
        (rect) => rect.style.baseFill?.type == SvgPaintType.color,
      );
      final outlined = rotating.singleWhere(
        (rect) => rect.style.baseStroke?.type == SvgPaintType.color,
      );
      expectSolidPaint(filled.style.baseFill, 255, 0xca, 0xe1, 0xeb);
      expect(outlined.style.baseFill!.type, SvgPaintType.none);
      expectSolidPaint(outlined.style.baseStroke, 255, 0xb4, 0xd3, 0xff);

      scene.dispose();
    });
  });
}

void expectSolid(String raw, int a, int r, int g, int b) {
  expectSolidPaint(SvgCssParser.parsePaintServer(raw), a, r, g, b);
}

void expectSolidPaint(SvgPaintServer? paint, int a, int r, int g, int b) {
  expect(paint, isNotNull);
  expect(paint!.type, SvgPaintType.color);
  expect(paint.gradientId, isNull);
  final argb = paint.color.toARGB32();
  expect((argb >> 24) & 0xFF, a);
  expect((argb >> 16) & 0xFF, r);
  expect((argb >> 8) & 0xFF, g);
  expect(argb & 0xFF, b);
  expect(paint.color, ui.Color.fromARGB(a, r, g, b));
}
