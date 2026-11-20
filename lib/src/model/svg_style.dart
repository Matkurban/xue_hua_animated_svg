import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_css_clip_shape.dart';
import 'svg_filter_node.dart';
import 'svg_text_style.dart';
import 'svg_transform.dart';

/// Reference box for `transform-origin` percentages (W3C CSS Transforms Level 1).
/// `transform-origin` 百分比参考盒枚举（W3C CSS Transforms Level 1）。
enum SvgTransformBox {
  /// Relative to the element's local bounding box (`fill-box`). 相对元素自身包围盒。
  fillBox,

  /// Relative to the nearest SVG viewport `viewBox` (`view-box`). 相对最近 SVG `viewBox`。
  viewBox,
}

/// How `transform-origin` X/Y coordinates are specified.
/// `transform-origin` 坐标单位枚举。
enum SvgOriginUnit {
  /// Absolute pixel offset in user space. 用户空间绝对像素偏移。
  pixels,

  /// Percentage `[0.0 .. 1.0]` relative to the node's bounding box. 相对节点包围盒的百分比。
  boundingBoxPercent,

  /// Percentage `[0.0 .. 1.0]` relative to the root SVG `viewBox`. 相对根 `viewBox` 的百分比。
  viewBoxPercent,
}

/// Precompiled `transform-origin` specification.
/// 预编译的 `transform-origin` 变换原点配置。
class SvgTransformOrigin {
  /// X offset or normalized percentage (`0.0..1.0`). X 坐标偏移或归一化百分比。
  final double x;

  /// Y offset or normalized percentage (`0.0..1.0`). Y 坐标偏移或归一化百分比。
  final double y;

  /// Unit for [x]. [x] 的单位类型。
  final SvgOriginUnit unitX;

  /// Unit for [y]. [y] 的单位类型。
  final SvgOriginUnit unitY;

  /// Creates an [SvgTransformOrigin]. 创建一个 [SvgTransformOrigin] 变换原点。
  ///
  /// - [x]: X value. X 坐标值。
  /// - [y]: Y value. Y 坐标值。
  /// - [unitX]: Unit for [x]. X 单位。
  /// - [unitY]: Unit for [y]. Y 单位。
  const SvgTransformOrigin({
    this.x = 0.0,
    this.y = 0.0,
    this.unitX = SvgOriginUnit.pixels,
    this.unitY = SvgOriginUnit.pixels,
  });

  /// Zero pixel origin `(0, 0)`. 零点原点 `(0, 0)`。
  static const SvgTransformOrigin zero = SvgTransformOrigin();

  /// Bounding-box center origin `(50%, 50%)`. 包围盒中心原点 `(50%, 50%)`。
  static const SvgTransformOrigin center = SvgTransformOrigin(
    x: 0.5,
    y: 0.5,
    unitX: SvgOriginUnit.boundingBoxPercent,
    unitY: SvgOriginUnit.boundingBoxPercent,
  );

  /// Whether this origin is `(0px, 0px)`. 是否为零像素原点。
  bool get isZero =>
      x == 0.0 &&
      y == 0.0 &&
      unitX == SvgOriginUnit.pixels &&
      unitY == SvgOriginUnit.pixels;

  /// Resolves the concrete X anchor in local coordinates given [bounds] and [viewBox].
  /// 根据节点包围盒 [bounds] 与视口 [viewBox] 解析具体 X 原点坐标。
  ///
  /// - [bounds]: Element local bounding box. 元素局部包围盒。
  /// - [viewBox]: Nearest SVG `viewBox`. 所属 SVG `viewBox`。
  double resolveX(ui.Rect bounds, ui.Rect viewBox) {
    switch (unitX) {
      case SvgOriginUnit.pixels:
        return x;
      case SvgOriginUnit.boundingBoxPercent:
        return bounds.left + bounds.width * x;
      case SvgOriginUnit.viewBoxPercent:
        return viewBox.left + viewBox.width * x;
    }
  }

  /// Resolves the concrete Y anchor in local coordinates given [bounds] and [viewBox].
  /// 根据节点包围盒 [bounds] 与视口 [viewBox] 解析具体 Y 原点坐标。
  ///
  /// - [bounds]: Element local bounding box. 元素局部包围盒。
  /// - [viewBox]: Nearest SVG `viewBox`. 所属 SVG `viewBox`。
  double resolveY(ui.Rect bounds, ui.Rect viewBox) {
    switch (unitY) {
      case SvgOriginUnit.pixels:
        return y;
      case SvgOriginUnit.boundingBoxPercent:
        return bounds.top + bounds.height * y;
      case SvgOriginUnit.viewBoxPercent:
        return viewBox.top + viewBox.height * y;
    }
  }
}

