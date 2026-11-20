import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_geometry_node.dart';
import 'svg_marker_node.dart';
import 'svg_precompiled_path.dart';

/// `<path>` node supporting static path caching and isomorphic `d` path morphing.
class SvgPathNode extends SvgGeometryNode {
  final PrecompiledSvgPath precompiledPath;
  final String? xmlBaseD;

  /// Pre-allocated coordinate buffer used when `<animate attributeName="d">` morphs this path.
  late final Float64List morphedCoords;
  bool isMorphed = false;

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
class SvgRectNode extends SvgGeometryNode {
  final double baseX;
  final double baseY;
  final double baseWidth;
  final double baseHeight;
  final double baseRx;
  final double baseRy;

  double currentX;
  double currentY;
  double currentWidth;
  double currentHeight;
  double currentRx;
  double currentRy;

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
class SvgCircleNode extends SvgGeometryNode {
  final double baseCx;
  final double baseCy;
  final double baseR;

  double currentCx;
  double currentCy;
  double currentR;

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
class SvgEllipseNode extends SvgGeometryNode {
  final double baseCx;
  final double baseCy;
  final double baseRx;
  final double baseRy;

  double currentCx;
  double currentCy;
  double currentRx;
  double currentRy;

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
class SvgLineNode extends SvgGeometryNode {
  final double baseX1;
  final double baseY1;
  final double baseX2;
  final double baseY2;

  double currentX1;
  double currentY1;
  double currentX2;
  double currentY2;

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
      SvgMarkerVertex(x: currentX1, y: currentY1, angleRad: angle, isStart: true),
      SvgMarkerVertex(x: currentX2, y: currentY2, angleRad: angle, isEnd: true),
    ];
  }
}

/// `<polyline>` or `<polygon>` node with precompiled coordinate list.
class SvgPolyNode extends SvgGeometryNode {
  final Float64List points;
  final bool closePath;

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
