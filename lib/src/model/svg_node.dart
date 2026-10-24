import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_gradient.dart';
import 'svg_style.dart';
import 'svg_transform.dart';

/// Alignment mode for SVG `preserveAspectRatio`.
enum SvgAspectRatioAlign {
  none,
  xMinYMin,
  xMidYMin,
  xMaxYMin,
  xMinYMid,
  xMidYMid,
  xMaxYMid,
  xMinYMax,
  xMidYMax,
  xMaxYMax,
}

/// Meet or slice scaling mode for SVG `preserveAspectRatio`.
enum SvgMeetOrSlice { meet, slice }

/// Precompiled `preserveAspectRatio` configuration.
class SvgPreserveAspectRatio {
  final SvgAspectRatioAlign align;
  final SvgMeetOrSlice meetOrSlice;

  const SvgPreserveAspectRatio({
    this.align = SvgAspectRatioAlign.xMidYMid,
    this.meetOrSlice = SvgMeetOrSlice.meet,
  });

  static const SvgPreserveAspectRatio defaultValue = SvgPreserveAspectRatio();

  /// Computes the 4x4 transformation matrix mapping [viewBox] into [viewportSize]
  /// in-place into [outMatrix] without allocating memory.
  void computeMatrixInPlace(
    ui.Rect viewBox,
    ui.Size viewportSize,
    Float64List outMatrix,
  ) {
    SvgMatrixMath.resetToIdentity(outMatrix);
    if (viewBox.width <= 0.0 ||
        viewBox.height <= 0.0 ||
        viewportSize.width <= 0.0 ||
        viewportSize.height <= 0.0) {
      return;
    }

    final scaleX = viewportSize.width / viewBox.width;
    final scaleY = viewportSize.height / viewBox.height;

    if (align == SvgAspectRatioAlign.none) {
      SvgMatrixMath.scaleInPlace(outMatrix, scaleX, scaleY);
      SvgMatrixMath.translateInPlace(outMatrix, -viewBox.left, -viewBox.top);
      return;
    }

    final uniformScale = meetOrSlice == SvgMeetOrSlice.meet
        ? math.min(scaleX, scaleY)
        : math.max(scaleX, scaleY);

    final scaledWidth = viewBox.width * uniformScale;
    final scaledHeight = viewBox.height * uniformScale;
    final spareX = viewportSize.width - scaledWidth;
    final spareY = viewportSize.height - scaledHeight;

    double offsetX = 0.0;
    double offsetY = 0.0;

    switch (align) {
      case SvgAspectRatioAlign.xMinYMin:
      case SvgAspectRatioAlign.xMinYMid:
      case SvgAspectRatioAlign.xMinYMax:
        offsetX = 0.0;
      case SvgAspectRatioAlign.xMidYMin:
      case SvgAspectRatioAlign.xMidYMid:
      case SvgAspectRatioAlign.xMidYMax:
        offsetX = spareX * 0.5;
      case SvgAspectRatioAlign.xMaxYMin:
      case SvgAspectRatioAlign.xMaxYMid:
      case SvgAspectRatioAlign.xMaxYMax:
        offsetX = spareX;
      case SvgAspectRatioAlign.none:
        break;
    }

    switch (align) {
      case SvgAspectRatioAlign.xMinYMin:
      case SvgAspectRatioAlign.xMidYMin:
      case SvgAspectRatioAlign.xMaxYMin:
        offsetY = 0.0;
      case SvgAspectRatioAlign.xMinYMid:
      case SvgAspectRatioAlign.xMidYMid:
      case SvgAspectRatioAlign.xMaxYMid:
        offsetY = spareY * 0.5;
      case SvgAspectRatioAlign.xMinYMax:
      case SvgAspectRatioAlign.xMidYMax:
      case SvgAspectRatioAlign.xMaxYMax:
        offsetY = spareY;
      case SvgAspectRatioAlign.none:
        break;
    }

    SvgMatrixMath.translateInPlace(outMatrix, offsetX, offsetY);
    SvgMatrixMath.scaleInPlace(outMatrix, uniformScale, uniformScale);
    SvgMatrixMath.translateInPlace(outMatrix, -viewBox.left, -viewBox.top);
  }
}