/// Paint layer token for full 3-layer W3C SVG 2 `paint-order`.
/// W3C SVG 2 三层 `paint-order` 绘制层枚举。
enum SvgPaintLayer {
  /// Fill pass (`fill`). 填充层。
  fill,

  /// Stroke pass (`stroke`). 描边层。
  stroke,

  /// Path markers pass (`markers`). 端点标记层。
  markers,
}

/// Paint server type for `fill` or `stroke`.
/// `fill` 或 `stroke` 画刷服务类型枚举。
enum SvgPaintType {
  /// No paint (`none`). 不绘制。
  none,

  /// Solid sRGB color. 纯色。
  color,

  /// Reference to `<linearGradient>`, `<radialGradient>`, or `<pattern>` via `url(#id)`.
  /// 通过 `url(#id)` 引用的渐变或图案画刷。
  gradient,

  /// Inherits the node's resolved `color` property (`currentColor`).
  /// 继承元素当前解析的 `color` 属性（`currentColor`）。
  currentColor,
}

/// Precompiled paint server (solid color, gradient/pattern reference with
/// optional W3C fallback color, `currentColor`, or `none`).
/// 预编译画刷服务（支持纯色、带可选回退色的渐变/图案引用、`currentColor` 或 `none`）。
class SvgPaintServer {
  /// Paint server discriminator. 画刷服务类型。
  final SvgPaintType type;

  /// Solid color payload when [type] is [SvgPaintType.color]. 纯色值。
  final ui.Color color;

  /// Referenced gradient or pattern XML `id` when [type] is [SvgPaintType.gradient]. 引用的渐变/图案 ID。
  final String? gradientId;

  /// Optional W3C fallback color used when [gradientId] is missing (`url(#id) #color`).
  /// 当 [gradientId] 缺失时使用的可选 W3C 回退色。
  final ui.Color? fallbackColor;

  const SvgPaintServer._({
    required this.type,
    this.color = const ui.Color(0xFF000000),
    this.gradientId,
    this.fallbackColor,
  });

  /// Invisible paint (`none`). 不绘制画刷（`none`）。
  static const SvgPaintServer none = SvgPaintServer._(type: SvgPaintType.none);

  /// Dynamic `currentColor` paint server. 动态 `currentColor` 画刷。
  static const SvgPaintServer currentColor = SvgPaintServer._(
    type: SvgPaintType.currentColor,
  );

  /// SVG default solid black fill (`#000000`). SVG 默认纯黑填充。
  static const SvgPaintServer defaultBlack = SvgPaintServer._(
    type: SvgPaintType.color,
    color: ui.Color(0xFF000000),
  );

  /// Creates a solid color [SvgPaintServer] for [color].
  /// 从纯色 [color] 创建 [SvgPaintServer]。
  ///
  /// - [color]: Solid color. 纯色值。
  factory SvgPaintServer.fromColor(ui.Color color) =>
      SvgPaintServer._(type: SvgPaintType.color, color: color);

  /// Creates a gradient/pattern reference [SvgPaintServer] for [id] with optional [fallbackColor].
  /// 创建引用渐变/图案 [id]（带可选 [fallbackColor]）的 [SvgPaintServer]。
  ///
  /// - [id]: Target paint server `id`. 目标画刷服务 ID。
  /// - [fallbackColor]: Optional fallback solid color. 可选回退纯色。
  factory SvgPaintServer.fromGradient(String id, {ui.Color? fallbackColor}) =>
      SvgPaintServer._(
        type: SvgPaintType.gradient,
        gradientId: id,
        fallbackColor: fallbackColor,
      );

  /// Whether this paint server produces visible output (`type != SvgPaintType.none`).
  /// 该画刷是否可见（非 `none`）。
  bool get isVisible => type != SvgPaintType.none;
}

