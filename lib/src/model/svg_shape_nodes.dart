import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_geometry_node.dart';
import 'svg_marker_node.dart';
import 'svg_precompiled_path.dart';

/// `<path>` node supporting static path caching and isomorphic `d` path morphing.
/// `<path>` 路径图元节点，支持静态路径缓存与同构 `d` 路径形变。
class SvgPathNode extends SvgGeometryNode {
  /// Precompiled canonical path commands and base coordinates. 预编译规范路径指令与基础坐标。
  final PrecompiledSvgPath precompiledPath;

  /// Optional raw XML `d` attribute string retained as fallback for SMIL `from`. 原始 `d` 属性字符串。
  final String? xmlBaseD;

  /// Pre-allocated coordinate buffer used when `<animate attributeName="d">` morphs this path.
  /// 路径形变动画使用的预分配插值坐标缓冲。
  late final Float64List morphedCoords;

  /// Whether [morphedCoords] currently holds interpolated morph coordinates. 当前是否处于形变状态。
  bool isMorphed = false;

  /// Creates an [SvgPathNode]. 创建一个 [SvgPathNode] 路径节点。
  SvgPathNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    required this.precompiledPath,
    this.xmlBaseD,
  }) : super(tagName: 'path') {
    morphedCoords = Float64List.fromList(precompiledPath.coords);
  }

  @override
  void resetFrameState() {
    super.resetFrameState();
    if (isMorphed) {
      for (int i = 0; i < precompiledPath.coords.length; i++) {
        morphedCoords[i] = precompiledPath.coords[i];
      }
      isMorphed = false;
      markGeometryDirty();
    }
  }

  @override
  void buildPath(ui.Path outPath) {
    precompiledPath.buildUiPath(outPath, isMorphed ? morphedCoords : null);
  }

  @override
  List<SvgMarkerVertex> extractMarkerVertices() {
    final c = isMorphed ? morphedCoords : precompiledPath.coords;
    final cmds = precompiledPath.commands;
    if (cmds.isEmpty) return const [];

    final segs = <_PathMarkerSegment>[];
    double curX = 0.0;
    double curY = 0.0;
    double subStartX = 0.0;
    double subStartY = 0.0;
    int offset = 0;

    for (int i = 0; i < cmds.length; i++) {
      switch (cmds[i]) {
        case SvgPathCmdType.moveTo:
          curX = c[offset];
          curY = c[offset + 1];
          subStartX = curX;
          subStartY = curY;
          offset += 2;
        case SvgPathCmdType.lineTo:
          final ex = c[offset];
          final ey = c[offset + 1];
          offset += 2;
          segs.add(
            _PathMarkerSegment(
              curX,
              curY,
              ex,
              ey,
              ex - curX,
              ey - curY,
              ex - curX,
              ey - curY,
            ),
          );
          curX = ex;
          curY = ey;
        case SvgPathCmdType.quadTo:
          final qx = c[offset];
          final qy = c[offset + 1];
          final ex = c[offset + 2];
          final ey = c[offset + 3];
          offset += 4;
          final odx = (qx != curX || qy != curY) ? qx - curX : ex - curX;
          final ody = (qx != curX || qy != curY) ? qy - curY : ey - curY;
          final idx = (ex != qx || ey != qy) ? ex - qx : ex - curX;
          final idy = (ex != qx || ey != qy) ? ey - qy : ey - curY;
          segs.add(_PathMarkerSegment(curX, curY, ex, ey, odx, ody, idx, idy));
          curX = ex;
          curY = ey;
        case SvgPathCmdType.cubicTo:
          final c1x = c[offset];
          final c1y = c[offset + 1];
          final c2x = c[offset + 2];
          final c2y = c[offset + 3];
          final ex = c[offset + 4];
          final ey = c[offset + 5];
          offset += 6;
          double odx = c1x - curX;
          double ody = c1y - curY;
          if (odx == 0.0 && ody == 0.0) {
            odx = c2x - curX;
            ody = c2y - curY;
          }
          if (odx == 0.0 && ody == 0.0) {
            odx = ex - curX;
            ody = ey - curY;
          }
          double idx = ex - c2x;
          double idy = ey - c2y;
          if (idx == 0.0 && idy == 0.0) {
            idx = ex - c1x;
            idy = ey - c1y;
          }
          if (idx == 0.0 && idy == 0.0) {
            idx = ex - curX;
            idy = ey - curY;
          }
          segs.add(_PathMarkerSegment(curX, curY, ex, ey, odx, ody, idx, idy));
          curX = ex;
          curY = ey;
        case SvgPathCmdType.arcTo:
          final ex = c[offset + 5];
          final ey = c[offset + 6];
          offset += 7;
          segs.add(
            _PathMarkerSegment(
              curX,
              curY,
              ex,
              ey,
              ex - curX,
              ey - curY,
              ex - curX,
              ey - curY,
            ),
          );
          curX = ex;
          curY = ey;
        case SvgPathCmdType.close:
          if ((curX - subStartX).abs() > 1e-6 ||
              (curY - subStartY).abs() > 1e-6) {
            segs.add(
              _PathMarkerSegment(
                curX,
                curY,
                subStartX,
                subStartY,
                subStartX - curX,
                subStartY - curY,
                subStartX - curX,
                subStartY - curY,
              ),
            );
            curX = subStartX;
            curY = subStartY;
          }
      }
    }

    if (segs.isEmpty) return const [];
    final vertices = <SvgMarkerVertex>[];
    final first = segs.first;
    vertices.add(
      SvgMarkerVertex(
        x: first.sx,
        y: first.sy,
        angleRad: math.atan2(first.ody, first.odx),
        isStart: true,
      ),
    );
    for (int i = 0; i < segs.length - 1; i++) {
      final prev = segs[i];
      final next = segs[i + 1];
      final angle = _bisectorAngle(prev.idx, prev.idy, next.odx, next.ody);
      vertices.add(SvgMarkerVertex(x: prev.ex, y: prev.ey, angleRad: angle));
    }
    final last = segs.last;
    vertices.add(
      SvgMarkerVertex(
        x: last.ex,
        y: last.ey,
        angleRad: math.atan2(last.idy, last.idx),
        isEnd: true,
      ),
    );
    return vertices;
  }
}