/// Base class for all nodes in the precompiled SVG AST scene graph.
///
/// Holds pre-allocated `Paint` and `Float64List` matrix buffers to guarantee a
/// zero-allocation `paint()` loop at 60/120fps.
abstract class SvgElement {
  final String tagName;
  final String? id;
  final List<String> classes;
  final SvgStyle style;
  final List<SvgTransformOp> baseTransformOps;
  SvgElement? parent;

  /// Pre-allocated paint instances reused across every frame.
  final ui.Paint cachedFillPaint = ui.Paint()
    ..style = ui.PaintingStyle.fill
    ..isAntiAlias = true;

  final ui.Paint cachedStrokePaint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..isAntiAlias = true;

  final ui.Paint cachedLayerPaint = ui.Paint();

  /// Pre-allocated 16-element column-major transformation matrices.
  final Float64List baseTransformMatrix = SvgMatrixMath.createIdentity();
  final Float64List transformMatrix = SvgMatrixMath.createIdentity();
  final Float64List motionMatrix = SvgMatrixMath.createIdentity();

  /// Whether this node or any of its descendants (or referenced gradients/defs)
  /// are animated. Static subtrees (`isAnimated == false`) are recorded into a
  /// `ui.Picture` on their first draw and replayed via `canvas.drawPicture`.
  bool isAnimated = false;
  bool hasSelfAnimation = false;
  bool hasMotionAnimation = false;

  /// Cached static picture when `isAnimated == false`.
  ui.Picture? cachedPicture;

  /// Cached local bounding box (computed once during AST finalization or updated
  /// when geometry morphs).
  ui.Rect cachedBounds = ui.Rect.zero;

  /// Cached blur filter when `blurSigma > 0` to avoid recreating if unchanged.
  double _lastBlurSigma = 0.0;
  ui.MaskFilter? _cachedMaskFilter;

  SvgElement({
    required this.tagName,
    this.id,
    this.classes = const [],
    required this.style,
    this.baseTransformOps = const [],
  });

  /// Returns child elements if this node is a container.
  List<SvgElement> get children => const [];

  /// Computes and caches the node's local geometry and bounding box.
  void initializeGeometry(SvgDocument document);

  /// Recomputes [baseTransformMatrix] incorporating `transform-origin` once
  /// [cachedBounds] is known.
  void finalizeBaseTransforms(ui.Rect viewBox) {
    SvgMatrixMath.resetToIdentity(baseTransformMatrix);
    final origin = style.currentTransformOrigin;
    final ox = origin.resolveX(cachedBounds, viewBox);
    final oy = origin.resolveY(cachedBounds, viewBox);

    if (baseTransformOps.isNotEmpty) {
      SvgMatrixMath.applyOpsWithOriginInPlace(
        baseTransformMatrix,
        baseTransformOps,
        originX: ox,
        originY: oy,
      );
    }
    if (style.cssBaseTransformOps != null &&
        style.cssBaseTransformOps!.isNotEmpty) {
      SvgMatrixMath.applyOpsWithOriginInPlace(
        baseTransformMatrix,
        style.cssBaseTransformOps!,
        originX: ox,
        originY: oy,
      );
    }
    SvgMatrixMath.copyInto(baseTransformMatrix, transformMatrix);
    SvgMatrixMath.resetToIdentity(motionMatrix);
  }

  /// Resets runtime transform and style back to base state before applying frame animations.
  void resetFrameState() {
    style.resetRuntimeToBase(parent?.style);
    SvgMatrixMath.copyInto(baseTransformMatrix, transformMatrix);
    if (hasMotionAnimation) {
      SvgMatrixMath.resetToIdentity(motionMatrix);
    }
  }

