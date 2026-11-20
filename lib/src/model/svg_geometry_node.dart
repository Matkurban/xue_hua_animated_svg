import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_document.dart';
import 'svg_element.dart';
import 'svg_marker_node.dart';
import 'svg_style.dart';

/// Abstract base class for all geometric shape nodes (`<path>`, `<rect>`,
/// `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`).
/// 所有几何图元节点的抽象基类，预计算并缓存基础路径、路径度量与总长度。
abstract class SvgGeometryNode extends SvgElement {
  /// Pre-allocated base geometric path. 预分配的基础几何路径。
  final ui.Path basePath = ui.Path();

  /// Pre-allocated dashed/trimmed stroke path reused every frame when `stroke-dasharray` is active.
  /// 启用 `stroke-dasharray` 时每帧复用的虚线描边路径缓冲。
  final ui.Path dashedStrokePath = ui.Path();

  /// Cached `PathMetric` list computed once at initialization (or on morph).
  /// 缓存的路径度量列表（供虚线描边与 `<animateMotion>` 使用）。
  List<ui.PathMetric>? cachedMetrics;

  /// Total arc length across all contours in [cachedMetrics]. 所有子轮廓的总路径长度。
  double totalPathLength = 0.0;

  /// Whether [cachedMetrics] must be computed for dasharray or motion paths. 是否需要预计算路径度量。
  bool needsPathMetrics = false;

  /// Dirty flag set when animated geometry parameters change. 动画修改几何属性时置位的脏标记。
  bool geometryDirty = false;

  /// Creates an [SvgGeometryNode]. 创建一个 [SvgGeometryNode] 几何基类节点。
  SvgGeometryNode({
    required super.tagName,
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
  });

  @override
  bool get shouldCacheStaticPicture => !isAnimated;

  /// Populates [outPath] from the current geometric attributes.
  /// 根据当前几何属性填充目标路径 [outPath]。
  ///
  /// - [outPath]: Destination [ui.Path] buffer. 目标路径缓冲区。
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
  /// 从 [basePath] 重新计算并缓存 [cachedMetrics] 与 [totalPathLength]。
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
  /// 标记几何属性已被动画修改，本帧绘制前将按需重建一次路径与度量。
  void markGeometryDirty() {
    geometryDirty = true;
  }

  /// Rebuilds [basePath], [cachedBounds], and [cachedMetrics] if [geometryDirty] is `true`.
  /// 若 [geometryDirty] 为真则重建路径、包围盒与路径度量。
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
    final antiAlias = !style.currentShapeRenderingCrisp;

    void paintFillPass() {
      final fillServer = style.resolvedFill;
      final fillAlpha = (style.currentFillOpacity * effectiveOpacity).clamp(
        0.0,
        1.0,
      );
      if (fillServer.isVisible && fillAlpha > 0.0) {
        basePath.fillType = style.currentFillRule;
        cachedFillPaint
          ..isAntiAlias = antiAlias
          ..maskFilter = maskFilter;

        if (fillServer.type == SvgPaintType.gradient &&
            fillServer.gradientId != null) {
          final serverId = fillServer.gradientId!;
          final grad = document.gradientsById[serverId];
          final pat = document.patternsById[serverId];
          final shader =
              grad?.createShader(cachedBounds) ??
              pat?.createShader(cachedBounds, document);
          if (shader != null) {
            cachedFillPaint.shader = shader;
            cachedFillPaint.color = ui.Color.fromARGB(
              (fillAlpha * 255.0).round().clamp(0, 255),
              255,
              255,
              255,
            );
          } else if (fillServer.fallbackColor != null) {
            cachedFillPaint.shader = null;
            final fc = fillServer.fallbackColor!;
            cachedFillPaint.color = fc.withValues(
              alpha: (fc.a * fillAlpha).clamp(0.0, 1.0),
            );
          } else {
            return;
          }
        } else {
          cachedFillPaint.shader = null;
          final c = style.currentFillColor;
          final combinedAlpha = (c.a * fillAlpha).clamp(0.0, 1.0);
          cachedFillPaint.color = c.withValues(alpha: combinedAlpha);
        }
        canvas.drawPath(basePath, cachedFillPaint);
      }
    }