/// Precompiled SVG presentation and CSS style attributes for a single node.
/// 单个 SVG 节点的预编译表现属性与 CSS 样式集合（区分不可变基础值与每帧原地更新的运行时值）。
///
/// Separate base (immutable after AST build) and current (mutated in-place by
/// animations during `tick`) values ensure zero memory allocations in the render loop.
class SvgStyle {
  // Base parsed paint & geometry properties
  ui.Color? baseColor;
  SvgPaintServer? baseFill;
  SvgPaintServer? baseStroke;
  double? baseFillOpacity;
  double? baseStrokeOpacity;
  double? baseOpacity;
  double? baseStrokeWidth;
  ui.StrokeCap? baseStrokeCap;
  ui.StrokeJoin? baseStrokeJoin;
  double? baseStrokeMiterLimit;
  ui.PathFillType? baseFillRule;
  Float64List? baseStrokeDasharray;
  double? baseStrokeDashoffset;
  double? basePathLength;
  double? baseBlurSigma;
  SvgTransformOrigin? baseTransformOrigin;
  String? clipPathId;
  SvgCssClipShape? cssClipShape;
  String? maskId;
  String? filterId;
  bool? baseNonScalingStroke;
  List<SvgPaintLayer>? basePaintOrderLayers;
  List<SvgFilterPrimitive>? baseCssFilterPrimitives;
  String? baseMarkerStartId;
  String? baseMarkerMidId;
  String? baseMarkerEndId;
  bool baseDisplayNone = false;
  bool? baseVisibilityHidden;
  bool? baseOverflowVisible;
  bool? baseShapeRenderingCrisp;
  ui.BlendMode? baseMixBlendMode;
  bool? baseIsolationIsolate;
  SvgTransformBox? baseTransformBox;
  SvgTransformOp? baseCssTranslateOp;
  SvgTransformOp? baseCssRotateOp;
  SvgTransformOp? baseCssScaleOp;
  Map<String, String>? cssGeometryProps;
  final Map<String, String> customProperties = <String, String>{};
  bool displayNone = false;
  bool visibilityHidden = false;
  List<SvgTransformOp>? cssBaseTransformOps;

  // Base parsed SVG text presentation properties (W3C SVG 1.1 / SVG 2)
  String? baseFontFamily;
  List<String>? baseFontFamilyFallback;
  SvgTextLength? baseFontSizeSpec;
  ui.FontWeight? baseFontWeight;
  ui.FontStyle? baseFontStyle;
  bool? baseFontVariantSmallCaps;
  SvgTextAnchor? baseTextAnchor;
  SvgDominantBaseline? baseDominantBaseline;
  SvgDominantBaseline? baseAlignmentBaseline;
  SvgBaselineShift? baseBaselineShift;
  SvgTextLength? baseLetterSpacingSpec;
  SvgTextLength? baseWordSpacingSpec;
  ui.TextDecoration? baseTextDecoration;
  ui.TextDirection? baseTextDirection;
  SvgWhiteSpace? baseWhiteSpace;
  SvgTextTransform? baseTextTransform;
  SvgWritingMode? baseWritingMode;
  SvgPaintOrder? basePaintOrder;

  // Runtime mutated properties (written in-place during animation tick)
  ui.Color currentColor = const ui.Color(0xFF000000);
  SvgPaintServer resolvedFill = SvgPaintServer.defaultBlack;
  SvgPaintServer resolvedStroke = SvgPaintServer.none;
  ui.Color currentFillColor = const ui.Color(0xFF000000);
  ui.Color currentStrokeColor = const ui.Color(0x00000000);
  double currentFillOpacity = 1.0;
  double currentStrokeOpacity = 1.0;
  double currentOpacity = 1.0;
  double currentStrokeWidth = 1.0;
  ui.StrokeCap currentStrokeCap = ui.StrokeCap.butt;
  ui.StrokeJoin currentStrokeJoin = ui.StrokeJoin.miter;
  double currentStrokeMiterLimit = 4.0;
  ui.PathFillType currentFillRule = ui.PathFillType.nonZero;
  Float64List? currentStrokeDasharray;
  double currentStrokeDashoffset = 0.0;
  double? currentPathLength;
  double currentBlurSigma = 0.0;
  SvgTransformOrigin currentTransformOrigin = SvgTransformOrigin.zero;
  String? currentMarkerStartId;
  String? currentMarkerMidId;
  String? currentMarkerEndId;
  bool currentShapeRenderingCrisp = false;
  ui.BlendMode currentMixBlendMode = ui.BlendMode.srcOver;
  bool currentIsolationIsolate = false;
  SvgTransformBox currentTransformBox = SvgTransformBox.fillBox;

