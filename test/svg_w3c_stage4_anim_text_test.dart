import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_animated_svg/src/animation/svg_step_easing.dart';
import 'package:xue_hua_animated_svg/src/model/svg_node.dart';
import 'package:xue_hua_animated_svg/src/parser/svg_xml_parser.dart';

void main() {
  group('W3C Stage 4: SMIL additive/accumulate & Syncbase Timing', () {
    test('stacks multiple <animateTransform additive="sum"> tracks', () {
      const svg = '''
        <svg viewBox="0 0 200 200">
          <rect id="box" x="0" y="0" width="20" height="20" fill="#ff0000">
            <animateTransform attributeName="transform" type="translate"
              from="0 0" to="40 0" dur="1s" fill="freeze" />
            <animateTransform attributeName="transform" type="translate"
              from="0 0" to="0 60" dur="1s" additive="sum" fill="freeze" />
          </rect>
        </svg>
      ''';
      final scene = SvgParser.compile(svg);
      addTearDown(scene.dispose);

      scene.timeline.seekMicroseconds(500000);
      final box = scene.document.elementsById['box'] as SvgRectNode;
      // Column-major 4x4 matrix: m[12] = tx, m[13] = ty
      expect(box.transformMatrix[12], closeTo(20.0, 1e-4));
      expect(box.transformMatrix[13], closeTo(30.0, 1e-4));

      scene.timeline.seekMicroseconds(1000000);
      expect(box.transformMatrix[12], closeTo(40.0, 1e-4));
      expect(box.transformMatrix[13], closeTo(60.0, 1e-4));
    });

    test('accumulates repeated cycles with SMIL accumulate="sum"', () {
      const svg = '''
        <svg viewBox="0 0 300 100">
          <rect id="mover" x="0" y="10" width="20" height="20" fill="#00ff00">
            <animate attributeName="x" from="0" to="50" dur="1s"
              repeatCount="3" accumulate="sum" fill="freeze" />
          </rect>
          <rect id="scaler" x="0" y="40" width="10" height="10" fill="#0000ff">
            <animateTransform attributeName="transform" type="scale"
              from="1 1" to="2 2" dur="1s"
              repeatCount="3" accumulate="sum" fill="freeze" />
          </rect>
        </svg>
      ''';
      final scene = SvgParser.compile(svg);
      addTearDown(scene.dispose);

      final mover = scene.document.elementsById['mover'] as SvgRectNode;
      final scaler = scene.document.elementsById['scaler'] as SvgRectNode;

      // Cycle 0 at t = 0.5s -> x = 25, scale = 1.5
      scene.timeline.seekMicroseconds(500000);
      expect(mover.currentX, closeTo(25.0, 1e-4));
      expect(scaler.transformMatrix[0], closeTo(1.5, 1e-4));

      // Cycle 1 at t = 1.5s -> x = 25 + 50*1 = 75, scale = 1.5 * 2^1 = 3.0
      scene.timeline.seekMicroseconds(1500000);
      expect(mover.currentX, closeTo(75.0, 1e-4));
      expect(scaler.transformMatrix[0], closeTo(3.0, 1e-4));

      // Frozen at end of cycle 2 (t = 3.0s) -> x = 50 + 50*2 = 150, scale = 2 * 2^2 = 8.0
      scene.timeline.seekMicroseconds(3000000);
      expect(mover.currentX, closeTo(150.0, 1e-4));
      expect(scaler.transformMatrix[0], closeTo(8.0, 1e-4));
    });

    test(
      'resolves SMIL syncbase timing chains (id.end+offset & id.begin+offset)',
      () {
        const svg = '''
        <svg viewBox="0 0 200 100">
          <rect id="r2" x="0" y="50" width="20" height="20" fill="#0000ff">
            <animate id="a2" attributeName="x" from="0" to="100"
              begin="a1.end+0.5s" dur="1s" fill="freeze" />
          </rect>
          <rect id="r1" x="0" y="10" width="20" height="20" fill="#ff0000">
            <animate id="a1" attributeName="x" from="0" to="100"
              begin="0.2s" dur="1s" fill="freeze" />
          </rect>
          <rect id="r3" x="0" y="80" width="20" height="20" fill="#00aa00">
            <animate id="a3" attributeName="x" from="0" to="80"
              begin="a2.begin+0.3s" dur="1s" fill="freeze" />
          </rect>
        </svg>
      ''';
        final scene = SvgParser.compile(svg);
        addTearDown(scene.dispose);

        // a1: [0.2s .. 1.2s]
        // a2: begins at 1.2s + 0.5s = 1.7s -> [1.7s .. 2.7s]
        // a3: begins at 1.7s + 0.3s = 2.0s -> [2.0s .. 3.0s]
        final r1 = scene.document.elementsById['r1'] as SvgRectNode;
        final r2 = scene.document.elementsById['r2'] as SvgRectNode;
        final r3 = scene.document.elementsById['r3'] as SvgRectNode;

        scene.timeline.seekMicroseconds(1500000); // t = 1.5s
        expect(r1.currentX, closeTo(100.0, 1e-4));
        expect(r2.currentX, closeTo(0.0, 1e-4)); // not started yet
        expect(r3.currentX, closeTo(0.0, 1e-4));

        scene.timeline.seekMicroseconds(2200000); // t = 2.2s
        expect(r2.currentX, closeTo(50.0, 1e-4)); // 0.5s into [1.7s..2.7s]
        expect(r3.currentX, closeTo(16.0, 1e-4)); // 0.2s into [2.0s..3.0s]

        expect(scene.timeline.finiteDuration, const Duration(seconds: 3));
      },
    );
  });

  group('W3C Stage 4: CSS steps(), Negative Delay & animation-play-state', () {
    test('evaluates W3C CSS steps(N, <position>) accurately', () {
      final jumpEnd = SvgStepEasing.parse('steps(4, jump-end)')!;
      expect(jumpEnd.transform(0.0), closeTo(0.0, 1e-6));
      expect(jumpEnd.transform(0.24), closeTo(0.0, 1e-6));
      expect(jumpEnd.transform(0.25), closeTo(0.25, 1e-6));
      expect(jumpEnd.transform(0.75), closeTo(0.75, 1e-6));
      expect(jumpEnd.transform(1.0), closeTo(1.0, 1e-6));

      final jumpStart = SvgStepEasing.parse('steps(4, jump-start)')!;
      expect(jumpStart.transform(0.0), closeTo(0.25, 1e-6));
      expect(jumpStart.transform(0.25), closeTo(0.5, 1e-6));
      expect(jumpStart.transform(0.75), closeTo(1.0, 1e-6));

      final jumpNone = SvgStepEasing.parse('steps(4, jump-none)')!;
      expect(jumpNone.transform(0.0), closeTo(0.0, 1e-6));
      expect(jumpNone.transform(0.25), closeTo(1.0 / 3.0, 1e-6));
      expect(jumpNone.transform(0.5), closeTo(2.0 / 3.0, 1e-6));
      expect(jumpNone.transform(0.75), closeTo(1.0, 1e-6));

      final jumpBoth = SvgStepEasing.parse('steps(4, jump-both)')!;
      expect(jumpBoth.transform(0.0), closeTo(0.2, 1e-6));
      expect(jumpBoth.transform(0.25), closeTo(0.4, 1e-6));
      expect(jumpBoth.transform(0.75), closeTo(0.8, 1e-6));

      expect(
        SvgStepEasing.parse('step-start')!.transform(0.0),
        closeTo(1.0, 1e-6),
      );
      expect(
        SvgStepEasing.parse('step-end')!.transform(0.99),
        closeTo(0.0, 1e-6),
      );
    });

    test('applies CSS steps(), negative animation-delay, and paused state', () {
      const svg = '''
        <svg viewBox="0 0 200 200">
          <style>
            @keyframes fade {
              from { opacity: 0; }
              to { opacity: 1; }
            }
            #stepped {
              animation: fade 2s steps(4, jump-end) forwards;
            }
            #negDelay {
              animation: fade 2s linear -1s forwards;
            }
            #paused {
              animation: fade 2s linear -0.5s forwards;
              animation-play-state: paused;
            }
          </style>
          <rect id="stepped" x="0" y="0" width="20" height="20" fill="#ff0000" />
          <rect id="negDelay" x="30" y="0" width="20" height="20" fill="#00ff00" />
          <rect id="paused" x="60" y="0" width="20" height="20" fill="#0000ff" />
        </svg>
      ''';
      final scene = SvgParser.compile(svg);
      addTearDown(scene.dispose);

      final stepped = scene.document.elementsById['stepped'] as SvgRectNode;
      final negDelay = scene.document.elementsById['negDelay'] as SvgRectNode;
      final paused = scene.document.elementsById['paused'] as SvgRectNode;

      // At t = 0:
      // - stepped is at step 0 -> 0.0
      // - negDelay has -1s delay on 2s duration -> starts at 0.5
      // - paused has -0.5s delay and is paused -> frozen at 0.25
      expect(stepped.style.currentOpacity, closeTo(0.0, 1e-4));
      expect(negDelay.style.currentOpacity, closeTo(0.5, 1e-4));
      expect(paused.style.currentOpacity, closeTo(0.25, 1e-4));

      // At t = 0.6s (30% of 2s -> step 1 of 4 -> 0.25):
      scene.timeline.seekMicroseconds(600000);
      expect(stepped.style.currentOpacity, closeTo(0.25, 1e-4));
      expect(negDelay.style.currentOpacity, closeTo(0.8, 1e-4));
      // Still paused at 0.25!
      expect(paused.style.currentOpacity, closeTo(0.25, 1e-4));
    });
  });

  group('W3C Stage 4: Text text-transform & Vertical writing-mode', () {
    test(
      'parses text-transform and writing-mode and lays out vertical text',
      () {
        const svg = '''
        <svg viewBox="0 0 200 200">
          <text id="upper" x="10" y="30" font-size="16" style="text-transform: uppercase;">hello world</text>
          <text id="cap" x="10" y="60" font-size="16" text-transform="capitalize">hello-world test</text>
          <text id="vert" x="100" y="20" font-size="16" writing-mode="vertical-rl">ABCD</text>
        </svg>
      ''';
        final scene = SvgParser.compile(svg);
        addTearDown(scene.dispose);

        final upper = scene.document.elementsById['upper'] as SvgTextNode;
        final cap = scene.document.elementsById['cap'] as SvgTextNode;
        final vert = scene.document.elementsById['vert'] as SvgTextNode;

        expect(upper.style.currentTextTransform, SvgTextTransform.uppercase);
        expect(cap.style.currentTextTransform, SvgTextTransform.capitalize);
        expect(vert.style.currentWritingMode, SvgWritingMode.verticalRl);

        // Vertical text of 4 characters should be taller than it is wide
        expect(vert.cachedBounds.height, greaterThan(vert.cachedBounds.width));

        // Verify painting completes cleanly without error
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        scene.document.paint(canvas, const ui.Size(200, 200));
        final picture = recorder.endRecording();
        picture.dispose();
      },
    );
  });
}
