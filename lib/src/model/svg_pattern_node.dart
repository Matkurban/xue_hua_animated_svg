import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_container_nodes.dart';
import 'svg_document.dart';
import 'svg_gradient.dart';
import 'svg_preserve_aspect_ratio.dart';
import 'svg_transform.dart';

/// `<pattern>` paint server node (W3C SVG 1.1 §13.3 / SVG 2).
///
/// Rasterizes one tile offscreen into a cached `ui.Image` and returns a
/// repeating `ui.ImageShader` for both `fill="url(#...)"` and `stroke="url(#...)"`.
class SvgPatternNode extends SvgGroupNode {
  final String? hrefId;
  final SvgGradientUnits patternUnits;
  final SvgGradientUnits patternContentUnits;
  final double x;
  final double y;
  final double width;
  final double height;
  final ui.Rect? innerViewBox;
  final SvgPreserveAspectRatio preserveAspectRatio;
  final List<SvgTransformOp> basePatternTransformOps;

  final Float64List _patternTransformMatrix = SvgMatrixMath.createIdentity();
  final Float64List _shaderMatrix = SvgMatrixMath.createIdentity();
  final Float64List _viewBoxMatrix = SvgMatrixMath.createIdentity();

  ui.Image? _cachedTileImage;
  int _cachedPxWidth = 0;
  int _cachedPxHeight = 0;

  SvgPatternNode({
    super.id,
    super.classes,
    required super.style,
    super.children,
    this.hrefId,
    this.patternUnits = SvgGradientUnits.objectBoundingBox,
    this.patternContentUnits = SvgGradientUnits.userSpaceOnUse,
    this.x = 0.0,
    this.y = 0.0,
    this.width = 0.0,
    this.height = 0.0,
    this.innerViewBox,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
    this.basePatternTransformOps = const [],
  }) : super(tagName: 'pattern') {
    for (int i = 0; i < basePatternTransformOps.length; i++) {
      SvgMatrixMath.applyOpInPlace(
        _patternTransformMatrix,
        basePatternTransformOps[i],
      );
    }
  }

  @override
  bool get shouldCacheStaticPicture => false;

  /// Resolves inherited children from an `href`/`xlink:href` template `<pattern>`.
  void resolveTemplate(Map<String, SvgPatternNode> patternsById) {
    if (children.isEmpty && hrefId != null) {
      final template = patternsById[hrefId!];
      if (template != null && !identical(template, this)) {
        children.addAll(template.children);
      }
    }
  }

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <pattern> is a paint server and never painted directly.
  }

  /// Creates a repeating [ui.ImageShader] for [targetBounds].
  ui.Shader? createShader(ui.Rect targetBounds, SvgDocument document) {
    final double tileX;
    final double tileY;
    final double tileW;
    final double tileH;

    if (patternUnits == SvgGradientUnits.objectBoundingBox) {
      tileX = targetBounds.left + x * targetBounds.width;
      tileY = targetBounds.top + y * targetBounds.height;
      tileW = width * targetBounds.width;
      tileH = height * targetBounds.height;
    } else {
      tileX = x;
      tileY = y;
      tileW = width;
      tileH = height;
    }

    if (tileW <= 1e-4 || tileH <= 1e-4) return null;

    // Supersample small tiles up to 2x for crisp edges, capped at 512px per side
    final double dpr = (tileW < 64.0 || tileH < 64.0) ? 2.0 : 1.0;
    final int pxW = (tileW * dpr).ceil().clamp(1, 512);
    final int pxH = (tileH * dpr).ceil().clamp(1, 512);

    final needsRebuild =
        isAnimated ||
        _cachedTileImage == null ||
        _cachedPxWidth != pxW ||
        _cachedPxHeight != pxH;

    if (needsRebuild) {
      _cachedTileImage?.dispose();
      _cachedTileImage = null;

      final recorder = ui.PictureRecorder();
      final recCanvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0.0, 0.0, pxW.toDouble(), pxH.toDouble()),
      );

      final scaleToPxX = pxW / tileW;
      final scaleToPxY = pxH / tileH;
      recCanvas.scale(scaleToPxX, scaleToPxY);

      if (innerViewBox != null) {
        preserveAspectRatio.computeMatrixInPlace(
          innerViewBox!,
          ui.Size(tileW, tileH),
          _viewBoxMatrix,
        );
        recCanvas.transform(_viewBoxMatrix);
      } else if (patternContentUnits == SvgGradientUnits.objectBoundingBox &&
          targetBounds.width > 0.0 &&
          targetBounds.height > 0.0) {
        recCanvas.scale(targetBounds.width, targetBounds.height);
      }

      super.paintContent(recCanvas, document, 1.0);
      final picture = recorder.endRecording();
      _cachedTileImage = picture.toImageSync(pxW, pxH);
      picture.dispose();
      _cachedPxWidth = pxW;
      _cachedPxHeight = pxH;
    }

    final tileImage = _cachedTileImage;
    if (tileImage == null) return null;

    SvgMatrixMath.resetToIdentity(_shaderMatrix);
    SvgMatrixMath.multiply4x4InPlace(_shaderMatrix, _patternTransformMatrix);
    SvgMatrixMath.translateInPlace(_shaderMatrix, tileX, tileY);
    SvgMatrixMath.scaleInPlace(_shaderMatrix, tileW / pxW, tileH / pxH);

    return ui.ImageShader(
      tileImage,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      _shaderMatrix,
    );
  }

  @override
  void dispose() {
    _cachedTileImage?.dispose();
    _cachedTileImage = null;
    super.dispose();
  }
}