  /// Propagates `isAnimated` bottom-up through the scene graph.
  bool propagateAnimationFlags(SvgDocument document) {
    bool animated = hasSelfAnimation || hasMotionAnimation;

    // Check if fill or stroke references an animated gradient
    final fillGradId = style.resolvedFill.gradientId;
    if (fillGradId != null) {
      final grad = document.gradientsById[fillGradId];
      if (grad != null && grad.isAnimated) {
        animated = true;
      }
    }
    final strokeGradId = style.resolvedStroke.gradientId;
    if (strokeGradId != null) {
      final grad = document.gradientsById[strokeGradId];
      if (grad != null && grad.isAnimated) {
        animated = true;
      }
    }

    for (final child in children) {
      if (child.propagateAnimationFlags(document)) {
        animated = true;
      }
    }

    isAnimated = animated;
    return animated;
  }

  /// Updates [cachedBlurFilter] only when `currentBlurSigma` changes.
  ui.MaskFilter? resolveMaskFilter() {
    final sigma = style.currentBlurSigma;
    if (sigma <= 0.0) {
      _lastBlurSigma = 0.0;
      _cachedMaskFilter = null;
      return null;
    }
    if ((sigma - _lastBlurSigma).abs() > 1e-4 || _cachedMaskFilter == null) {
      _lastBlurSigma = sigma;
      _cachedMaskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
    }
    return _cachedMaskFilter;
  }

  /// Renders this node onto [canvas]. Uses `cachedPicture` if `isAnimated == false`
  /// and this node is a group or complex static subtree.
  void paint(ui.Canvas canvas, SvgDocument document) {
    if (style.displayNone) return;

    if (!isAnimated && shouldCacheStaticPicture) {
      if (cachedPicture == null) {
        final recorder = ui.PictureRecorder();
        final recCanvas = ui.Canvas(recorder);
        _paintInternal(recCanvas, document);
        cachedPicture = recorder.endRecording();
      }
      canvas.drawPicture(cachedPicture!);
      return;
    }

    _paintInternal(canvas, document);
  }

  /// Whether this node should record a static [ui.Picture] when `isAnimated == false`.
  bool get shouldCacheStaticPicture => false;

  void _paintInternal(ui.Canvas canvas, SvgDocument document) {
    final hasTransform = !SvgMatrixMath.isIdentity(transformMatrix);
    final hasMotion =
        hasMotionAnimation && !SvgMatrixMath.isIdentity(motionMatrix);
    final clipId = style.clipPathId;
    final clipNode = clipId != null ? document.clipPathsById[clipId] : null;
    final opacity = style.currentOpacity.clamp(0.0, 1.0);
    final needsLayer = opacity < 1.0 && children.isNotEmpty;

    final needsSave =
        hasTransform || hasMotion || clipNode != null || needsLayer;
    if (needsSave) {
      canvas.save();
    }

    if (hasMotion) {
      canvas.transform(motionMatrix);
    }
    if (hasTransform) {
      canvas.transform(transformMatrix);
    }
    if (clipNode != null) {
      canvas.clipPath(clipNode.clipPath);
    }
    if (needsLayer) {
      cachedLayerPaint.color = ui.Color.fromARGB(
        (opacity * 255.0).round().clamp(0, 255),
        255,
        255,
        255,
      );
      canvas.saveLayer(null, cachedLayerPaint);
    }

    paintContent(canvas, document, needsLayer ? 1.0 : opacity);

    if (needsLayer) {
      canvas.restore();
    }
    if (needsSave) {
      canvas.restore();
    }
  }

  /// Subclass hook to draw geometry or child elements.
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  );

  /// Releases native `ui.Picture` resources.
  void dispose() {
    cachedPicture?.dispose();
    cachedPicture = null;
    for (final child in children) {
      child.dispose();
    }
  }
}

/// Container `<g>` or root `<svg>` group node.
class SvgGroupNode extends SvgElement {
  @override
  final List<SvgElement> children;

  SvgGroupNode({
    super.tagName = 'g',
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    List<SvgElement>? children,
  }) : children = children ?? <SvgElement>[];

  @override
  bool get shouldCacheStaticPicture => children.isNotEmpty;