  // Runtime resolved SVG text properties
  String? currentFontFamily;
  List<String>? currentFontFamilyFallback;
  double resolvedBaseFontSize = 16.0;
  double currentFontSize = 16.0;
  ui.FontWeight currentFontWeight = ui.FontWeight.w400;
  ui.FontStyle currentFontStyle = ui.FontStyle.normal;
  bool currentFontVariantSmallCaps = false;
  SvgTextAnchor currentTextAnchor = SvgTextAnchor.start;
  SvgDominantBaseline currentDominantBaseline = SvgDominantBaseline.auto;
  SvgDominantBaseline? currentAlignmentBaseline;
  SvgBaselineShift currentBaselineShift = SvgBaselineShift.baseline;
  double? resolvedBaseLetterSpacing;
  double? currentLetterSpacing;
  double? currentWordSpacing;
  ui.TextDecoration currentTextDecoration = ui.TextDecoration.none;
  ui.TextDirection currentTextDirection = ui.TextDirection.ltr;
  SvgWhiteSpace currentWhiteSpace = SvgWhiteSpace.normal;
  SvgTextTransform currentTextTransform = SvgTextTransform.none;
  SvgWritingMode currentWritingMode = SvgWritingMode.horizontalTb;
  bool currentNonScalingStroke = false;
  SvgPaintOrder currentPaintOrder = SvgPaintOrder.fillStroke;
  List<SvgPaintLayer> currentPaintOrderLayers = const [
    SvgPaintLayer.fill,
    SvgPaintLayer.stroke,
    SvgPaintLayer.markers,
  ];

