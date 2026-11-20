import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_container_nodes.dart';
import 'svg_document.dart';
import 'svg_preserve_aspect_ratio.dart';
import 'svg_transform.dart';

/// Coordinate unit system for `<marker markerUnits="...">`.
/// `<marker markerUnits="...">` 标记尺寸缩放单位枚举。
enum SvgMarkerUnits {
  /// Scales marker dimensions proportionally to the host shape's `stroke-width`. 按宿主描边宽度缩放。
  strokeWidth,

  /// Uses raw user-space coordinates without stroke-width scaling. 直接使用用户空间坐标。
  userSpaceOnUse,
}

/// Orientation mode for `<marker orient="...">`.
/// `<marker orient="...">` 标记朝向模式枚举。
enum SvgMarkerOrientMode {
  /// Fixed rotation angle in degrees (`orient="45deg"`). 固定旋转角度。
  fixedAngle,

  /// Aligns with the path vertex tangent (`orient="auto"`). 沿路径切线自动旋转。
  auto,

  /// Reverses by 180° at the start vertex and follows tangent elsewhere (`orient="auto-start-reverse"`).
  /// 起点反向旋转 180°，其余顶点沿切线方向。
  autoStartReverse,
}

/// Vertex placement and tangent orientation for marker rendering.
/// 标记渲染所需的顶点位置与切线方向描述对象。
class SvgMarkerVertex {
  /// Vertex X coordinate. 顶点 X 坐标。
  final double x;

  /// Vertex Y coordinate. 顶点 Y 坐标。
  final double y;

  /// Tangent angle at this vertex in radians. 顶点切线角度（弧度）。
  final double angleRad;

  /// Whether this is the first vertex (`marker-start`). 是否为起始顶点。
  final bool isStart;

  /// Whether this is the terminal vertex (`marker-end`). 是否为终止顶点。
  final bool isEnd;

  /// Creates an [SvgMarkerVertex]. 创建一个 [SvgMarkerVertex] 标记顶点描述。
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
/// `<marker>` 路径端点/顶点标记图形节点。
class SvgMarkerNode extends SvgGroupNode {
  /// Reference X coordinate aligned to the vertex (`refX`). 对齐顶点的参考 X 坐标。
  final double refX;

  /// Reference Y coordinate aligned to the vertex (`refY`). 对齐顶点的参考 Y 坐标。
  final double refY;

  /// Marker viewport width (`markerWidth`). 标记视口宽度。
  final double markerWidth;

  /// Marker viewport height (`markerHeight`). 标记视口高度。
  final double markerHeight;

  /// Marker unit scaling mode. 标记单位缩放模式。
  final SvgMarkerUnits markerUnits;

  /// Marker orientation mode. 标记朝向模式。
  final SvgMarkerOrientMode orientMode;

  /// Fixed rotation angle in degrees when [orientMode] is [SvgMarkerOrientMode.fixedAngle]. 固定角度（度）。
  final double fixedOrientDeg;

  /// Optional marker `viewBox`. 可选标记 `viewBox`。
  final ui.Rect? innerViewBox;

  /// Aspect ratio rule for [innerViewBox]. 标记 `viewBox` 长宽比规则。
  final SvgPreserveAspectRatio preserveAspectRatio;

  final Float64List _viewBoxMatrix = SvgMatrixMath.createIdentity();

  /// Creates an [SvgMarkerNode]. 创建一个 [SvgMarkerNode] 路径标记节点。
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

  /// Renders this marker at [vertex] on [canvas] with the host shape's [strokeWidth].
  /// 在顶点 [vertex] 处结合宿主线宽 [strokeWidth] 将当前标记绘制到 [canvas] 上。
  ///
  /// - [canvas]: Target Flutter canvas. 目标画布。
  /// - [document]: Owning [SvgDocument]. 所属 SVG 文档。
  /// - [vertex]: Vertex position and tangent angle. 顶点位置与切线角。
  /// - [strokeWidth]: Host element stroke width. 宿主元素描边宽度。
  /// - [effectiveOpacity]: Effective inherited opacity. 有效继承不透明度。
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
