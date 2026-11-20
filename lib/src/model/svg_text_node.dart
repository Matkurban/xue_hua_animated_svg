import 'dart:typed_data';
import 'dart:ui' as ui;

import '../parser/svg_path_parser.dart';
import 'svg_document.dart';
import 'svg_element.dart';
import 'svg_geometry_node.dart';
import 'svg_text_layout.dart';
import 'svg_text_style.dart';

/// Ordered content item inside `<text>`, `<tspan>`, or `<textPath>`.
///
/// `<text>`、`<tspan>` 或 `<textPath>` 内部的有序内容项密封基类。
sealed class SvgTextContentItem {
  /// Creates an [SvgTextContentItem].
  ///
  /// 创建 [SvgTextContentItem]。
  const SvgTextContentItem();
}

/// Literal character data segment inside a text content element.
///
/// 文本容器元素中的纯文本字面量片段。
final class SvgTextLiteral extends SvgTextContentItem {
  /// Raw text characters contained in this literal segment.
  ///
  /// 当前字面量片段包含的原始文本字符串。
  final String text;

  /// Creates an [SvgTextLiteral] wrapping [text].
  ///
  /// 使用字符串 [text] 创建 [SvgTextLiteral]。
  const SvgTextLiteral(this.text);
}

/// `<tspan>` (or `<a>` inside `<text>`) child element supporting nested styling,
/// absolute/relative coordinate lists, per-glyph rotation, and animations.
///
/// `<tspan>`（或 `<text>` 内的 `<a>`）子文本节点，支持嵌套样式、绝对/相对坐标列表、
/// 逐字形旋转以及属性动画。
final class SvgTextSpanNode extends SvgElement implements SvgTextContentItem {
  /// Optional absolute X coordinate list (`x`).
  ///
  /// 可选绝对 X 坐标列表（`x`）。
  final List<SvgTextLength> xList;

  /// Optional absolute Y coordinate list (`y`).
  ///
  /// 可选绝对 Y 坐标列表（`y`）。
  final List<SvgTextLength> yList;

  /// Optional relative X shift list (`dx`).
  ///
  /// 可选相对 X 偏移列表（`dx`）。
  final List<SvgTextLength> dxList;

  /// Optional relative Y shift list (`dy`).
  ///
  /// 可选相对 Y 偏移列表（`dy`）。
  final List<SvgTextLength> dyList;

  /// Optional per-glyph rotation angles in degrees (`rotate`).
  ///
  /// 可选逐字形旋转角度列表（单位：度，`rotate`）。
  final Float64List rotateList;

  /// Optional target advance length (`textLength`).
  ///
  /// 可选目标文本排版长度（`textLength`）。
  final SvgTextLength? textLength;

  /// Adjustment mode applied when [textLength] is set (`lengthAdjust`).
  ///
  /// 设置 [textLength] 时的拉伸适配模式（`lengthAdjust`）。
  final SvgLengthAdjust lengthAdjust;

  /// Ordered child text literals and nested span/path items.
  ///
  /// 有序子内容列表（包含纯文本字面量与嵌套文本节点）。
  final List<SvgTextContentItem> contentItems;

  /// Runtime animated override for `x` (`null` when not animated).
  ///
  /// 运行时 `x` 坐标动画覆盖值（未动画时为 `null`）。
  double? animatedX;

  /// Runtime animated override for `y` (`null` when not animated).
  ///
  /// 运行时 `y` 坐标动画覆盖值（未动画时为 `null`）。
  double? animatedY;

  /// Runtime animated override for `dx` (`null` when not animated).
  ///
  /// 运行时 `dx` 偏移动画覆盖值（未动画时为 `null`）。
  double? animatedDx;

  /// Runtime animated override for `dy` (`null` when not animated).
  ///
  /// 运行时 `dy` 偏移动画覆盖值（未动画时为 `null`）。
  double? animatedDy;

  final List<SvgElement> _childElements;

  /// Creates an [SvgTextSpanNode] with [contentItems] and optional positioning
  /// lists ([xList], [yList], [dxList], [dyList], [rotateList]), [textLength],
  /// and [lengthAdjust].
  ///
  /// 创建 [SvgTextSpanNode]，传入子内容 [contentItems] 及可选定位参数（[xList]、[yList]、[dxList]、[dyList]、[rotateList]）、[textLength] 和 [lengthAdjust]。
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
///
/// `<textPath>` 路径文本节点，沿引用的 `<path>` 几何节点（`href`/`xlink:href`）
/// 或 SVG 2 内联 `path` 数据排列并渲染子文本片段。
final class SvgTextPathNode extends SvgElement implements SvgTextContentItem {
  /// Optional referenced geometry element ID without the leading `#` (`href` / `xlink:href`).
  ///
  /// 可选引用几何元素的 ID（不含前导 `#`，来自 `href` / `xlink:href`）。
  final String? hrefId;

  /// Optional inline SVG 2 path data string (`path` attribute).
  ///
  /// 可选 SVG 2 内联路径命令字符串（`path` 属性）。
  final String? inlinePathData;

  /// Optional starting distance offset along the path (`startOffset`).
  ///
  /// 可选沿路径起始偏移距离（`startOffset`）。
  final SvgTextLength? startOffset;

  /// Whether SVG 2 `side="right"` reverses path traversal direction.
  ///
  /// 是否启用 SVG 2 `side="right"` 以反向沿路径排版。
  final bool sideRight;