  /// Resolves inherited style properties from [parentStyle] once during AST finalization.
  /// 在 AST 构建完成阶段从父节点样式 [parentStyle] 一次性解析继承属性。
  ///
  /// - [parentStyle]: Optional parent element style (`null` for root). 可选父节点样式。
  void resolveInheritance(SvgStyle? parentStyle) {
    currentColor =
        baseColor ?? parentStyle?.currentColor ?? const ui.Color(0xFF000000);
    resolvedFill =
        baseFill ?? parentStyle?.resolvedFill ?? SvgPaintServer.defaultBlack;
    resolvedStroke =
        baseStroke ?? parentStyle?.resolvedStroke ?? SvgPaintServer.none;
    currentFillColor = resolvedFill.type == SvgPaintType.currentColor
        ? currentColor
        : resolvedFill.color;
    currentStrokeColor = resolvedStroke.type == SvgPaintType.currentColor
        ? currentColor
        : resolvedStroke.color;

    currentFillOpacity =
        baseFillOpacity ?? parentStyle?.currentFillOpacity ?? 1.0;
    currentStrokeOpacity =
        baseStrokeOpacity ?? parentStyle?.currentStrokeOpacity ?? 1.0;
    currentOpacity = baseOpacity ?? 1.0;
    currentStrokeWidth =
        baseStrokeWidth ?? parentStyle?.currentStrokeWidth ?? 1.0;
    currentStrokeCap =
        baseStrokeCap ?? parentStyle?.currentStrokeCap ?? ui.StrokeCap.butt;
    currentStrokeJoin =
        baseStrokeJoin ?? parentStyle?.currentStrokeJoin ?? ui.StrokeJoin.miter;
    currentStrokeMiterLimit =
        baseStrokeMiterLimit ?? parentStyle?.currentStrokeMiterLimit ?? 4.0;
    currentFillRule =
        baseFillRule ?? parentStyle?.currentFillRule ?? ui.PathFillType.nonZero;

    final inheritedDash =
        baseStrokeDasharray ?? parentStyle?.currentStrokeDasharray;
    if (inheritedDash != null && inheritedDash.isNotEmpty) {
      currentStrokeDasharray = Float64List.fromList(inheritedDash);
    } else {
      currentStrokeDasharray = null;
    }

    currentStrokeDashoffset =
        baseStrokeDashoffset ?? parentStyle?.currentStrokeDashoffset ?? 0.0;
    currentPathLength = basePathLength;
    currentBlurSigma = baseBlurSigma ?? 0.0;
    currentTransformOrigin = baseTransformOrigin ?? SvgTransformOrigin.zero;
    displayNone = baseDisplayNone;
    visibilityHidden =
        baseVisibilityHidden ?? parentStyle?.visibilityHidden ?? false;
    currentShapeRenderingCrisp =
        baseShapeRenderingCrisp ??
        parentStyle?.currentShapeRenderingCrisp ??
        false;
    currentMixBlendMode = baseMixBlendMode ?? ui.BlendMode.srcOver;
    currentIsolationIsolate = baseIsolationIsolate ?? false;
    currentTransformBox = baseTransformBox ?? SvgTransformBox.fillBox;
    if (parentStyle != null && parentStyle.customProperties.isNotEmpty) {
      for (final entry in parentStyle.customProperties.entries) {
        customProperties.putIfAbsent(entry.key, () => entry.value);
      }
    }
    currentMarkerStartId =
        baseMarkerStartId ?? parentStyle?.currentMarkerStartId;
    currentMarkerMidId = baseMarkerMidId ?? parentStyle?.currentMarkerMidId;
    currentMarkerEndId = baseMarkerEndId ?? parentStyle?.currentMarkerEndId;

    // Text presentation properties
    final parentFontSize = parentStyle?.currentFontSize ?? 16.0;
    if (baseFontSizeSpec != null) {
      resolvedBaseFontSize = baseFontSizeSpec!
          .resolve(
            fontSize: parentFontSize,
            rootFontSize: 16.0,
            referenceExtent: parentFontSize,
          )
          .clamp(0.0, double.infinity);
    } else {
      resolvedBaseFontSize = parentFontSize;
    }
    currentFontSize = resolvedBaseFontSize;

    currentFontFamily = baseFontFamily ?? parentStyle?.currentFontFamily;
    currentFontFamilyFallback =
        baseFontFamilyFallback ?? parentStyle?.currentFontFamilyFallback;
    currentFontWeight =
        baseFontWeight ?? parentStyle?.currentFontWeight ?? ui.FontWeight.w400;
    currentFontStyle =
        baseFontStyle ?? parentStyle?.currentFontStyle ?? ui.FontStyle.normal;
    currentFontVariantSmallCaps =
        baseFontVariantSmallCaps ??
        parentStyle?.currentFontVariantSmallCaps ??
        false;
    currentTextAnchor =
        baseTextAnchor ?? parentStyle?.currentTextAnchor ?? SvgTextAnchor.start;
    currentDominantBaseline =
        baseDominantBaseline ??
        parentStyle?.currentDominantBaseline ??
        SvgDominantBaseline.auto;
    // alignment-baseline and baseline-shift are non-inherited per W3C SVG spec
    currentAlignmentBaseline = baseAlignmentBaseline;
    currentBaselineShift = baseBaselineShift ?? SvgBaselineShift.baseline;

    if (baseLetterSpacingSpec != null) {
      resolvedBaseLetterSpacing = baseLetterSpacingSpec!.resolve(
        fontSize: currentFontSize,
        rootFontSize: 16.0,
        referenceExtent: currentFontSize,
      );
    } else {
      resolvedBaseLetterSpacing = parentStyle?.currentLetterSpacing;
    }
    currentLetterSpacing = resolvedBaseLetterSpacing;

    if (baseWordSpacingSpec != null) {
      currentWordSpacing = baseWordSpacingSpec!.resolve(
        fontSize: currentFontSize,
        rootFontSize: 16.0,
        referenceExtent: currentFontSize,
      );
    } else {
      currentWordSpacing = parentStyle?.currentWordSpacing;
    }

    currentTextDecoration =
        baseTextDecoration ??
        parentStyle?.currentTextDecoration ??
        ui.TextDecoration.none;
    currentTextDirection =
        baseTextDirection ??
        parentStyle?.currentTextDirection ??
        ui.TextDirection.ltr;
    currentWhiteSpace =
        baseWhiteSpace ??
        parentStyle?.currentWhiteSpace ??
        SvgWhiteSpace.normal;
    currentTextTransform =
        baseTextTransform ??
        parentStyle?.currentTextTransform ??
        SvgTextTransform.none;
    currentWritingMode =
        baseWritingMode ??
        parentStyle?.currentWritingMode ??
        SvgWritingMode.horizontalTb;
    currentNonScalingStroke = baseNonScalingStroke ?? false;
    currentPaintOrder =
        basePaintOrder ??
        parentStyle?.currentPaintOrder ??
        SvgPaintOrder.fillStroke;
    currentPaintOrderLayers =
        basePaintOrderLayers ??
        parentStyle?.currentPaintOrderLayers ??
        const [SvgPaintLayer.fill, SvgPaintLayer.stroke, SvgPaintLayer.markers];
  }

