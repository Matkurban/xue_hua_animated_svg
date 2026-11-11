import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_document.dart';
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
