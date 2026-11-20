import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_container_nodes.dart';
import 'svg_document.dart';
import 'svg_preserve_aspect_ratio.dart';
import 'svg_transform.dart';

/// Coordinate unit system for `<marker markerUnits="...">`.
enum SvgMarkerUnits { strokeWidth, userSpaceOnUse }

/// Orientation mode for `<marker orient="...">`.
enum SvgMarkerOrientMode { fixedAngle, auto, autoStartReverse }

/// Vertex placement & tangent orientation for marker rendering.
class SvgMarkerVertex {
  final double x;
  final double y;
  final double angleRad;
  final bool isStart;
  final bool isEnd;

  const SvgMarkerVertex({
    required this.x,
    required this.y,
    required this.angleRad,
    this.isStart = false,
    this.isEnd = false,
  });
}

/// `<marker>` graphic node rendered at start/mid/end vertices of `<path>`,
/// `<line>`, `<polyline>`, and `<polygon>` elements (W3C SVG 1.1 §11.6 / SVG 2).
class SvgMarkerNode extends SvgGroupNode {
  final double refX;
  final double refY;
  final double markerWidth;
  final double markerHeight;
  final SvgMarkerUnits markerUnits;
  final SvgMarkerOrientMode orientMode;
  final double fixedOrientDeg;
  final ui.Rect? innerViewBox;
  final SvgPreserveAspectRatio preserveAspectRatio;

  final Float64List _viewBoxMatrix = SvgMatrixMath.createIdentity();

  SvgMarkerNode({
    super.id,
    super.classes,
    required super.style,
    super.children,
    this.refX = 0.0,
    this.refY = 0.0,
    this.markerWidth = 3.0,
    this.markerHeight = 3.0,
    this.markerUnits = SvgMarkerUnits.strokeWidth,
    this.orientMode = SvgMarkerOrientMode.fixedAngle,
    this.fixedOrientDeg = 0.0,
    this.innerViewBox,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
  }) : super(tagName: 'marker');

  bool get _overflowHidden => style.baseOverflowVisible != true;

  @override
  bool get shouldCacheStaticPicture => false;

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <marker> is never painted directly; only at vertices via paintAtVertex().
  }

  /// Renders this marker at [vertex] with the host shape's [strokeWidth].
  void paintAtVertex({
    required ui.Canvas canvas,
    required SvgDocument document,
    required SvgMarkerVertex vertex,
    required double strokeWidth,
    required double effectiveOpacity,
  }) {
    if (style.displayNone || markerWidth <= 0.0 || markerHeight <= 0.0) return;

    final double unitScale = markerUnits == SvgMarkerUnits.strokeWidth
        ? strokeWidth
        : 1.0;
    if (unitScale <= 0.0) return;

    final double angleRad;
    switch (orientMode) {
      case SvgMarkerOrientMode.fixedAngle:
        angleRad = fixedOrientDeg * SvgMatrixMath.degToRad;
      case SvgMarkerOrientMode.auto:
        angleRad = vertex.angleRad;
      case SvgMarkerOrientMode.autoStartReverse:
        angleRad = vertex.isStart
            ? (vertex.angleRad + math.pi)
            : vertex.angleRad;
    }

    canvas.save();
    canvas.translate(vertex.x, vertex.y);
    if (angleRad != 0.0) {
      canvas.rotate(angleRad);
    }

    final viewportW = markerWidth * unitScale;
    final viewportH = markerHeight * unitScale;

    if (innerViewBox != null) {
      preserveAspectRatio.computeMatrixInPlace(
        innerViewBox!,
        ui.Size(viewportW, viewportH),
        _viewBoxMatrix,
      );
      // Align (refX, refY) in viewBox coordinates to the vertex origin (0, 0)
      final tx =
          _viewBoxMatrix[0] * refX +
          _viewBoxMatrix[4] * refY +
          _viewBoxMatrix[12];
      final ty =
          _viewBoxMatrix[1] * refX +
          _viewBoxMatrix[5] * refY +
          _viewBoxMatrix[13];
      canvas.translate(-tx, -ty);
      if (_overflowHidden) {
        canvas.clipRect(ui.Rect.fromLTWH(0.0, 0.0, viewportW, viewportH));
      }
      canvas.transform(_viewBoxMatrix);
    } else {
      if (unitScale != 1.0) {
        canvas.scale(unitScale, unitScale);
      }
      canvas.translate(-refX, -refY);
      if (_overflowHidden) {
        canvas.clipRect(ui.Rect.fromLTWH(0.0, 0.0, markerWidth, markerHeight));
      }
    }

    super.paintContent(canvas, document, effectiveOpacity);
    canvas.restore();
  }
}