  @override
  void initializeGeometry(SvgDocument document) {
    ui.Rect? unionBounds;
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      child.initializeGeometry(document);
      final childBounds = child.cachedBounds;
      if (!childBounds.isEmpty) {
        unionBounds = unionBounds == null
            ? childBounds
            : unionBounds.expandToInclude(childBounds);
      }
    }
    cachedBounds = unionBounds ?? ui.Rect.zero;
    finalizeBaseTransforms(document.viewBox);
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    // Grouping consecutive static children into a cached Picture if this group is animated
    for (int i = 0; i < children.length; i++) {
      children[i].paint(canvas, document);
    }
  }
}

/// `<defs>` container node (not rendered directly; children are referenced by ID).
class SvgDefsNode extends SvgGroupNode {
  SvgDefsNode({super.id, required super.style, super.children})
    : super(tagName: 'defs');

  @override
  bool get shouldCacheStaticPicture => false;

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <defs> are never painted directly
  }
}

/// `<clipPath>` node that precomputes and caches the union `ui.Path` of its children.
class SvgClipPathNode extends SvgGroupNode {
  final ui.Path clipPath = ui.Path();

  SvgClipPathNode({super.id, required super.style, super.children})
    : super(tagName: 'clipPath');

  @override
  void initializeGeometry(SvgDocument document) {
    super.initializeGeometry(document);
    clipPath.reset();
    for (final child in children) {
      if (child is SvgGeometryNode) {
        if (!SvgMatrixMath.isIdentity(child.baseTransformMatrix)) {
          clipPath.addPath(
            child.basePath,
            ui.Offset.zero,
            matrix4: child.baseTransformMatrix,
          );
        } else {
          clipPath.addPath(child.basePath, ui.Offset.zero);
        }
      }
    }
    cachedBounds = clipPath.getBounds();
  }

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <clipPath> is applied via canvas.clipPath()
  }
}

/// `<use>` node that references a `<defs>` element by `href` / `xlink:href` with `(x, y)` offset.
class SvgUseNode extends SvgElement {
  final String? hrefId;
  final double baseX;
  final double baseY;
  double currentX;
  double currentY;

  SvgUseNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.hrefId,
    this.baseX = 0.0,
    this.baseY = 0.0,
  }) : currentX = baseX,
       currentY = baseY,
       super(tagName: 'use');

  @override
  void initializeGeometry(SvgDocument document) {
    final target = hrefId != null ? document.defsById[hrefId!] : null;
    if (target != null) {
      target.initializeGeometry(document);
      cachedBounds = target.cachedBounds.shift(ui.Offset(baseX, baseY));
    } else {
      cachedBounds = ui.Rect.zero;
    }
    finalizeBaseTransforms(document.viewBox);
  }

  @override
  bool propagateAnimationFlags(SvgDocument document) {
    bool animated = super.propagateAnimationFlags(document);
    final target = hrefId != null ? document.defsById[hrefId!] : null;
    if (target != null) {
      if (target.propagateAnimationFlags(document)) {
        animated = true;
      }
    }
    isAnimated = animated;
    return animated;
  }

  @override
  void resetFrameState() {
    super.resetFrameState();
    currentX = baseX;
    currentY = baseY;
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    if (style.visibilityHidden || hrefId == null) return;
    final target = document.defsById[hrefId!];
    if (target == null) return;

    final hasOffset = currentX != 0.0 || currentY != 0.0;
    if (hasOffset) {
      canvas.save();
      canvas.translate(currentX, currentY);
    }
    target.paint(canvas, document);
    if (hasOffset) {
      canvas.restore();
    }
  }
}

/// Abstract base class for all geometric shape nodes (`<path>`, `<rect>`,
/// `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`).
///
/// Precomputes and caches `basePath`, `cachedMetrics`, and `totalPathLength`.
abstract class SvgGeometryNode extends SvgElement {
  /// Pre-allocated base geometric path.
  final ui.Path basePath = ui.Path();

  /// Pre-allocated dashed/trimmed stroke path reused every frame when
  /// `stroke-dasharray` is active.
  final ui.Path dashedStrokePath = ui.Path();

  /// Cached `PathMetric` list computed once at initialization (or when geometry
  /// morphs) if needed for `stroke-dasharray` or `<animateMotion>`.
  List<ui.PathMetric>? cachedMetrics;
  double totalPathLength = 0.0;
  bool needsPathMetrics = false;
  bool geometryDirty = false;