    void paintStrokePass() {
      final strokeServer = style.resolvedStroke;
      final rawStrokeWidth = style.currentStrokeWidth;
      final strokeWidth = style.currentNonScalingStroke
          ? rawStrokeWidth / computeAccumulatedScale(document)
          : rawStrokeWidth;
      final strokeAlpha = (style.currentStrokeOpacity * effectiveOpacity).clamp(
        0.0,
        1.0,
      );
      if (strokeServer.isVisible && strokeWidth > 0.0 && strokeAlpha > 0.0) {
        cachedStrokePaint
          ..isAntiAlias = antiAlias
          ..strokeWidth = strokeWidth
          ..strokeCap = style.currentStrokeCap
          ..strokeJoin = style.currentStrokeJoin
          ..strokeMiterLimit = style.currentStrokeMiterLimit
          ..maskFilter = maskFilter;

        if (strokeServer.type == SvgPaintType.gradient &&
            strokeServer.gradientId != null) {
          final serverId = strokeServer.gradientId!;
          final grad = document.gradientsById[serverId];
          final pat = document.patternsById[serverId];
          final shader =
              grad?.createShader(cachedBounds) ??
              pat?.createShader(cachedBounds, document);
          if (shader != null) {
            cachedStrokePaint.shader = shader;
            cachedStrokePaint.color = ui.Color.fromARGB(
              (strokeAlpha * 255.0).round().clamp(0, 255),
              255,
              255,
              255,
            );
          } else if (strokeServer.fallbackColor != null) {
            cachedStrokePaint.shader = null;
            final fc = strokeServer.fallbackColor!;
            cachedStrokePaint.color = fc.withValues(
              alpha: (fc.a * strokeAlpha).clamp(0.0, 1.0),
            );
          } else {
            return;
          }
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

    for (final layer in style.currentPaintOrderLayers) {
      switch (layer) {
        case SvgPaintLayer.fill:
          paintFillPass();
        case SvgPaintLayer.stroke:
          paintStrokePass();
        case SvgPaintLayer.markers:
          _paintMarkers(canvas, document, effectiveOpacity);
      }
    }
  }

  /// Subclasses (`<path>`, `<line>`, `<polyline>`, `<polygon>`) override this
  /// to supply vertex positions and tangent angles for `<marker>` placement.
  List<SvgMarkerVertex> extractMarkerVertices() => const [];

  void _paintMarkers(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    final startId = style.currentMarkerStartId;
    final midId = style.currentMarkerMidId;
    final endId = style.currentMarkerEndId;
    if (startId == null && midId == null && endId == null) return;

    final startMarker = startId != null ? document.markersById[startId] : null;
    final midMarker = midId != null ? document.markersById[midId] : null;
    final endMarker = endId != null ? document.markersById[endId] : null;
    if (startMarker == null && midMarker == null && endMarker == null) return;

    final vertices = extractMarkerVertices();
    if (vertices.isEmpty) return;
    final sw = style.currentStrokeWidth;

    for (int i = 0; i < vertices.length; i++) {
      final v = vertices[i];
      if (v.isStart && startMarker != null) {
        startMarker.paintAtVertex(
          canvas: canvas,
          document: document,
          vertex: v,
          strokeWidth: sw,
          effectiveOpacity: effectiveOpacity,
        );
      }
      if (!v.isStart && !v.isEnd && midMarker != null) {
        midMarker.paintAtVertex(
          canvas: canvas,
          document: document,
          vertex: v,
          strokeWidth: sw,
          effectiveOpacity: effectiveOpacity,
        );
      }
      if (v.isEnd && endMarker != null) {
        endMarker.paintAtVertex(
          canvas: canvas,
          document: document,
          vertex: v,
          strokeWidth: sw,
          effectiveOpacity: effectiveOpacity,
        );
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