/// `<rect>` node with animatable `x`, `y`, `width`, `height`, `rx`, `ry`.
/// `<rect>` 矩形/圆角矩形图元节点，支持几何属性动画。
class SvgRectNode extends SvgGeometryNode {
  /// Base X coordinate. 基础 X 坐标。
  final double baseX;

  /// Base Y coordinate. 基础 Y 坐标。
  final double baseY;

  /// Base width. 基础宽度。
  final double baseWidth;

  /// Base height. 基础高度。
  final double baseHeight;

  /// Base horizontal corner radius `rx`. 基础水平圆角半径。
  final double baseRx;

  /// Base vertical corner radius `ry`. 基础垂直圆角半径。
  final double baseRy;

  /// Active runtime X coordinate. 运行时 X 坐标。
  double currentX;

  /// Active runtime Y coordinate. 运行时 Y 坐标。
  double currentY;

  /// Active runtime width. 运行时宽度。
  double currentWidth;

  /// Active runtime height. 运行时高度。
  double currentHeight;

  /// Active runtime horizontal corner radius. 运行时水平圆角半径。
  double currentRx;

  /// Active runtime vertical corner radius. 运行时垂直圆角半径。
  double currentRy;

  /// Creates an [SvgRectNode]. 创建一个 [SvgRectNode] 矩形节点。
  SvgRectNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.baseX = 0.0,
    this.baseY = 0.0,
    required this.baseWidth,
    required this.baseHeight,
    this.baseRx = 0.0,
    this.baseRy = 0.0,
  }) : currentX = baseX,
       currentY = baseY,
       currentWidth = baseWidth,
       currentHeight = baseHeight,
       currentRx = baseRx,
       currentRy = baseRy,
       super(tagName: 'rect');

  @override
  void resetFrameState() {
    super.resetFrameState();
    if (currentX != baseX ||
        currentY != baseY ||
        currentWidth != baseWidth ||
        currentHeight != baseHeight ||
        currentRx != baseRx ||
        currentRy != baseRy) {
      currentX = baseX;
      currentY = baseY;
      currentWidth = baseWidth;
      currentHeight = baseHeight;
      currentRx = baseRx;
      currentRy = baseRy;
      markGeometryDirty();
    }
  }

  @override
  void buildPath(ui.Path outPath) {
    if (currentWidth <= 0.0 || currentHeight <= 0.0) return;
    final rect = ui.Rect.fromLTWH(
      currentX,
      currentY,
      currentWidth,
      currentHeight,
    );
    if (currentRx > 0.0 || currentRy > 0.0) {
      final rx = currentRx > 0.0 ? currentRx : currentRy;
      final ry = currentRy > 0.0 ? currentRy : currentRx;
      outPath.addRRect(
        ui.RRect.fromRectXY(
          rect,
          math.min(rx, currentWidth * 0.5),
          math.min(ry, currentHeight * 0.5),
        ),
      );
    } else {
      outPath.addRect(rect);
    }
  }
}

/// `<circle>` node with animatable `cx`, `cy`, `r`.
/// `<circle>` 圆形图元节点，支持圆心与半径动画。
class SvgCircleNode extends SvgGeometryNode {
  /// Base center X (`cx`). 基础圆心 X。
  final double baseCx;