  /// Optional target advance length along the path (`textLength`).
  ///
  /// 可选沿路径目标排版长度（`textLength`）。
  final SvgTextLength? textLength;

  /// Adjustment mode applied when [textLength] is set (`lengthAdjust`).
  ///
  /// 设置 [textLength] 时的拉伸适配模式（`lengthAdjust`）。
  final SvgLengthAdjust lengthAdjust;

  /// Ordered child text literals and nested span items.
  ///
  /// 有序子内容列表（纯文本与嵌套 `<tspan>` 节点）。
  final List<SvgTextContentItem> contentItems;

  final List<SvgElement> _childElements;

  /// Cached contour [ui.PathMetric]s for the resolved target path.
  ///
  /// 已解析目标路径的轮廓 [ui.PathMetric] 缓存列表。
  List<ui.PathMetric>? cachedPathMetrics;

  /// Total arc length across all contours in [cachedPathMetrics].
  ///
  /// [cachedPathMetrics] 中所有轮廓段的总弧长。
  double cachedTotalPathLength = 0.0;

  /// Creates an [SvgTextPathNode] with [contentItems] and optional [hrefId],
  /// [inlinePathData], [startOffset], [sideRight], [textLength], and [lengthAdjust].
  ///
  /// 创建 [SvgTextPathNode]，传入子内容 [contentItems] 及可选路径源（[hrefId]、[inlinePathData]）、起始偏移 [startOffset]、方向 [sideRight]、[textLength] 与 [lengthAdjust]。
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

  /// Resolves and caches the target path metrics from [inlinePathData] or
  /// [hrefId] within [document].
  ///
  /// 从 [inlinePathData] 或在 [document] 中查找 [hrefId] 解析并缓存目标路径的度量信息。
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
///
/// 顶层 `<text>` 图形文本节点，支持完整 W3C SVG 1.1 / SVG 2 文本排版、`<tspan>`、
/// `<textPath>`、基线对齐、`text-anchor`、`textLength`、填充/描边/渐变绘制、
/// `paint-order` 以及 SMIL/CSS 动画。
final class SvgTextNode extends SvgElement {
  /// Optional absolute X coordinate list (`x`).
  ///
  /// 可选绝对 X 坐标列表（`x`）。
  final List<SvgTextLength> xList;

  /// Optional absolute Y coordinate list (`y`).
  ///
  /// 可选绝对 Y 坐标列表（`y`）。
  final List<SvgTextLength> yList;

  /// Optional relative X shift list (`dx`).
  ///
  /// 可选相对 X 偏移列表（`dx`）。
  final List<SvgTextLength> dxList;

  /// Optional relative Y shift list (`dy`).
  ///
  /// 可选相对 Y 偏移列表（`dy`）。
  final List<SvgTextLength> dyList;

  /// Optional per-glyph rotation angles in degrees (`rotate`).
  ///
  /// 可选逐字形旋转角度列表（单位：度，`rotate`）。
  final Float64List rotateList;

  /// Optional target advance length (`textLength`).
  ///
  /// 可选目标文本排版长度（`textLength`）。
  final SvgTextLength? textLength;

  /// Adjustment mode applied when [textLength] is set (`lengthAdjust`).
  ///
  /// 设置 [textLength] 时的拉伸适配模式（`lengthAdjust`）。
  final SvgLengthAdjust lengthAdjust;

  /// Ordered child text literals, `<tspan>`, and `<textPath>` items.
  ///
  /// 有序子内容列表（包含纯文本、`<tspan>` 及 `<textPath>` 项）。
  final List<SvgTextContentItem> contentItems;

  /// Runtime animated override for `x` (`null` when not animated).
  ///
  /// 运行时 `x` 坐标动画覆盖值（未动画时为 `null`）。
  double? animatedX;

  /// Runtime animated override for `y` (`null` when not animated).
  ///
  /// 运行时 `y` 坐标动画覆盖值（未动画时为 `null`）。
  double? animatedY;

  /// Runtime animated override for `dx` (`null` when not animated).
  ///
  /// 运行时 `dx` 偏移动画覆盖值（未动画时为 `null`）。
  double? animatedDx;

  /// Runtime animated override for `dy` (`null` when not animated).
  ///
  /// 运行时 `dy` 偏移动画覆盖值（未动画时为 `null`）。
  double? animatedDy;

  final List<SvgElement> _childElements;

  /// Creates an [SvgTextNode] with [contentItems] and optional positioning lists
  /// ([xList], [yList], [dxList], [dyList], [rotateList]), [textLength], and
  /// [lengthAdjust].
  ///
  /// 创建 [SvgTextNode]，传入子内容 [contentItems] 及可选定位参数（[xList]、[yList]、[dxList]、[dyList]、[rotateList]）、[textLength] 和 [lengthAdjust]。
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

  /// Resolves the primary base X coordinate in user space relative to [viewBox]
  /// (defaults to `0.0`).
  ///
  /// 相对于 [viewBox] 解析用户坐标系下的主基准 X 坐标（缺省为 `0.0`）。
  double resolveBaseX(ui.Rect viewBox) {
    if (xList.isEmpty) return 0.0;
    return xList.first.resolve(
      fontSize: style.currentFontSize,
      referenceExtent: viewBox.width,
    );
  }

  /// Resolves the primary base Y coordinate in user space relative to [viewBox]
  /// (defaults to `0.0`).
  ///
  /// 相对于 [viewBox] 解析用户坐标系下的主基准 Y 坐标（缺省为 `0.0`）。
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
