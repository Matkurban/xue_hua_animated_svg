import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

const _sampleSvg = '''
<svg viewBox="0 0 40 40" width="40" height="40" xmlns="http://www.w3.org/2000/svg">
  <circle cx="20" cy="20" r="10" fill="#22C55E">
    <animate attributeName="r" values="8;14;8" dur="1s" repeatCount="indefinite"/>
  </circle>
</svg>
''';

Future<void> _flushAsyncIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(CustomPaint).evaluate().isNotEmpty) {
      return;
    }
  }
}

void main() {
  testWidgets('AnimatedSvgPicture.file loads and paints from a temp file', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('animated_svg_file_');
    final file = File('${temp.path}/sample.svg');
    await tester.runAsync(() => file.writeAsString(_sampleSvg));
    addTearDown(() {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    });

    final controller = AnimatedSvgController(autoPlay: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: AnimatedSvgPicture.file(
            file,
            controller: controller,
            width: 40,
            height: 40,
          ),
        ),
      ),
    );

    await _flushAsyncIo(tester);

    expect(find.byType(AnimatedSvgPicture), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('AnimatedSvgPicture.network loads UTF-8 body via http client', (
    tester,
  ) async {
    final mock = MockClient((request) async {
      expect(request.url.toString(), 'https://example.test/demo.svg');
      expect(request.headers['X-Demo'], '1');
      return http.Response(
        _sampleSvg,
        200,
        headers: {'content-type': 'image/svg+xml; charset=utf-8'},
      );
    });

    final controller = AnimatedSvgController(autoPlay: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: AnimatedSvgPicture.network(
            'https://example.test/demo.svg',
            headers: const {'X-Demo': '1'},
            httpClient: mock,
            controller: controller,
            width: 40,
            height: 40,
          ),
        ),
      ),
    );

    await _flushAsyncIo(tester);

    expect(find.byType(AnimatedSvgPicture), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('AnimatedSvgPicture.network keeps empty SizedBox on HTTP error', (
    tester,
  ) async {
    final mock = MockClient((request) async {
      return http.Response('missing', 404);
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: AnimatedSvgPicture.network(
            'https://example.test/missing.svg',
            httpClient: mock,
            width: 64,
            height: 48,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(find.byType(CustomPaint), findsNothing);
    final box = tester.widget<SizedBox>(find.byType(SizedBox).first);
    expect(box.width, 64);
    expect(box.height, 48);
  });

  test('MockClient body is decoded as UTF-8 string for compile', () {
    final bytes = utf8.encode(_sampleSvg);
    final body = utf8.decode(bytes);
    final scene = SvgParser.compile(body);
    expect(scene.document.rootGroup, isNotNull);
    scene.dispose();
  });
}
