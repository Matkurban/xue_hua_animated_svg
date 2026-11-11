import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_container_nodes.dart';
import 'svg_element.dart';
import 'svg_geometry_node.dart';
import 'svg_gradient.dart';
import 'svg_preserve_aspect_ratio.dart';
import 'svg_transform.dart';

/// Top-level precompiled `<svg>` document containing the scene graph, gradients,
/// defs, clipPaths, and precompiled animation timeline.
class SvgDocument {
  final double? width;
  final double? height;
  final ui.Rect viewBox;
  final SvgPreserveAspectRatio preserveAspectRatio;
  final SvgGroupNode rootGroup;

  final Map<String, SvgElement> elementsById;
  final Map<String, SvgElement> defsById;
  final Map<String, SvgGradientNode> gradientsById;
  final Map<String, SvgClipPathNode> clipPathsById;
  final Map<String, SvgGeometryNode> geometryById;

  /// Pre-allocated viewBox transformation matrix buffer.
  final Float64List viewBoxMatrix = SvgMatrixMath.createIdentity();

  SvgDocument({
    this.width,
    this.height,
    required this.viewBox,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
    required this.rootGroup,
    required this.elementsById,
    required this.defsById,
    required this.gradientsById,
    required this.clipPathsById,
    required this.geometryById,
  });

  /// Intrinsic size of the SVG document.
  ui.Size get intrinsicSize =>
      ui.Size(width ?? viewBox.width, height ?? viewBox.height);

  /// Initializes all node geometries, resolves gradient templates, and propagates
  /// `isAnimated` flags bottom-up through the AST.
  void initialize() {
    for (final gradient in gradientsById.values) {
      gradient.resolveTemplate(gradientsById);
    }
    for (final def in defsById.values) {
      def.initializeGeometry(this);
    }
    for (final clip in clipPathsById.values) {
      clip.initializeGeometry(this);
    }
    rootGroup.initializeGeometry(this);
    rootGroup.propagateAnimationFlags(this);
  }

  /// Paints the document at its current timeline state into [canvas] scaled to [canvasSize].
  void paint(ui.Canvas canvas, ui.Size canvasSize) {
    if (canvasSize.isEmpty) return;
    preserveAspectRatio.computeMatrixInPlace(
      viewBox,
      canvasSize,
      viewBoxMatrix,
    );
    canvas.save();
    canvas.transform(viewBoxMatrix);
    rootGroup.paint(canvas, this);
    canvas.restore();
  }

  /// Releases any cached `ui.Picture` instances held by static subtrees.
  void dispose() {
    rootGroup.dispose();
    for (final def in defsById.values) {
      def.dispose();
    }
  }
}