  /// Resets runtime values back to resolved initial values without allocating memory.
  /// 将运行时样式值原地重置回初始基值（零堆分配），用于每帧动画求值前复位。
  ///
  /// - [parentStyle]: Optional parent element style. 可选父节点样式。
  void resetRuntimeToBase(SvgStyle? parentStyle) {
    currentColor =
        baseColor ?? parentStyle?.currentColor ?? const ui.Color(0xFF000000);
    resolvedFill =
        baseFill ?? parentStyle?.resolvedFill ?? SvgPaintServer.defaultBlack;
    resolvedStroke =
        baseStroke ?? parentStyle?.resolvedStroke ?? SvgPaintServer.none;
    currentFillColor = resolvedFill.type == SvgPaintType.currentColor
        ? currentColor
        : resolvedFill.color;
    currentStrokeColor = resolvedStroke.type == SvgPaintType.currentColor
        ? currentColor
        : resolvedStroke.color;
    currentFillOpacity =
        baseFillOpacity ?? parentStyle?.currentFillOpacity ?? 1.0;
    currentStrokeOpacity =
        baseStrokeOpacity ?? parentStyle?.currentStrokeOpacity ?? 1.0;
    currentOpacity = baseOpacity ?? 1.0;
    currentStrokeWidth =
        baseStrokeWidth ?? parentStyle?.currentStrokeWidth ?? 1.0;
    currentStrokeDashoffset =
        baseStrokeDashoffset ?? parentStyle?.currentStrokeDashoffset ?? 0.0;
    currentBlurSigma = baseBlurSigma ?? 0.0;
    displayNone = baseDisplayNone;
    visibilityHidden =
        baseVisibilityHidden ?? parentStyle?.visibilityHidden ?? false;
    currentShapeRenderingCrisp =
        baseShapeRenderingCrisp ??
        parentStyle?.currentShapeRenderingCrisp ??
        false;
    currentMixBlendMode = baseMixBlendMode ?? ui.BlendMode.srcOver;
    currentIsolationIsolate = baseIsolationIsolate ?? false;
    currentFontSize = baseFontSizeSpec != null
        ? resolvedBaseFontSize
        : (parentStyle?.currentFontSize ?? resolvedBaseFontSize);
    currentLetterSpacing = baseLetterSpacingSpec != null
        ? resolvedBaseLetterSpacing
        : (parentStyle?.currentLetterSpacing ?? resolvedBaseLetterSpacing);

    final inheritedDash =
        baseStrokeDasharray ?? parentStyle?.currentStrokeDasharray;
    if (inheritedDash != null && currentStrokeDasharray != null) {
      if (currentStrokeDasharray!.length == inheritedDash.length) {
        for (int i = 0; i < inheritedDash.length; i++) {
          currentStrokeDasharray![i] = inheritedDash[i];
        }
      } else {
        currentStrokeDasharray = Float64List.fromList(inheritedDash);
      }
    }
  }

