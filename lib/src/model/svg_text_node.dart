import 'dart:typed_data';
import 'dart:ui' as ui;

import '../parser/svg_path_parser.dart';
import 'svg_document.dart';
import 'svg_element.dart';
import 'svg_geometry_node.dart';
import 'svg_text_layout.dart';
import 'svg_text_style.dart';

/// Ordered content item inside `<text>`, `<tspan>`, or `<textPath>`.
sealed class SvgTextContentItem {
  const SvgTextContentItem();
}

/// Literal character data segment inside a text content element.
final class SvgTextLiteral extends SvgTextContentItem {
  final String text;

  const SvgTextLiteral(this.text);
}

/// `<tspan>` (or `<a>` inside `<text>`) child element supporting nested styling,
/// absolute/relative coordinate lists, per-glyph rotation, and animations.
final class SvgTextSpanNode extends SvgElement implements SvgTextContentItem {
  final List<SvgTextLength> xList;
  final List<SvgTextLength> yList;
  final List<SvgTextLength> dxList;
  final List<SvgTextLength> dyList;
  final Float64List rotateList;
  final SvgTextLength? textLength;
  final SvgLengthAdjust lengthAdjust;
  final List<SvgTextContentItem> contentItems;

  /// Runtime animated overrides for `x`, `y`, `dx`, `dy` (null when not animated).
  double? animatedX;
  double? animatedY;
  double? animatedDx;
  double? animatedDy;

  final List<SvgElement> _childElements;

  SvgTextSpanNode({
    super.tagName = 'tspan',
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.xList = const [],
    this.yList = const [],
    this.dxList = const [],
    this.dyList = const [],
    Float64List? rotateList,
    this.textLength,
    this.lengthAdjust = SvgLengthAdjust.spacing,
    required this.contentItems,
  }) : rotateList = rotateList ?? Float64List(0),
       _childElements = [
         for (final item in contentItems)
           if (item case final SvgElement elem) elem,
       ];

  @override
  List<SvgElement> get children => _childElements;

  @override
  void initializeGeometry(SvgDocument document) {
    for (final child in _childElements) {
      child.initializeGeometry(document);
    }
    finalizeBaseTransforms(document.viewBox);
  }

  @override
  void resetFrameState() {
    super.resetFrameState();
    animatedX = null;
    animatedY = null;
    animatedDx = null;
    animatedDy = null;
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    // Painted as part of its ancestor SvgTextNode layout pass.
  }
}

/// `<textPath>` element that renders nested text runs along a referenced
/// `<path>` / geometry node (`href`/`xlink:href`) or inline SVG 2 `path` data.
final class SvgTextPathNode extends SvgElement implements SvgTextContentItem {
  final String? hrefId;
  final String? inlinePathData;
  final SvgTextLength? startOffset;
  final bool sideRight;
  final SvgTextLength? textLength;
  final SvgLengthAdjust lengthAdjust;
  final List<SvgTextContentItem> contentItems;

  final List<SvgElement> _childElements;
  List<ui.PathMetric>? cachedPathMetrics;
  double cachedTotalPathLength = 0.0;

  SvgTextPathNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.hrefId,
    this.inlinePathData,
    this.startOffset,
    this.sideRight = false,
    this.textLength,
    this.lengthAdjust = SvgLengthAdjust.spacing,
    required this.contentItems,
  }) : _childElements = [
         for (final item in contentItems)
           if (item case final SvgElement elem) elem,
       ],
       super(tagName: 'textPath');

  @override
  List<SvgElement> get children => _childElements;

  /// Resolves the target path metrics from inline `path` or `href`/`xlink:href`.
  List<ui.PathMetric>? resolvePathMetrics(SvgDocument document) {
    if (cachedPathMetrics != null) return cachedPathMetrics;

    ui.Path? sourcePath;
    if (inlinePathData != null && inlinePathData!.trim().isNotEmpty) {
      final precompiled = SvgPathParser.parse(inlinePathData!);
      sourcePath = ui.Path();
      precompiled.buildUiPath(sourcePath);
    } else if (hrefId != null && hrefId!.isNotEmpty) {
      final geom = document.geometryById[hrefId!];
      if (geom != null) {
        if (geom.cachedMetrics == null) {
          geom.needsPathMetrics = true;
          geom.initializeGeometry(document);
        }
        sourcePath = geom.basePath;
      } else {
        final defNode = document.defsById[hrefId!];
        if (defNode is SvgGeometryNode) {
          if (defNode.cachedMetrics == null) {
            defNode.needsPathMetrics = true;
            defNode.initializeGeometry(document);
          }
          sourcePath = defNode.basePath;
        }
      }
    }

    if (sourcePath == null) return null;
    final metrics = sourcePath.computeMetrics(forceClosed: false).toList();
    double total = 0.0;
    for (int i = 0; i < metrics.length; i++) {
      total += metrics[i].length;
    }
    cachedPathMetrics = metrics;
    cachedTotalPathLength = total;
    return metrics;
  }

  @override
  void initializeGeometry(SvgDocument document) {
    resolvePathMetrics(document);
    for (final child in _childElements) {
      child.initializeGeometry(document);
    }
    finalizeBaseTransforms(document.viewBox);
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    // Painted as part of its ancestor SvgTextNode layout pass.
  }
}

/// Top-level `<text>` graphics element supporting full W3C SVG 1.1 / SVG 2
/// text layout, `<tspan>`, `<textPath>`, baselines, `text-anchor`, `textLength`,
/// fill/stroke/gradient rendering, `paint-order`, and SMIL/CSS animations.
final class SvgTextNode extends SvgElement {
  final List<SvgTextLength> xList;
  final List<SvgTextLength> yList;
  final List<SvgTextLength> dxList;
  final List<SvgTextLength> dyList;
  final Float64List rotateList;
  final SvgTextLength? textLength;
  final SvgLengthAdjust lengthAdjust;
  final List<SvgTextContentItem> contentItems;

  /// Runtime animated overrides for `x`, `y`, `dx`, `dy` (null when not animated).
  double? animatedX;
  double? animatedY;
  double? animatedDx;
  double? animatedDy;

  final List<SvgElement> _childElements;

  SvgTextNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.xList = const [],
    this.yList = const [],
    this.dxList = const [],
    this.dyList = const [],
    Float64List? rotateList,
    this.textLength,
    this.lengthAdjust = SvgLengthAdjust.spacing,
    required this.contentItems,
  }) : rotateList = rotateList ?? Float64List(0),
       _childElements = [
         for (final item in contentItems)
           if (item case final SvgElement elem) elem,
       ],
       super(tagName: 'text');

  @override
  List<SvgElement> get children => _childElements;

  @override
  bool get shouldCacheStaticPicture => !isAnimated;

  /// Resolves the primary base X coordinate in user space (defaults to `0.0`).
  double resolveBaseX(ui.Rect viewBox) {
    if (xList.isEmpty) return 0.0;
    return xList.first.resolve(
      fontSize: style.currentFontSize,
      referenceExtent: viewBox.width,
    );
  }

  /// Resolves the primary base Y coordinate in user space (defaults to `0.0`).
  double resolveBaseY(ui.Rect viewBox) {
    if (yList.isEmpty) return 0.0;
    return yList.first.resolve(
      fontSize: style.currentFontSize,
      referenceExtent: viewBox.height,
    );
  }

  @override
  void initializeGeometry(SvgDocument document) {
    for (final child in _childElements) {
      child.initializeGeometry(document);
    }
    cachedBounds = SvgTextLayoutEngine.computeBounds(this, document);
    finalizeBaseTransforms(document.viewBox);
  }

  @override
  void resetFrameState() {
    super.resetFrameState();
    animatedX = null;
    animatedY = null;
    animatedDx = null;
    animatedDy = null;
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    if (style.visibilityHidden) return;
    SvgTextLayoutEngine.paint(canvas, this, document, effectiveOpacity);
  }
}