  SvgGeometryNode({
    required super.tagName,
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
  });

  @override
  bool get shouldCacheStaticPicture => !isAnimated;

  /// Populates [basePath] from the current geometric attributes.
  void buildPath(ui.Path outPath);

  @override
  void initializeGeometry(SvgDocument document) {
    basePath.reset();
    buildPath(basePath);
    basePath.fillType = style.currentFillRule;
    cachedBounds = basePath.getBounds();

    if (style.currentStrokeDasharray != null &&
        style.currentStrokeDasharray!.isNotEmpty) {
      needsPathMetrics = true;
    }
    if (needsPathMetrics) {
      recomputePathMetrics();
    }
    finalizeBaseTransforms(document.viewBox);
  }

  /// Computes and caches [cachedMetrics] and [totalPathLength] from [basePath].
  void recomputePathMetrics() {
    final metricsList = basePath.computeMetrics(forceClosed: false).toList();
    cachedMetrics = metricsList;
    double sum = 0.0;
    for (int i = 0; i < metricsList.length; i++) {
      sum += metricsList[i].length;
    }
    totalPathLength = sum;
  }

  /// Marks geometry as modified during an animation frame so [basePath] and
  /// [cachedMetrics] (if required) are refreshed once per frame.
  void markGeometryDirty() {
    geometryDirty = true;
  }

  void refreshGeometryIfNeeded() {
    if (!geometryDirty) return;
    geometryDirty = false;
    basePath.reset();
    buildPath(basePath);
    basePath.fillType = style.currentFillRule;
    cachedBounds = basePath.getBounds();
    if (needsPathMetrics ||
        (style.currentStrokeDasharray != null &&
            style.currentStrokeDasharray!.isNotEmpty)) {
      recomputePathMetrics();
    }
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    if (style.visibilityHidden) return;
    refreshGeometryIfNeeded();

    final maskFilter = resolveMaskFilter();

    // 1. Fill Pass
    final fillServer = style.resolvedFill;
    final fillAlpha = (style.currentFillOpacity * effectiveOpacity).clamp(
      0.0,
      1.0,
    );
    if (fillServer.isVisible && fillAlpha > 0.0) {
      basePath.fillType = style.currentFillRule;
      cachedFillPaint.maskFilter = maskFilter;

      if (fillServer.type == SvgPaintType.gradient &&
          fillServer.gradientId != null) {
        final grad = document.gradientsById[fillServer.gradientId!];
        cachedFillPaint.shader = grad?.createShader(cachedBounds);
        cachedFillPaint.color = ui.Color.fromARGB(
          (fillAlpha * 255.0).round().clamp(0, 255),
          255,
          255,
          255,
        );
      } else {
        cachedFillPaint.shader = null;
        final c = style.currentFillColor;
        final combinedAlpha = (c.a * fillAlpha).clamp(0.0, 1.0);
        cachedFillPaint.color = c.withValues(alpha: combinedAlpha);
      }
      canvas.drawPath(basePath, cachedFillPaint);
    }

    // 2. Stroke Pass
    final strokeServer = style.resolvedStroke;
    final strokeWidth = style.currentStrokeWidth;
    final strokeAlpha = (style.currentStrokeOpacity * effectiveOpacity).clamp(
      0.0,
      1.0,
    );
    if (strokeServer.isVisible && strokeWidth > 0.0 && strokeAlpha > 0.0) {
      cachedStrokePaint
        ..strokeWidth = strokeWidth
        ..strokeCap = style.currentStrokeCap
        ..strokeJoin = style.currentStrokeJoin
        ..strokeMiterLimit = style.currentStrokeMiterLimit
        ..maskFilter = maskFilter;

      if (strokeServer.type == SvgPaintType.gradient &&
          strokeServer.gradientId != null) {
        final grad = document.gradientsById[strokeServer.gradientId!];
        cachedStrokePaint.shader = grad?.createShader(cachedBounds);
        cachedStrokePaint.color = ui.Color.fromARGB(
          (strokeAlpha * 255.0).round().clamp(0, 255),
          255,
          255,
          255,
        );
      } else {
        cachedStrokePaint.shader = null;
        final c = style.currentStrokeColor;
        final combinedAlpha = (c.a * strokeAlpha).clamp(0.0, 1.0);
        cachedStrokePaint.color = c.withValues(alpha: combinedAlpha);
      }

      final dashArray = style.currentStrokeDasharray;
      if (dashArray != null && dashArray.isNotEmpty) {
        _buildDashedPathInPlace(dashArray, style.currentStrokeDashoffset);
        canvas.drawPath(dashedStrokePath, cachedStrokePaint);
      } else {
        canvas.drawPath(basePath, cachedStrokePaint);
      }
    }
  }

