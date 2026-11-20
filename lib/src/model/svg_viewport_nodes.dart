import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_container_nodes.dart';
import 'svg_document.dart';
import 'svg_element.dart';
import 'svg_preserve_aspect_ratio.dart';
import 'svg_transform.dart';

/// Graphic-level hyperlink container `<a>` node (W3C SVG 1.1 / SVG 2).
class SvgAnchorNode extends SvgGroupNode {
  final String? href;
  final String? target;

  SvgAnchorNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    super.children,
    this.href,
    this.target,
  }) : super(tagName: 'a');
}

/// Conditional processing attributes attached to a direct child of `<switch>`.
class SvgConditionalAttrs {
  final String? requiredExtensions;
  final String? requiredFeatures;
  final List<String> systemLanguages;

  const SvgConditionalAttrs({
    this.requiredExtensions,
    this.requiredFeatures,
    this.systemLanguages = const [],
  });

  /// Evaluates whether this child satisfies W3C SVG conditional processing rules.
  bool matches({String? activeLanguageTag}) {
    if (requiredExtensions != null && requiredExtensions!.trim().isNotEmpty) {
      return false;
    }
    if (systemLanguages.isNotEmpty) {
      final localeTag = (activeLanguageTag ?? _platformLanguageTag())
          .toLowerCase();
      bool langMatched = false;
      for (final raw in systemLanguages) {
        final candidate = raw.trim().toLowerCase();
        if (candidate.isEmpty) continue;
        if (localeTag == candidate ||
            localeTag.startsWith('$candidate-') ||
            candidate.startsWith('$localeTag-')) {
          langMatched = true;
          break;
        }
      }
      if (!langMatched) return false;
    }
    return true;
  }

  static String _platformLanguageTag() {
    final locale = ui.PlatformDispatcher.instance.locale;
    final country = locale.countryCode;
    if (country != null && country.isNotEmpty) {
      return '${locale.languageCode}-$country';
    }
    return locale.languageCode;
  }
}

/// Conditional `<switch>` container node (W3C SVG 1.1 §5.8.1 / SVG 2).
///
/// Evaluates child elements in document order and renders only the **first**
/// child whose conditional processing attributes (`requiredExtensions`,
/// `systemLanguage`) match the current environment.
class SvgSwitchNode extends SvgGroupNode {
  final List<SvgConditionalAttrs> childConditions;
  final String? languageOverride;
  SvgElement? _selectedChild;

  SvgSwitchNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    super.children,
    required this.childConditions,
    this.languageOverride,
  }) : super(tagName: 'switch');

  /// The single child element selected by `<switch>` evaluation, or `null`.
  SvgElement? get selectedChild => _selectedChild;

  SvgElement? _resolveSelectedChild() {
    for (int i = 0; i < children.length; i++) {
      final cond = i < childConditions.length
          ? childConditions[i]
          : const SvgConditionalAttrs();
      if (cond.matches(activeLanguageTag: languageOverride)) {
        return children[i];
      }
    }
    return null;
  }

  @override
  void initializeGeometry(SvgDocument document) {
    _selectedChild = _resolveSelectedChild();
    final chosen = _selectedChild;
    if (chosen != null) {
      chosen.initializeGeometry(document);
      cachedBounds = chosen.cachedBounds;
    } else {
      cachedBounds = ui.Rect.zero;
    }
    finalizeBaseTransforms(document.viewBox);
  }

  @override
  bool propagateAnimationFlags(SvgDocument document) {
    bool animated = hasSelfAnimation || hasMotionAnimation;
    final chosen = _selectedChild;
    if (chosen != null && chosen.propagateAnimationFlags(document)) {
      animated = true;
    }
    isAnimated = animated;
    return animated;
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    final chosen = _selectedChild;
    if (chosen == null) return;
    if (hasSelfAnimation) {
      chosen.style.syncInheritedFromParent(style);
    }
    chosen.paint(canvas, document);
  }
}

/// Nested `<svg>` viewport container establishing a new coordinate system,
/// optional `viewBox` + `preserveAspectRatio` mapping, and `overflow: hidden`
/// viewport clipping per W3C SVG 1.1 §5.1 / SVG 2.
class SvgNestedSvgNode extends SvgGroupNode {
  final double baseX;
  final double baseY;
  final double? baseWidth;
  final double? baseHeight;
  final ui.Rect? innerViewBox;
  final SvgPreserveAspectRatio preserveAspectRatio;

  double currentX;
  double currentY;
  double? currentWidth;
  double? currentHeight;

  final Float64List _innerViewBoxMatrix = SvgMatrixMath.createIdentity();

  SvgNestedSvgNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    super.children,
    this.baseX = 0.0,
    this.baseY = 0.0,
    this.baseWidth,
    this.baseHeight,
    this.innerViewBox,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
  }) : currentX = baseX,
       currentY = baseY,
       currentWidth = baseWidth,
       currentHeight = baseHeight,
       super(tagName: 'svg');

  bool get _overflowHidden => style.baseOverflowVisible != true;

  @override
  void initializeGeometry(SvgDocument document) {
    super.initializeGeometry(document);
    final w = baseWidth ?? innerViewBox?.width ?? cachedBounds.width;
    final h = baseHeight ?? innerViewBox?.height ?? cachedBounds.height;
    if (w > 0.0 && h > 0.0) {
      cachedBounds = ui.Rect.fromLTWH(baseX, baseY, w, h);
    }
    finalizeBaseTransforms(document.viewBox);
  }

  @override
  void resetFrameState() {
    super.resetFrameState();
    currentX = baseX;
    currentY = baseY;
    currentWidth = baseWidth;
    currentHeight = baseHeight;
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    paintWithViewport(
      canvas,
      document,
      effectiveOpacity,
      overrideWidth: null,
      overrideHeight: null,
    );
  }

  /// Paints this nested `<svg>` with optional width/height overrides from `<use>`.
  void paintWithViewport(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity, {
    double? overrideWidth,
    double? overrideHeight,
  }) {
    final w = overrideWidth ?? currentWidth ?? innerViewBox?.width;
    final h = overrideHeight ?? currentHeight ?? innerViewBox?.height;
    final hasOffset = currentX != 0.0 || currentY != 0.0;
    final hasClip = _overflowHidden && w != null && h != null && w > 0 && h > 0;
    final hasViewBox =
        innerViewBox != null && w != null && h != null && w > 0 && h > 0;

    final needsSave = hasOffset || hasClip || hasViewBox;
    if (needsSave) canvas.save();

    if (hasOffset) {
      canvas.translate(currentX, currentY);
    }
    if (hasClip) {
      canvas.clipRect(ui.Rect.fromLTWH(0.0, 0.0, w, h));
    }
    if (hasViewBox) {
      preserveAspectRatio.computeMatrixInPlace(
        innerViewBox!,
        ui.Size(w, h),
        _innerViewBoxMatrix,
      );
      canvas.transform(_innerViewBoxMatrix);
    }

    super.paintContent(canvas, document, effectiveOpacity);

    if (needsSave) canvas.restore();
  }
}

/// Reusable `<symbol>` template node (W3C SVG 1.1 §5.5 / SVG 2).
///
/// Never rendered directly in the scene tree; instantiated solely via `<use>`,
/// mapping its `viewBox` into the `<use>` element's `(width, height)` viewport.
class SvgSymbolNode extends SvgGroupNode {
  final double baseX;
  final double baseY;
  final double? baseWidth;
  final double? baseHeight;
  final double refX;
  final double refY;
  final ui.Rect? innerViewBox;
  final SvgPreserveAspectRatio preserveAspectRatio;

  final Float64List _symbolMatrix = SvgMatrixMath.createIdentity();

  SvgSymbolNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    super.children,
    this.baseX = 0.0,
    this.baseY = 0.0,
    this.baseWidth,
    this.baseHeight,
    this.refX = 0.0,
    this.refY = 0.0,
    this.innerViewBox,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
  }) : super(tagName: 'symbol');

  bool get _overflowHidden => style.baseOverflowVisible != true;

  @override
  bool get shouldCacheStaticPicture => false;

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // Per W3C SVG spec, <symbol> is never rendered directly; only via <use>.
  }

  /// Resolves the effective `(width, height)` for a `<use>` instantiation,
  /// preserving `innerViewBox` aspect ratio when only one dimension is given.
  ui.Size? resolveInstantiatedSize({double? useWidth, double? useHeight}) {
    final explicitW = useWidth ?? baseWidth;
    final explicitH = useHeight ?? baseHeight;
    final vb = innerViewBox;
    if (explicitW != null && explicitH != null) {
      return ui.Size(explicitW, explicitH);
    }
    if (explicitW != null) {
      if (vb != null && vb.width > 0.0 && vb.height > 0.0) {
        return ui.Size(explicitW, explicitW * (vb.height / vb.width));
      }
      return ui.Size(explicitW, explicitW);
    }
    if (explicitH != null) {
      if (vb != null && vb.width > 0.0 && vb.height > 0.0) {
        return ui.Size(explicitH * (vb.width / vb.height), explicitH);
      }
      return ui.Size(explicitH, explicitH);
    }
    if (vb != null && vb.width > 0.0 && vb.height > 0.0) {
      return ui.Size(vb.width, vb.height);
    }
    return null;
  }

  /// Instantiates and paints this `<symbol>` from a `<use>` element.
  void paintInstantiated(
    ui.Canvas canvas,
    SvgDocument document, {
    double? useWidth,
    double? useHeight,
  }) {
    if (style.displayNone) return;

    final resolvedSize = resolveInstantiatedSize(
      useWidth: useWidth,
      useHeight: useHeight,
    );
    final w = resolvedSize?.width;
    final h = resolvedSize?.height;
    final hasClip = _overflowHidden && w != null && h != null && w > 0 && h > 0;
    final hasViewBox =
        innerViewBox != null && w != null && h != null && w > 0 && h > 0;
    final hasOffset =
        baseX != 0.0 || baseY != 0.0 || refX != 0.0 || refY != 0.0;

    canvas.save();
    if (hasOffset) {
      canvas.translate(baseX - refX, baseY - refY);
    }
    if (hasClip) {
      canvas.clipRect(ui.Rect.fromLTWH(0.0, 0.0, w, h));
    }
    if (hasViewBox) {
      preserveAspectRatio.computeMatrixInPlace(
        innerViewBox!,
        ui.Size(w, h),
        _symbolMatrix,
      );
      canvas.transform(_symbolMatrix);
    }

    super.paintContent(canvas, document, style.currentOpacity.clamp(0.0, 1.0));
    canvas.restore();
  }
}

/// Named `<view>` specification defining an alternate `viewBox` and
/// `preserveAspectRatio` for SVG sprite sheets and view anchors (W3C SVG 1.1 §17.3 / SVG 2).
class SvgViewNode {
  final String id;
  final ui.Rect? viewBox;
  final SvgPreserveAspectRatio? preserveAspectRatio;

  const SvgViewNode({required this.id, this.viewBox, this.preserveAspectRatio});
}