  /// Synchronizes any unset (inherited) presentation properties from [parentStyle]
  /// at render time without allocating heap objects.
  /// 渲染期零分配同步父节点 [parentStyle] 上已变化的继承属性（如动画驱动的父级样式）。
  ///
  /// - [parentStyle]: Optional parent element style. 可选父节点样式。
  void syncInheritedFromParent(SvgStyle? parentStyle) {
    if (parentStyle == null) return;
    if (baseColor == null) {
      currentColor = parentStyle.currentColor;
    }
    if (baseFill == null) {
      resolvedFill = parentStyle.resolvedFill;
      currentFillColor = resolvedFill.type == SvgPaintType.currentColor
          ? currentColor
          : parentStyle.currentFillColor;
    } else if (resolvedFill.type == SvgPaintType.currentColor) {
      currentFillColor = currentColor;
    }
    if (baseStroke == null) {
      resolvedStroke = parentStyle.resolvedStroke;
      currentStrokeColor = resolvedStroke.type == SvgPaintType.currentColor
          ? currentColor
          : parentStyle.currentStrokeColor;
    } else if (resolvedStroke.type == SvgPaintType.currentColor) {
      currentStrokeColor = currentColor;
    }
    if (baseShapeRenderingCrisp == null) {
      currentShapeRenderingCrisp = parentStyle.currentShapeRenderingCrisp;
    }
    if (baseFillOpacity == null) {
      currentFillOpacity = parentStyle.currentFillOpacity;
    }
    if (baseStrokeOpacity == null) {
      currentStrokeOpacity = parentStyle.currentStrokeOpacity;
    }
    if (baseStrokeWidth == null) {
      currentStrokeWidth = parentStyle.currentStrokeWidth;
    }
    if (baseStrokeCap == null) {
      currentStrokeCap = parentStyle.currentStrokeCap;
    }
    if (baseStrokeJoin == null) {
      currentStrokeJoin = parentStyle.currentStrokeJoin;
    }
    if (baseStrokeMiterLimit == null) {
      currentStrokeMiterLimit = parentStyle.currentStrokeMiterLimit;
    }
    if (baseFillRule == null) {
      currentFillRule = parentStyle.currentFillRule;
    }
    if (baseStrokeDashoffset == null) {
      currentStrokeDashoffset = parentStyle.currentStrokeDashoffset;
    }
    if (baseStrokeDasharray == null &&
        parentStyle.currentStrokeDasharray != null) {
      currentStrokeDasharray = parentStyle.currentStrokeDasharray;
    }
    if (baseVisibilityHidden == null) {
      visibilityHidden = parentStyle.visibilityHidden;
    }
    if (baseFontFamily == null) {
      currentFontFamily = parentStyle.currentFontFamily;
      currentFontFamilyFallback = parentStyle.currentFontFamilyFallback;
    }
    if (baseFontSizeSpec == null) {
      currentFontSize = parentStyle.currentFontSize;
    }
    if (baseFontWeight == null) {
      currentFontWeight = parentStyle.currentFontWeight;
    }
    if (baseFontStyle == null) {
      currentFontStyle = parentStyle.currentFontStyle;
    }
    if (baseFontVariantSmallCaps == null) {
      currentFontVariantSmallCaps = parentStyle.currentFontVariantSmallCaps;
    }
    if (baseTextAnchor == null) {
      currentTextAnchor = parentStyle.currentTextAnchor;
    }
    if (baseDominantBaseline == null) {
      currentDominantBaseline = parentStyle.currentDominantBaseline;
    }
    if (baseLetterSpacingSpec == null) {
      currentLetterSpacing = parentStyle.currentLetterSpacing;
    }
    if (baseWordSpacingSpec == null) {
      currentWordSpacing = parentStyle.currentWordSpacing;
    }
    if (baseTextDecoration == null) {
      currentTextDecoration = parentStyle.currentTextDecoration;
    }
    if (baseTextDirection == null) {
      currentTextDirection = parentStyle.currentTextDirection;
    }
    if (baseWhiteSpace == null) {
      currentWhiteSpace = parentStyle.currentWhiteSpace;
    }
    if (baseTextTransform == null) {
      currentTextTransform = parentStyle.currentTextTransform;
    }
    if (baseWritingMode == null) {
      currentWritingMode = parentStyle.currentWritingMode;
    }
    if (basePaintOrder == null) {
      currentPaintOrder = parentStyle.currentPaintOrder;
    }
  }

