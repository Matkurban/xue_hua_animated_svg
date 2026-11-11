import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../controller/animated_svg_controller.dart';
import '../parser/svg_xml_parser.dart';

/// Zero-allocation [CustomPainter] that advances the precompiled `SvgTimelineEngine`
/// and paints the `SvgDocument` scene graph directly onto the [ui.Canvas].
class AnimatedSvgPainter extends CustomPainter {
  final CompiledSvgScene scene;
  final AnimatedSvgController controller;
  final Clip clipBehavior;
  final BoxFit fit;
  final Alignment alignment;

  AnimatedSvgPainter({
    required this.scene,
    required this.controller,
    this.clipBehavior = Clip.hardEdge,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
  }) : super(repaint: controller);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (size.isEmpty) return;

    // 1. Evaluate all precompiled SMIL & CSS animation tracks in-place
    scene.timeline.seekMicroseconds(controller.elapsedMicroseconds);

    final intrinsic = scene.document.intrinsicSize;
    if (intrinsic.width <= 0.0 || intrinsic.height <= 0.0) {
      return;
    }

    // 2. Fit the SVG intrinsic box into the widget layout size.
    //    [alignment] places the fitted rect inside leftover / cropped space.
    final fitted = applyBoxFit(fit, intrinsic, size);
    if (fitted.source.isEmpty || fitted.destination.isEmpty) {
      return;
    }
    final inputSubrect = alignment.inscribe(
      fitted.source,
      ui.Offset.zero & intrinsic,
    );
    final outputSubrect = alignment.inscribe(
      fitted.destination,
      ui.Offset.zero & size,
    );

    canvas.save();
    if (clipBehavior != Clip.none) {
      canvas.clipRect(ui.Offset.zero & size);
    }

    final scaleX = outputSubrect.width / inputSubrect.width;
    final scaleY = outputSubrect.height / inputSubrect.height;
    canvas.translate(outputSubrect.left, outputSubrect.top);
    canvas.scale(scaleX, scaleY);
    canvas.translate(-inputSubrect.left, -inputSubrect.top);

    // Paint into the intrinsic viewport; SVG preserveAspectRatio still applies
    // for viewBox → intrinsic. Widget [fit] then maps intrinsic → [size].
    scene.document.paint(canvas, intrinsic);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AnimatedSvgPainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.controller != controller ||
        oldDelegate.clipBehavior != clipBehavior ||
        oldDelegate.fit != fit ||
        oldDelegate.alignment != alignment;
  }
}