  /// High-performance stroke-dasharray / stroke-dashoffset extractor using
  /// pre-cached [cachedMetrics], supporting SVG `pathLength` normalization and
  /// negative/positive `dashoffset` wrap-around.
  void _buildDashedPathInPlace(Float64List dashArray, double dashOffset) {
    dashedStrokePath.reset();
    if (cachedMetrics == null) {
      recomputePathMetrics();
    }
    final metrics = cachedMetrics;
    if (metrics == null || metrics.isEmpty || totalPathLength <= 0.0) {
      return;
    }

    // Compute scale factor if SVG `pathLength` attribute is specified
    double scale = 1.0;
    final definedPathLength = style.currentPathLength;
    if (definedPathLength != null && definedPathLength > 0.0) {
      scale = totalPathLength / definedPathLength;
    }

    // Per SVG spec: if dasharray has an odd number of elements, repeat it twice
    // so the pattern cycle length is always even (dash/gap pairs).
    final rawCount = dashArray.length;
    final patternCount = rawCount.isOdd ? rawCount * 2 : rawCount;

    double cycleLength = 0.0;
    for (int i = 0; i < patternCount; i++) {
      final d = dashArray[i % rawCount] * scale;
      if (d > 0.0) {
        cycleLength += d;
      }
    }

    if (cycleLength <= 1e-6) {
      dashedStrokePath.addPath(basePath, ui.Offset.zero);
      return;
    }

    // Normalize dashoffset into [0, cycleLength) with proper negative wrap-around
    double normalizedOffset = (dashOffset * scale) % cycleLength;
    if (normalizedOffset < 0.0) {
      normalizedOffset += cycleLength;
    }

    for (int mIdx = 0; mIdx < metrics.length; mIdx++) {
      final metric = metrics[mIdx];
      final contourLen = metric.length;
      if (contourLen <= 0.0) continue;

      // Advance to the starting dash segment based on normalizedOffset
      int segIndex = 0;
      double segRemaining = dashArray[0] * scale;
      double offsetLeft = normalizedOffset;

      while (offsetLeft > 0.0) {
        final segLen = dashArray[segIndex % rawCount] * scale;
        if (offsetLeft < segLen) {
          segRemaining = segLen - offsetLeft;
          break;
        }
        offsetLeft -= segLen;
        segIndex = (segIndex + 1) % patternCount;
        segRemaining = dashArray[segIndex % rawCount] * scale;
      }

      double dist = 0.0;
      while (dist < contourLen) {
        final drawLen = math.min(segRemaining, contourLen - dist);
        final isDrawnDash = segIndex.isEven;
        if (isDrawnDash && drawLen > 0.0) {
          final extracted = metric.extractPath(
            dist,
            dist + drawLen,
            startWithMoveTo: true,
          );
          dashedStrokePath.addPath(extracted, ui.Offset.zero);
        }
        dist += drawLen;
        segIndex = (segIndex + 1) % patternCount;
        segRemaining = dashArray[segIndex % rawCount] * scale;
        if (segRemaining <= 0.0) {
          // Guard against zero-length segment inside positive cycle
          int guard = 0;
          while (segRemaining <= 0.0 && guard < patternCount) {
            segIndex = (segIndex + 1) % patternCount;
            segRemaining = dashArray[segIndex % rawCount] * scale;
            guard++;
          }
          if (segRemaining <= 0.0) break;
        }
      }
    }
  }
}