  /// Base center Y (`cy`). 基础圆心 Y。
  final double baseCy;

  /// Base radius (`r`). 基础半径。
  final double baseR;

  /// Active runtime center X. 运行时圆心 X。
  double currentCx;

  /// Active runtime center Y. 运行时圆心 Y。
  double currentCy;

  /// Active runtime radius. 运行时半径。
  double currentR;

  /// Creates an [SvgCircleNode]. 创建一个 [SvgCircleNode] 圆形节点。
  SvgCircleNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.baseCx = 0.0,
    this.baseCy = 0.0,
    required this.baseR,
  }) : currentCx = baseCx,
       currentCy = baseCy,
       currentR = baseR,
       super(tagName: 'circle');

  @override
  void resetFrameState() {
    super.resetFrameState();
    if (currentCx != baseCx || currentCy != baseCy || currentR != baseR) {
      currentCx = baseCx;
      currentCy = baseCy;
      currentR = baseR;
      markGeometryDirty();
    }
  }

  @override
  void buildPath(ui.Path outPath) {
    if (currentR <= 0.0) return;
    outPath.addOval(
      ui.Rect.fromCircle(
        center: ui.Offset(currentCx, currentCy),
        radius: currentR,
      ),
    );
  }
}

/// `<ellipse>` node with animatable `cx`, `cy`, `rx`, `ry`.
/// `<ellipse>` 椭圆图元节点，支持中心与半轴动画。
class SvgEllipseNode extends SvgGeometryNode {
  /// Base center X (`cx`). 基础中心 X。
  final double baseCx;

  /// Base center Y (`cy`). 基础中心 Y。
  final double baseCy;

  /// Base horizontal radius (`rx`). 基础水平半轴。
  final double baseRx;

  /// Base vertical radius (`ry`). 基础垂直半轴。
  final double baseRy;

  /// Active runtime center X. 运行时中心 X。
  double currentCx;

  /// Active runtime center Y. 运行时中心 Y。
  double currentCy;

  /// Active runtime horizontal radius. 运行时水平半轴。
  double currentRx;

  /// Active runtime vertical radius. 运行时垂直半轴。
  double currentRy;

  /// Creates an [SvgEllipseNode]. 创建一个 [SvgEllipseNode] 椭圆节点。
  SvgEllipseNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.baseCx = 0.0,
    this.baseCy = 0.0,
    required this.baseRx,
    required this.baseRy,
  }) : currentCx = baseCx,
       currentCy = baseCy,
       currentRx = baseRx,
       currentRy = baseRy,
       super(tagName: 'ellipse');

  @override
  void resetFrameState() {
    super.resetFrameState();
    if (currentCx != baseCx ||
        currentCy != baseCy ||
        currentRx != baseRx ||
        currentRy != baseRy) {
      currentCx = baseCx;
      currentCy = baseCy;
      currentRx = baseRx;
      currentRy = baseRy;
      markGeometryDirty();
    }
  }

  @override
  void buildPath(ui.Path outPath) {
    if (currentRx <= 0.0 || currentRy <= 0.0) return;
    outPath.addOval(
      ui.Rect.fromCenter(
        center: ui.Offset(currentCx, currentCy),
        width: currentRx * 2.0,
        height: currentRy * 2.0,
      ),
    );
  }
}

/// `<line>` node with animatable `x1`, `y1`, `x2`, `y2`.
/// `<line>` 线段图元节点，支持起止端点坐标动画。
class SvgLineNode extends SvgGeometryNode {
  /// Base start X (`x1`). 基础起点 X。
  final double baseX1;

  /// Base start Y (`y1`). 基础起点 Y。
  final double baseY1;

  /// Base end X (`x2`). 基础终点 X。
  final double baseX2;

  /// Base end Y (`y2`). 基础终点 Y。
  final double baseY2;

  /// Active runtime start X. 运行时起点 X。
  double currentX1;

  /// Active runtime start Y. 运行时起点 Y。
  double currentY1;

  /// Active runtime end X. 运行时终点 X。
  double currentX2;

  /// Active runtime end Y. 运行时终点 Y。
  double currentY2;

