import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_document.dart';
import 'svg_filter_executor.dart';
import 'svg_filter_node.dart';
import 'svg_mask_node.dart';
import 'svg_style.dart';
import 'svg_transform.dart';

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

  /// Recomputes [baseTransformMatrix] incorporating `transform-origin`,
  /// `transform-box`, and CSS Transforms Level 2 standalone properties once
  /// [cachedBounds] is known.
  void finalizeBaseTransforms(ui.Rect viewBox) {
    SvgMatrixMath.resetToIdentity(baseTransformMatrix);
    final origin = style.currentTransformOrigin;
    final refBounds = style.currentTransformBox == SvgTransformBox.viewBox
        ? viewBox
        : cachedBounds;
    final ox = origin.resolveX(refBounds, viewBox);
    final oy = origin.resolveY(refBounds, viewBox);

    if (baseTransformOps.isNotEmpty) {
      SvgMatrixMath.applyOpsWithOriginInPlace(
        baseTransformMatrix,
        baseTransformOps,
        originX: ox,
        originY: oy,
      );
    }

    // CSS Transforms Level 2 order: translate -> rotate -> scale -> transform
    final cssOps = <SvgTransformOp>[
      if (style.baseCssTranslateOp != null) style.baseCssTranslateOp!,
      if (style.baseCssRotateOp != null) style.baseCssRotateOp!,
      if (style.baseCssScaleOp != null) style.baseCssScaleOp!,
      if (style.cssBaseTransformOps != null) ...style.cssBaseTransformOps!,
    ];
    if (cssOps.isNotEmpty) {
      SvgMatrixMath.applyOpsWithOriginInPlace(
        baseTransformMatrix,
        cssOps,
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

    // Check if fill or stroke references an animated gradient or pattern
    final fillServerId = style.resolvedFill.gradientId;
    if (fillServerId != null) {
      final grad = document.gradientsById[fillServerId];
      final pat = document.patternsById[fillServerId];
      if ((grad != null && grad.isAnimated) ||
          (pat != null && pat.isAnimated)) {
        animated = true;
      }
    }
    final strokeServerId = style.resolvedStroke.gradientId;
    if (strokeServerId != null) {
      final grad = document.gradientsById[strokeServerId];
      final pat = document.patternsById[strokeServerId];
      if ((grad != null && grad.isAnimated) ||
          (pat != null && pat.isAnimated)) {
        animated = true;
      }
    }
    // Check if referenced clipPath or mask is animated
    final clipId = style.clipPathId;
    if (clipId != null) {
      final clip = document.clipPathsById[clipId];
      if (clip != null && clip.isAnimated) animated = true;
    }
    final maskId = style.maskId;
    if (maskId != null) {
      final mask = document.masksById[maskId];
      if (mask != null && mask.isAnimated) animated = true;
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

  /// Depth counter > 0 while painting inside a `<use>` instantiation so shared
  /// `<symbol>` / `<defs>` subtrees bypass static `cachedPicture` and honor
  /// per-instance inherited styles (e.g., different `fill`/`stroke` per `<use>`).
  static int _dynamicUsePaintDepth = 0;

  /// Begins a dynamic `<use>` paint pass that bypasses `cachedPicture`.
  static void beginDynamicUsePaint() => _dynamicUsePaintDepth++;

  /// Ends a dynamic `<use>` paint pass.
  static void endDynamicUsePaint() {
    if (_dynamicUsePaintDepth > 0) _dynamicUsePaintDepth--;
  }

  /// Recursively pushes inherited style properties from [parentStyle] through
  /// this node and its descendants (used when `<use>` instantiates a template).
  void syncInheritedStyleTree(SvgStyle? parentStyle) {
    style.syncInheritedFromParent(parentStyle);
    for (int i = 0; i < children.length; i++) {
      children[i].syncInheritedStyleTree(style);
    }
  }

  /// Recursively restores resolved runtime styles back to base values from
  /// [parentStyle] after a `<use>` instantiation finishes.
  void restoreBaseStyleTree(SvgStyle? parentStyle) {
    style.resetRuntimeToBase(parentStyle);
    for (int i = 0; i < children.length; i++) {
      children[i].restoreBaseStyleTree(style);
    }
  }

  /// Renders this node onto [canvas]. Uses `cachedPicture` if `isAnimated == false`
  /// and this node is a group or complex static subtree.
  void paint(ui.Canvas canvas, SvgDocument document) {
    if (style.displayNone) return;

    if (_dynamicUsePaintDepth == 0 && !isAnimated && shouldCacheStaticPicture) {
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
    final cssClip = style.cssClipShape;
    final maskId = style.maskId;
    final maskNode = maskId != null ? document.masksById[maskId] : null;
    final filterId = style.filterId;
    final filterNode = filterId != null ? document.filtersById[filterId] : null;
    final opacity = style.currentOpacity.clamp(0.0, 1.0);
    final mixBlendMode = style.currentMixBlendMode;
    final hasBlend = mixBlendMode != ui.BlendMode.srcOver;
    final hasIsolation = style.currentIsolationIsolate;
    final needsLayer =
        hasBlend || hasIsolation || (opacity < 1.0 && children.isNotEmpty);

    final needsSave =
        hasTransform ||
        hasMotion ||
        clipNode != null ||
        cssClip != null ||
        maskNode != null ||
        filterNode != null ||
        needsLayer;
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
      canvas.clipPath(clipNode.resolveClipPath(document, cachedBounds));
    }
    if (cssClip != null) {
      canvas.clipPath(cssClip.resolvePath(cachedBounds));
    }
    if (needsLayer) {
      cachedLayerPaint
        ..blendMode = mixBlendMode
        ..color = ui.Color.fromARGB(
          (opacity * 255.0).round().clamp(0, 255),
          255,
          255,
          255,
        );
      canvas.saveLayer(null, cachedLayerPaint);
    }

    void drawBody(ui.Canvas targetCanvas) {
      if (maskNode != null) {
        final maskBounds = maskNode.resolveMaskRegion(cachedBounds);
        targetCanvas.saveLayer(maskBounds, ui.Paint());
        paintContent(targetCanvas, document, needsLayer ? 1.0 : opacity);
        final dstInPaint = ui.Paint()..blendMode = ui.BlendMode.dstIn;
        if (maskNode.maskType == SvgMaskType.luminance) {
          dstInPaint.colorFilter = SvgMaskNode.luminanceToAlphaFilter;
        }
        targetCanvas.saveLayer(maskBounds, dstInPaint);
        maskNode.paintMaskContent(targetCanvas, document, cachedBounds);
        targetCanvas.restore();
        targetCanvas.restore();
      } else {
        paintContent(targetCanvas, document, needsLayer ? 1.0 : opacity);
      }
    }

    final cssFilters = style.baseCssFilterPrimitives;
    if (filterNode != null && cssFilters != null && cssFilters.isNotEmpty) {
      final combined = SvgFilterNode(
        id: filterNode.id,
        filterUnits: filterNode.filterUnits,
        primitiveUnits: filterNode.primitiveUnits,
        x: filterNode.x,
        y: filterNode.y,
        width: filterNode.width,
        height: filterNode.height,
        primitives: [...filterNode.primitives, ...cssFilters],
      );
      SvgFilterExecutor.paintWithFilter(
        canvas: canvas,
        filter: combined,
        targetBounds: cachedBounds,
        paintSource: drawBody,
        document: document,
      );
    } else if (filterNode != null) {
      SvgFilterExecutor.paintWithFilter(
        canvas: canvas,
        filter: filterNode,
        targetBounds: cachedBounds,
        paintSource: drawBody,
        document: document,
      );
    } else if (cssFilters != null && cssFilters.isNotEmpty) {
      final inlineFilter = SvgFilterNode(
        id: '',
        x: -0.5,
        y: -0.5,
        width: 2.0,
        height: 2.0,
        primitives: cssFilters,
      );
      SvgFilterExecutor.paintWithFilter(
        canvas: canvas,
        filter: inlineFilter,
        targetBounds: cachedBounds,
        paintSource: drawBody,
        document: document,
      );
    } else {
      drawBody(canvas);
    }

    if (needsLayer) {
      canvas.restore();
    }
    if (needsSave) {
      canvas.restore();
    }
  }

  /// Computes the effective 2D isotropic scale factor from this element up to
  /// the root viewport (used by `vector-effect="non-scaling-stroke"`).
  double computeAccumulatedScale(SvgDocument document) {
    double scale = _matrix2dScale(document.viewBoxMatrix);
    SvgElement? cur = this;
    while (cur != null) {
      if (!SvgMatrixMath.isIdentity(cur.transformMatrix)) {
        scale *= _matrix2dScale(cur.transformMatrix);
      }
      if (cur.hasMotionAnimation && !SvgMatrixMath.isIdentity(cur.motionMatrix)) {
        scale *= _matrix2dScale(cur.motionMatrix);
      }
      cur = cur.parent;
    }
    return scale > 1e-6 ? scale : 1.0;
  }

  static double _matrix2dScale(Float64List m) {
    final sx = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    final sy = math.sqrt(m[4] * m[4] + m[5] * m[5]);
    final prod = sx * sy;
    return prod > 1e-12 ? math.sqrt(prod) : 1.0;
  }

  /// Subclass hook to draw geometry or child elements.
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  );

  /// Disposes and clears any cached static [ui.Picture] on this node and its
  /// descendants (e.g., when an asynchronous `<image>` finishes decoding).
  void invalidatePictureCache() {
    cachedPicture?.dispose();
    cachedPicture = null;
    for (final child in children) {
      child.invalidatePictureCache();
    }
  }

  /// Releases native `ui.Picture` resources.
  void dispose() {
    cachedPicture?.dispose();
    cachedPicture = null;
    for (final child in children) {
      child.dispose();
    }
  }
}
