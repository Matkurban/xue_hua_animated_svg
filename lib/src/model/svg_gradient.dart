import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_transform.dart';

/// Coordinate system for `<linearGradient>` and `<radialGradient>`.
enum SvgGradientUnits { objectBoundingBox, userSpaceOnUse }

/// Gradient `<stop>` element with precompiled base values and mutable runtime fields.
class SvgGradientStop {
  final String? id;
  final double baseOffset;
  final ui.Color baseColor;
  final double baseOpacity;

  double currentOffset;
  ui.Color currentColor;
  double currentOpacity;
  bool isAnimated = false;

  SvgGradientStop({
    this.id,
    required this.baseOffset,
    required this.baseColor,
    this.baseOpacity = 1.0,
  }) : currentOffset = baseOffset.clamp(0.0, 1.0),
       currentColor = baseColor,
       currentOpacity = baseOpacity.clamp(0.0, 1.0);

  void resetToBase() {
    currentOffset = baseOffset.clamp(0.0, 1.0);
    currentColor = baseColor;
    currentOpacity = baseOpacity.clamp(0.0, 1.0);
  }

  ui.Color get effectiveColor {
    if (currentOpacity >= 1.0) return currentColor;
    final combinedAlpha = (currentColor.a * currentOpacity.clamp(0.0, 1.0))
        .clamp(0.0, 1.0);
    return currentColor.withValues(alpha: combinedAlpha);
  }
}

/// Abstract base class for `<linearGradient>` and `<radialGradient>`.
abstract class SvgGradientNode {
  final String id;
  final String? hrefId;
  final SvgGradientUnits gradientUnits;
  final ui.TileMode spreadMethod;
  final List<SvgGradientStop> stops;
  final List<SvgTransformOp> baseGradientTransformOps;

  /// Pre-allocated 4x4 transform matrix for gradient space + `gradientTransform`.
  final Float64List baseGradientMatrix = SvgMatrixMath.createIdentity();
  final Float64List currentGradientMatrix = SvgMatrixMath.createIdentity();
  final Float64List shaderMatrix = SvgMatrixMath.createIdentity();

  /// Pre-allocated stop color and offset buffers to avoid list allocations per frame.
  late List<ui.Color> cachedColors;
  late List<double> cachedOffsets;

  bool isAnimated = false;

  SvgGradientNode({
    required this.id,
    this.hrefId,
    this.gradientUnits = SvgGradientUnits.objectBoundingBox,
    this.spreadMethod = ui.TileMode.clamp,
    required this.stops,
    this.baseGradientTransformOps = const [],
  }) {
    for (int i = 0; i < baseGradientTransformOps.length; i++) {
      SvgMatrixMath.applyOpInPlace(
        baseGradientMatrix,
        baseGradientTransformOps[i],
      );
    }
    SvgMatrixMath.copyInto(baseGradientMatrix, currentGradientMatrix);
    _allocateStopBuffers();
  }

  void _allocateStopBuffers() {
    cachedColors = List<ui.Color>.filled(
      stops.length,
      const ui.Color(0x00000000),
    );
    cachedOffsets = List<double>.filled(stops.length, 0.0);
    syncStopsToBuffers();
  }

  /// Resolves inherited stops from `href` / `xlink:href` template gradients.
  void resolveTemplate(Map<String, SvgGradientNode> gradientsById) {
    if (stops.isEmpty && hrefId != null) {
      final template = gradientsById[hrefId!];
      if (template != null) {
        for (final stop in template.stops) {
          stops.add(
            SvgGradientStop(
              id: stop.id,
              baseOffset: stop.baseOffset,
              baseColor: stop.baseColor,
              baseOpacity: stop.baseOpacity,
            )..isAnimated = stop.isAnimated,
          );
        }
        _allocateStopBuffers();
      }
    }
    for (final stop in stops) {
      if (stop.isAnimated) {
        isAnimated = true;
      }
    }
  }

  /// Updates [cachedColors] and [cachedOffsets] in-place from [stops].
  void syncStopsToBuffers() {
    if (cachedColors.length != stops.length) {
      _allocateStopBuffers();
      return;
    }
    double lastOffset = 0.0;
    for (int i = 0; i < stops.length; i++) {
      final stop = stops[i];
      cachedColors[i] = stop.effectiveColor;
      final clamped = stop.currentOffset.clamp(0.0, 1.0);
      final monotonic = clamped < lastOffset ? lastOffset : clamped;
      cachedOffsets[i] = monotonic;
      lastOffset = monotonic;
    }
  }

