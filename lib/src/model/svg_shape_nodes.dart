import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_geometry_node.dart';
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
}