  /// Merges incoming style rules from [other] into this [SvgStyle] during the build phase.
  /// 在构建阶段将 [other] 中的样式规则合并覆盖到当前 [SvgStyle]。
  ///
  /// - [other]: Incoming style declaration layer. 待合并的样式层。
  void mergeFrom(SvgStyle other) {
    if (other.baseColor != null) baseColor = other.baseColor;
    if (other.baseFill != null) baseFill = other.baseFill;
    if (other.baseStroke != null) baseStroke = other.baseStroke;
    if (other.baseShapeRenderingCrisp != null) {
      baseShapeRenderingCrisp = other.baseShapeRenderingCrisp;
    }
    if (other.baseMixBlendMode != null) {
      baseMixBlendMode = other.baseMixBlendMode;
    }
    if (other.baseIsolationIsolate != null) {
      baseIsolationIsolate = other.baseIsolationIsolate;
    }
    if (other.baseFillOpacity != null) baseFillOpacity = other.baseFillOpacity;
    if (other.baseStrokeOpacity != null) {
      baseStrokeOpacity = other.baseStrokeOpacity;
    }
    if (other.baseOpacity != null) baseOpacity = other.baseOpacity;
    if (other.baseStrokeWidth != null) baseStrokeWidth = other.baseStrokeWidth;
    if (other.baseStrokeCap != null) baseStrokeCap = other.baseStrokeCap;
    if (other.baseStrokeJoin != null) baseStrokeJoin = other.baseStrokeJoin;
    if (other.baseStrokeMiterLimit != null) {
      baseStrokeMiterLimit = other.baseStrokeMiterLimit;
    }
    if (other.baseFillRule != null) baseFillRule = other.baseFillRule;
    if (other.baseStrokeDasharray != null) {
      baseStrokeDasharray = other.baseStrokeDasharray;
    }
    if (other.baseStrokeDashoffset != null) {
      baseStrokeDashoffset = other.baseStrokeDashoffset;
    }
    if (other.basePathLength != null) basePathLength = other.basePathLength;
    if (other.baseBlurSigma != null) baseBlurSigma = other.baseBlurSigma;
    if (other.baseTransformOrigin != null) {
      baseTransformOrigin = other.baseTransformOrigin;
    }
    if (other.clipPathId != null) clipPathId = other.clipPathId;
    if (other.cssClipShape != null) cssClipShape = other.cssClipShape;
    if (other.baseNonScalingStroke != null) {
      baseNonScalingStroke = other.baseNonScalingStroke;
    }
    if (other.basePaintOrderLayers != null) {
      basePaintOrderLayers = other.basePaintOrderLayers;
    }
    if (other.maskId != null) maskId = other.maskId;
    if (other.filterId != null) filterId = other.filterId;
    if (other.baseCssFilterPrimitives != null) {
      baseCssFilterPrimitives = other.baseCssFilterPrimitives;
    }
    if (other.baseMarkerStartId != null) {
      baseMarkerStartId = other.baseMarkerStartId;
    }
    if (other.baseMarkerMidId != null) {
      baseMarkerMidId = other.baseMarkerMidId;
    }
    if (other.baseMarkerEndId != null) {
      baseMarkerEndId = other.baseMarkerEndId;
    }
    if (other.baseDisplayNone) {
      baseDisplayNone = true;
      displayNone = true;
    }
    if (other.baseVisibilityHidden != null) {
      baseVisibilityHidden = other.baseVisibilityHidden;
      visibilityHidden = other.baseVisibilityHidden!;
    }
    if (other.baseOverflowVisible != null) {
      baseOverflowVisible = other.baseOverflowVisible;
    }
    if (other.baseTransformBox != null) {
      baseTransformBox = other.baseTransformBox;
    }
    if (other.baseCssTranslateOp != null) {
      baseCssTranslateOp = other.baseCssTranslateOp;
    }
    if (other.baseCssRotateOp != null) {
      baseCssRotateOp = other.baseCssRotateOp;
    }
    if (other.baseCssScaleOp != null) {
      baseCssScaleOp = other.baseCssScaleOp;
    }
    if (other.cssGeometryProps != null && other.cssGeometryProps!.isNotEmpty) {
      (cssGeometryProps ??= <String, String>{}).addAll(other.cssGeometryProps!);
    }
    if (other.customProperties.isNotEmpty) {
      customProperties.addAll(other.customProperties);
    }
    if (other.cssBaseTransformOps != null) {
      cssBaseTransformOps = other.cssBaseTransformOps;
    }
    if (other.baseFontFamily != null) baseFontFamily = other.baseFontFamily;
    if (other.baseFontFamilyFallback != null) {
      baseFontFamilyFallback = other.baseFontFamilyFallback;
    }
    if (other.baseFontSizeSpec != null) {
      baseFontSizeSpec = other.baseFontSizeSpec;
    }
    if (other.baseFontWeight != null) baseFontWeight = other.baseFontWeight;
    if (other.baseFontStyle != null) baseFontStyle = other.baseFontStyle;
    if (other.baseFontVariantSmallCaps != null) {
      baseFontVariantSmallCaps = other.baseFontVariantSmallCaps;
    }
    if (other.baseTextAnchor != null) baseTextAnchor = other.baseTextAnchor;
    if (other.baseDominantBaseline != null) {
      baseDominantBaseline = other.baseDominantBaseline;
    }
    if (other.baseAlignmentBaseline != null) {
      baseAlignmentBaseline = other.baseAlignmentBaseline;
    }
    if (other.baseBaselineShift != null) {
      baseBaselineShift = other.baseBaselineShift;
    }
    if (other.baseLetterSpacingSpec != null) {
      baseLetterSpacingSpec = other.baseLetterSpacingSpec;
    }
    if (other.baseWordSpacingSpec != null) {
      baseWordSpacingSpec = other.baseWordSpacingSpec;
    }
    if (other.baseTextDecoration != null) {
      baseTextDecoration = other.baseTextDecoration;
    }
    if (other.baseTextDirection != null) {
      baseTextDirection = other.baseTextDirection;
    }
    if (other.baseWhiteSpace != null) baseWhiteSpace = other.baseWhiteSpace;
    if (other.baseTextTransform != null) {
      baseTextTransform = other.baseTextTransform;
    }
    if (other.baseWritingMode != null) {
      baseWritingMode = other.baseWritingMode;
    }
    if (other.basePaintOrder != null) basePaintOrder = other.basePaintOrder;
  }
}
