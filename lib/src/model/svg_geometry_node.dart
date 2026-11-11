import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_document.dart';
import 'svg_element.dart';
import 'svg_style.dart';

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