/// Precompiled path command type for isomorphic Path Morphing & zero-string runtime path building.
enum SvgPathCmdType {
  moveTo, // 2 coords: x, y
  lineTo, // 2 coords: x, y
  cubicTo, // 6 coords: x1, y1, x2, y2, x, y
  quadTo, // 4 coords: x1, y1, x, y
  arcTo, // 7 coords: rx, ry, xAxisRotationDeg, largeArcFlag, sweepFlag, x, y
  close, // 0 coords
}

/// Precompiled path instruction sequence stored in contiguous typed arrays.
///
/// Enables zero-allocation path building and O(N) isomorphic path morphing.
class PrecompiledSvgPath {
  final List<SvgPathCmdType> commands;
  final Float64List coords;

  const PrecompiledSvgPath({required this.commands, required this.coords});

  /// Number of coordinates consumed by [cmd].
  static int coordCountFor(SvgPathCmdType cmd) {
    switch (cmd) {
      case SvgPathCmdType.moveTo:
      case SvgPathCmdType.lineTo:
        return 2;
      case SvgPathCmdType.quadTo:
        return 4;
      case SvgPathCmdType.cubicTo:
        return 6;
      case SvgPathCmdType.arcTo:
        return 7;
      case SvgPathCmdType.close:
        return 0;
    }
  }

  /// Checks whether [other] is isomorphic (identical command sequence and coord count).
  bool isIsomorphicWith(PrecompiledSvgPath other) {
    if (commands.length != other.commands.length ||
        coords.length != other.coords.length) {
      return false;
    }
    for (int i = 0; i < commands.length; i++) {
      if (commands[i] != other.commands[i]) return false;
    }
    return true;
  }

  /// Populates [outPath] from [commands] and [activeCoords] (which may be [coords]
  /// or an interpolated morphed buffer).
  void buildUiPath(ui.Path outPath, [Float64List? activeCoords]) {
    final c = activeCoords ?? coords;
    int offset = 0;
    for (int i = 0; i < commands.length; i++) {
      switch (commands[i]) {
        case SvgPathCmdType.moveTo:
          outPath.moveTo(c[offset], c[offset + 1]);
          offset += 2;
        case SvgPathCmdType.lineTo:
          outPath.lineTo(c[offset], c[offset + 1]);
          offset += 2;
        case SvgPathCmdType.quadTo:
          outPath.quadraticBezierTo(
            c[offset],
            c[offset + 1],
            c[offset + 2],
            c[offset + 3],
          );
          offset += 4;
        case SvgPathCmdType.cubicTo:
          outPath.cubicTo(
            c[offset],
            c[offset + 1],
            c[offset + 2],
            c[offset + 3],
            c[offset + 4],
            c[offset + 5],
          );
          offset += 6;
        case SvgPathCmdType.arcTo:
          final rx = c[offset].abs();
          final ry = c[offset + 1].abs();
          final rotDeg = c[offset + 2];
          final largeArc = c[offset + 3] >= 0.5;
          final sweep = c[offset + 4] >= 0.5;
          final endX = c[offset + 5];
          final endY = c[offset + 6];
          if (rx == 0.0 || ry == 0.0) {
            outPath.lineTo(endX, endY);
          } else {
            outPath.arcToPoint(
              ui.Offset(endX, endY),
              radius: ui.Radius.elliptical(rx, ry),
              rotation: rotDeg,
              largeArc: largeArc,
              clockwise: sweep,
            );
          }
          offset += 7;
        case SvgPathCmdType.close:
          outPath.close();
      }
    }
  }
}

/// `<path>` node supporting static path caching and isomorphic `d` path morphing.
class SvgPathNode extends SvgGeometryNode {
  final PrecompiledSvgPath precompiledPath;

  /// Pre-allocated coordinate buffer used when `<animate attributeName="d">` morphs this path.
  late final Float64List morphedCoords;
  bool isMorphed = false;

  SvgPathNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    required this.precompiledPath,
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