  void resetToBase() {
    SvgMatrixMath.copyInto(baseGradientMatrix, currentGradientMatrix);
    for (int i = 0; i < stops.length; i++) {
      stops[i].resetToBase();
    }
    syncStopsToBuffers();
  }

  /// Computes the combined 4x4 matrix mapping gradient coordinates into [targetBounds]
  /// when [gradientUnits] is [SvgGradientUnits.objectBoundingBox].
  Float64List computeShaderMatrix(ui.Rect targetBounds) {
    SvgMatrixMath.resetToIdentity(shaderMatrix);
    if (gradientUnits == SvgGradientUnits.objectBoundingBox) {
      SvgMatrixMath.translateInPlace(
        shaderMatrix,
        targetBounds.left,
        targetBounds.top,
      );
      SvgMatrixMath.scaleInPlace(
        shaderMatrix,
        targetBounds.width == 0.0 ? 1.0 : targetBounds.width,
        targetBounds.height == 0.0 ? 1.0 : targetBounds.height,
      );
    }
    SvgMatrixMath.multiply4x4InPlace(shaderMatrix, currentGradientMatrix);
    return shaderMatrix;
  }

  /// Builds a [ui.Shader] for the given geometry [targetBounds].
  ui.Shader? createShader(ui.Rect targetBounds);
}

/// Precompiled `<linearGradient>` node with mutable endpoints `(x1, y1)` -> `(x2, y2)`.
class SvgLinearGradientNode extends SvgGradientNode {
  final double baseX1;
  final double baseY1;
  final double baseX2;
  final double baseY2;

  double currentX1;
  double currentY1;
  double currentX2;
  double currentY2;

  SvgLinearGradientNode({
    required super.id,
    super.hrefId,
    super.gradientUnits,
    super.spreadMethod,
    required super.stops,
    super.baseGradientTransformOps,
    this.baseX1 = 0.0,
    this.baseY1 = 0.0,
    this.baseX2 = 1.0,
    this.baseY2 = 0.0,
  }) : currentX1 = baseX1,
       currentY1 = baseY1,
       currentX2 = baseX2,
       currentY2 = baseY2;

  @override
  void resetToBase() {
    super.resetToBase();
    currentX1 = baseX1;
    currentY1 = baseY1;
    currentX2 = baseX2;
    currentY2 = baseY2;
  }

  @override
  ui.Shader? createShader(ui.Rect targetBounds) {
    if (stops.isEmpty) return null;
    syncStopsToBuffers();
    final matrix = computeShaderMatrix(targetBounds);
    return ui.Gradient.linear(
      ui.Offset(currentX1, currentY1),
      ui.Offset(currentX2, currentY2),
      cachedColors,
      cachedOffsets,
      spreadMethod,
      matrix,
    );
  }
}

/// Precompiled `<radialGradient>` node with mutable center `(cx, cy)`, radius `r`,
/// and focal point `(fx, fy)`.
class SvgRadialGradientNode extends SvgGradientNode {
  final double baseCx;
  final double baseCy;
  final double baseR;
  final double baseFx;
  final double baseFy;

  double currentCx;
  double currentCy;
  double currentR;
  double currentFx;
  double currentFy;

  SvgRadialGradientNode({
    required super.id,
    super.hrefId,
    super.gradientUnits,
    super.spreadMethod,
    required super.stops,
    super.baseGradientTransformOps,
    this.baseCx = 0.5,
    this.baseCy = 0.5,
    this.baseR = 0.5,
    double? baseFx,
    double? baseFy,
  }) : baseFx = baseFx ?? baseCx,
       baseFy = baseFy ?? baseCy,
       currentCx = baseCx,
       currentCy = baseCy,
       currentR = baseR,
       currentFx = baseFx ?? baseCx,
       currentFy = baseFy ?? baseCy;

  @override
  void resetToBase() {
    super.resetToBase();
    currentCx = baseCx;
    currentCy = baseCy;
    currentR = baseR;
    currentFx = baseFx;
    currentFy = baseFy;
  }

  @override
  ui.Shader? createShader(ui.Rect targetBounds) {
    if (stops.isEmpty || currentR <= 0.0) return null;
    syncStopsToBuffers();
    final matrix = computeShaderMatrix(targetBounds);
    final hasFocal =
        (currentFx - currentCx).abs() > 1e-5 ||
        (currentFy - currentCy).abs() > 1e-5;
    return ui.Gradient.radial(
      ui.Offset(currentCx, currentCy),
      currentR,
      cachedColors,
      cachedOffsets,
      spreadMethod,
      matrix,
      hasFocal ? ui.Offset(currentFx, currentFy) : null,
      0.0,
    );
  }
}
