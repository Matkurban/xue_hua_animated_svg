import 'dart:ui' as ui;

import 'svg_container_nodes.dart';
import 'svg_document.dart';
import 'svg_gradient.dart';

/// How `<mask>` pixel values map to transparency (SVG 2 `mask-type`).
enum SvgMaskType {
  /// Standard SVG luminance mask: `alpha = 0.2126*R + 0.7152*G + 0.0722*B`.
  luminance,

  /// Direct alpha channel mask (`mask-type: alpha`).
  alpha,
}

/// `<mask>` compositing container node (W3C SVG 1.1 §14.4 / SVG 2).
class SvgMaskNode extends SvgGroupNode {
  final SvgGradientUnits maskUnits;
  final SvgGradientUnits maskContentUnits;
  final SvgMaskType maskType;
  final double x;
  final double y;
  final double width;
  final double height;

  /// Rec.709 luminance-to-alpha color filter matrix per W3C SVG masking spec.
  static const ui.ColorFilter luminanceToAlphaFilter = ui.ColorFilter.matrix(
    <double>[
      0.0, 0.0, 0.0, 0.0, 0.0, // R
      0.0, 0.0, 0.0, 0.0, 0.0, // G
      0.0, 0.0, 0.0, 0.0, 0.0, // B
      0.2126, 0.7152, 0.0722, 0.0, 0.0, // A = luminance
    ],
  );

  SvgMaskNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    super.children,
    this.maskUnits = SvgGradientUnits.objectBoundingBox,
    this.maskContentUnits = SvgGradientUnits.userSpaceOnUse,
    this.maskType = SvgMaskType.luminance,
    this.x = -0.1,
    this.y = -0.1,
    this.width = 1.2,
    this.height = 1.2,
  }) : super(tagName: 'mask');

  @override
  bool get shouldCacheStaticPicture => false;

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <mask> is never painted directly; it is applied via applyMask().
  }

  /// Resolves the mask clipping/layer bounds in target user space.
  ui.Rect resolveMaskRegion(ui.Rect targetBounds) {
    if (maskUnits == SvgGradientUnits.objectBoundingBox) {
      return ui.Rect.fromLTWH(
        targetBounds.left + x * targetBounds.width,
        targetBounds.top + y * targetBounds.height,
        width * targetBounds.width,
        height * targetBounds.height,
      );
    }
    return ui.Rect.fromLTWH(x, y, width, height);
  }

  /// Renders the mask's children into the active `dstIn` mask layer.
  void paintMaskContent(
    ui.Canvas canvas,
    SvgDocument document,
    ui.Rect targetBounds,
  ) {
    final isBBoxContent =
        maskContentUnits == SvgGradientUnits.objectBoundingBox;
    if (isBBoxContent) {
      if (targetBounds.width <= 0.0 || targetBounds.height <= 0.0) return;
      canvas.save();
      canvas.translate(targetBounds.left, targetBounds.top);
      canvas.scale(targetBounds.width, targetBounds.height);
    }

    super.paintContent(canvas, document, 1.0);

    if (isBBoxContent) {
      canvas.restore();
    }
  }
}
