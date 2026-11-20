import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_text_style.dart';
import 'svg_transform.dart';

/// How `transform-origin` X/Y coordinates are specified.
enum SvgOriginUnit {
  /// Absolute pixel offset in user space (`transform-box: view-box` or pixel coordinates).
  pixels,

  /// Percentage `[0.0 .. 1.0]` relative to the node's bounding box (`getBounds()`).
  boundingBoxPercent,

  /// Percentage `[0.0 .. 1.0]` relative to the root SVG `viewBox`.
  viewBoxPercent,
}

/// Precompiled `transform-origin` specification.
class SvgTransformOrigin {
  final double x;
  final double y;
  final SvgOriginUnit unitX;
  final SvgOriginUnit unitY;

  const SvgTransformOrigin({
    this.x = 0.0,
    this.y = 0.0,
    this.unitX = SvgOriginUnit.pixels,
    this.unitY = SvgOriginUnit.pixels,
  });

  static const SvgTransformOrigin zero = SvgTransformOrigin();

  static const SvgTransformOrigin center = SvgTransformOrigin(
    x: 0.5,
    y: 0.5,
    unitX: SvgOriginUnit.boundingBoxPercent,
    unitY: SvgOriginUnit.boundingBoxPercent,
  );

  bool get isZero =>
      x == 0.0 &&
      y == 0.0 &&
      unitX == SvgOriginUnit.pixels &&
      unitY == SvgOriginUnit.pixels;

  /// Resolves the concrete X anchor in local coordinates given [bounds] and [viewBox].
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

/// Paint server type for `fill` or `stroke`.
enum SvgPaintType { none, color, gradient }

/// Precompiled paint server (solid color, gradient reference, or none).
class SvgPaintServer {
  final SvgPaintType type;
  final ui.Color color;
  final String? gradientId;

  const SvgPaintServer._({
    required this.type,
    this.color = const ui.Color(0xFF000000),
    this.gradientId,
  });

  static const SvgPaintServer none = SvgPaintServer._(type: SvgPaintType.none);
  static const SvgPaintServer defaultBlack = SvgPaintServer._(
    type: SvgPaintType.color,
    color: ui.Color(0xFF000000),
  );

  factory SvgPaintServer.fromColor(ui.Color color) =>
      SvgPaintServer._(type: SvgPaintType.color, color: color);

  factory SvgPaintServer.fromGradient(String id) =>
      SvgPaintServer._(type: SvgPaintType.gradient, gradientId: id);

  bool get isVisible => type != SvgPaintType.none;
}

/// Precompiled SVG presentation & CSS style attributes for a single node.
///
/// Separate base (immutable after AST build) and current (mutated in-place by
/// animations during `tick`) values ensure zero memory allocations in the render loop.
class SvgStyle {
  // Base parsed paint & geometry properties
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
  bool baseDisplayNone = false;
  bool? baseVisibilityHidden;
  bool? baseOverflowVisible;
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
  SvgPaintOrder? basePaintOrder;

  // Runtime mutated properties (written in-place during animation tick)
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
  SvgPaintOrder currentPaintOrder = SvgPaintOrder.fillStroke;

  /// Resolves inherited style properties from [parentStyle] once during AST finalization.
  void resolveInheritance(SvgStyle? parentStyle) {
    resolvedFill =
        baseFill ?? parentStyle?.resolvedFill ?? SvgPaintServer.defaultBlack;
    resolvedStroke =
        baseStroke ?? parentStyle?.resolvedStroke ?? SvgPaintServer.none;
    currentFillColor = resolvedFill.color;
    currentStrokeColor = resolvedStroke.color;

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
        baseWhiteSpace ?? parentStyle?.currentWhiteSpace ?? SvgWhiteSpace.normal;
    currentPaintOrder =
        basePaintOrder ??
        parentStyle?.currentPaintOrder ??
        SvgPaintOrder.fillStroke;
  }

  /// Resets runtime values back to resolved initial values without allocating memory
  /// (except copying dasharray values into the pre-allocated list).
  void resetRuntimeToBase(SvgStyle? parentStyle) {
    resolvedFill =
        baseFill ?? parentStyle?.resolvedFill ?? SvgPaintServer.defaultBlack;
    resolvedStroke =
        baseStroke ?? parentStyle?.resolvedStroke ?? SvgPaintServer.none;
    currentFillColor = resolvedFill.color;
    currentStrokeColor = resolvedStroke.color;
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
  void syncInheritedFromParent(SvgStyle? parentStyle) {
    if (parentStyle == null) return;
    if (baseFill == null) {
      resolvedFill = parentStyle.resolvedFill;
      currentFillColor = parentStyle.currentFillColor;
    }
    if (baseStroke == null) {
      resolvedStroke = parentStyle.resolvedStroke;
      currentStrokeColor = parentStyle.currentStrokeColor;
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
    if (basePaintOrder == null) {
      currentPaintOrder = parentStyle.currentPaintOrder;
    }
  }

  /// Merges incoming style rules (e.g., from CSS selector matching or inline style)
  /// into this [SvgStyle] during the build phase.
  void mergeFrom(SvgStyle other) {
    if (other.baseFill != null) baseFill = other.baseFill;
    if (other.baseStroke != null) baseStroke = other.baseStroke;
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
    if (other.basePaintOrder != null) basePaintOrder = other.basePaintOrder;
  }
}