  /// Creates an [SvgLineNode]. 创建一个 [SvgLineNode] 线段节点。
  SvgLineNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.baseX1 = 0.0,
    this.baseY1 = 0.0,
    this.baseX2 = 0.0,
    this.baseY2 = 0.0,
  }) : currentX1 = baseX1,
       currentY1 = baseY1,
       currentX2 = baseX2,
       currentY2 = baseY2,
       super(tagName: 'line');

  @override
  void resetFrameState() {
    super.resetFrameState();
    if (currentX1 != baseX1 ||
        currentY1 != baseY1 ||
        currentX2 != baseX2 ||
        currentY2 != baseY2) {
      currentX1 = baseX1;
      currentY1 = baseY1;
      currentX2 = baseX2;
      currentY2 = baseY2;
      markGeometryDirty();
    }
  }

  @override
  void buildPath(ui.Path outPath) {
    outPath.moveTo(currentX1, currentY1);
    outPath.lineTo(currentX2, currentY2);
  }

  @override
  List<SvgMarkerVertex> extractMarkerVertices() {
    final angle = math.atan2(currentY2 - currentY1, currentX2 - currentX1);
    return [
      SvgMarkerVertex(
        x: currentX1,
        y: currentY1,
        angleRad: angle,
        isStart: true,
      ),
      SvgMarkerVertex(x: currentX2, y: currentY2, angleRad: angle, isEnd: true),
    ];
  }
}

/// `<polyline>` or `<polygon>` node with precompiled coordinate list.
/// `<polyline>` 折线或 `<polygon>` 多边形图元节点。
class SvgPolyNode extends SvgGeometryNode {
  /// Interleaved `(x, y)` vertex coordinate array. 交替排列的 `(x, y)` 顶点坐标数组。
  final Float64List points;

  /// Whether to close the path (`true` for `<polygon>`, `false` for `<polyline>`). 是否闭合路径。
  final bool closePath;

  /// Creates an [SvgPolyNode]. 创建一个 [SvgPolyNode] 折线/多边形节点。
  SvgPolyNode({
    required super.tagName,
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    required this.points,
    required this.closePath,
  });

  @override
  void buildPath(ui.Path outPath) {
    if (points.length < 2) return;
    outPath.moveTo(points[0], points[1]);
    for (int i = 2; i + 1 < points.length; i += 2) {
      outPath.lineTo(points[i], points[i + 1]);
    }
    if (closePath) {
      outPath.close();
    }
  }

  @override
  List<SvgMarkerVertex> extractMarkerVertices() {
    final count = points.length ~/ 2;
    if (count < 2) return const [];
    final vertices = <SvgMarkerVertex>[];
    for (int i = 0; i < count; i++) {
      final x = points[i * 2];
      final y = points[i * 2 + 1];
      final bool hasIn = i > 0;
      final bool hasOut = i < count - 1;
      final inDx = hasIn ? x - points[(i - 1) * 2] : 0.0;
      final inDy = hasIn ? y - points[(i - 1) * 2 + 1] : 0.0;
      final outDx = hasOut
          ? points[(i + 1) * 2] - x
          : (closePath ? points[0] - x : 0.0);
      final outDy = hasOut
          ? points[(i + 1) * 2 + 1] - y
          : (closePath ? points[1] - y : 0.0);
      final double angle;
      if (hasIn && (hasOut || closePath)) {
        angle = _bisectorAngle(inDx, inDy, outDx, outDy);
      } else if (hasOut || closePath) {
        angle = math.atan2(outDy, outDx);
      } else {
        angle = math.atan2(inDy, inDx);
      }
      vertices.add(
        SvgMarkerVertex(
          x: x,
          y: y,
          angleRad: angle,
          isStart: i == 0,
          isEnd: !closePath && i == count - 1,
        ),
      );
    }
    if (closePath) {
      final lastX = points[(count - 1) * 2];
      final lastY = points[(count - 1) * 2 + 1];
      final closeAngle = math.atan2(points[1] - lastY, points[0] - lastX);
      vertices.add(
        SvgMarkerVertex(
          x: points[0],
          y: points[1],
          angleRad: closeAngle,
          isEnd: true,
        ),
      );
    }
    return vertices;
  }
}

class _PathMarkerSegment {
  final double sx, sy, ex, ey, odx, ody, idx, idy;

  const _PathMarkerSegment(
    this.sx,
    this.sy,
    this.ex,
    this.ey,
    this.odx,
    this.ody,
    this.idx,
    this.idy,
  );
}

double _bisectorAngle(double inDx, double inDy, double outDx, double outDy) {
  final inLen = math.sqrt(inDx * inDx + inDy * inDy);
  final outLen = math.sqrt(outDx * outDx + outDy * outDy);
  if (inLen <= 1e-9 && outLen <= 1e-9) return 0.0;
  if (inLen <= 1e-9) return math.atan2(outDy, outDx);
  if (outLen <= 1e-9) return math.atan2(inDy, inDx);
  final bx = (inDx / inLen) + (outDx / outLen);
  final by = (inDy / inLen) + (outDy / outLen);
  if (bx.abs() <= 1e-9 && by.abs() <= 1e-9) {
    return math.atan2(outDy, outDx);
  }
  return math.atan2(by, bx);
}
