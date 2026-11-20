import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_filter_noise.dart';
import 'svg_gradient.dart';
import 'svg_preserve_aspect_ratio.dart';

export 'svg_filter_noise.dart';

part 'svg_filter_advanced.dart';

/// Base sealed class for precompiled SVG `<filter>` primitives (`fe*`).
sealed class SvgFilterPrimitive {
  final String? inSource;
  final String? result;
  final double? x;
  final double? y;
  final double? width;
  final double? height;

  const SvgFilterPrimitive({
    this.inSource,
    this.result,
    this.x,
    this.y,
    this.width,
    this.height,
  });

  /// Resolves the primitive subregion clipped within [filterRegion].
  ui.Rect resolveSubregion(
    ui.Rect filterRegion,
    ui.Rect targetBounds,
    SvgGradientUnits primitiveUnits,
  ) {
    if (x == null && y == null && width == null && height == null) {
      return filterRegion;
    }
    if (primitiveUnits == SvgGradientUnits.objectBoundingBox) {
      final bw = targetBounds.width == 0.0 ? filterRegion.width : targetBounds.width;
      final bh = targetBounds.height == 0.0 ? filterRegion.height : targetBounds.height;
      final rx = x != null ? targetBounds.left + x! * bw : filterRegion.left;
      final ry = y != null ? targetBounds.top + y! * bh : filterRegion.top;
      final rw = width != null ? width! * bw : filterRegion.width;
      final rh = height != null ? height! * bh : filterRegion.height;
      return ui.Rect.fromLTWH(rx, ry, rw, rh);
    }
    return ui.Rect.fromLTWH(
      x ?? filterRegion.left,
      y ?? filterRegion.top,
      width ?? filterRegion.width,
      height ?? filterRegion.height,
    );
  }
}

/// `<feGaussianBlur stdDeviation="sx [sy]" edgeMode="none|duplicate|wrap" />`
final class SvgFeGaussianBlur extends SvgFilterPrimitive {
  final double sigmaX;
  final double sigmaY;
  final ui.TileMode tileMode;

  const SvgFeGaussianBlur({
    super.inSource,
    super.result,
    required this.sigmaX,
    required this.sigmaY,
    this.tileMode = ui.TileMode.decal,
  });
}

/// `<feDropShadow dx="..." dy="..." stdDeviation="..." flood-color="..." flood-opacity="..." />`
final class SvgFeDropShadow extends SvgFilterPrimitive {
  final double dx;
  final double dy;
  final double sigmaX;
  final double sigmaY;
  final ui.Color floodColor;
  final double floodOpacity;

  const SvgFeDropShadow({
    super.inSource,
    super.result,
    this.dx = 2.0,
    this.dy = 2.0,
    this.sigmaX = 2.0,
    this.sigmaY = 2.0,
    this.floodColor = const ui.Color(0xFF000000),
    this.floodOpacity = 1.0,
  });
}

/// `<feOffset dx="..." dy="..." />`
final class SvgFeOffset extends SvgFilterPrimitive {
  final double dx;
  final double dy;

  const SvgFeOffset({
    super.inSource,
    super.result,
    this.dx = 0.0,
    this.dy = 0.0,
  });
}

/// Mode for `<feColorMatrix type="...">`.
enum SvgFeColorMatrixType { matrix, saturate, hueRotate, luminanceToAlpha }

/// `<feColorMatrix type="..." values="..." />`
final class SvgFeColorMatrix extends SvgFilterPrimitive {
  final SvgFeColorMatrixType type;
  final Float64List values;

  const SvgFeColorMatrix({
    super.inSource,
    super.result,
    this.type = SvgFeColorMatrixType.matrix,
    required this.values,
  });
}

/// `<feFlood flood-color="..." flood-opacity="..." />`
final class SvgFeFlood extends SvgFilterPrimitive {
  final ui.Color floodColor;
  final double floodOpacity;

  const SvgFeFlood({
    super.inSource,
    super.result,
    this.floodColor = const ui.Color(0xFF000000),
    this.floodOpacity = 1.0,
  });
}

/// `<feBlend in="..." in2="..." mode="..." />`
final class SvgFeBlend extends SvgFilterPrimitive {
  final String? in2;
  final ui.BlendMode mode;

  const SvgFeBlend({
    super.inSource,
    super.result,
    this.in2,
    this.mode = ui.BlendMode.srcOver,
  });
}

/// `<feComposite in="..." in2="..." operator="over|in|out|atop|xor|lighter|arithmetic" />`
final class SvgFeComposite extends SvgFilterPrimitive {
  final String? in2;
  final ui.BlendMode operatorMode;
  final bool isArithmetic;
  final double k1;
  final double k2;
  final double k3;
  final double k4;

  const SvgFeComposite({
    super.inSource,
    super.result,
    super.x,
    super.y,
    super.width,
    super.height,
    this.in2,
    this.operatorMode = ui.BlendMode.srcOver,
    this.isArithmetic = false,
    this.k1 = 0.0,
    this.k2 = 0.0,
    this.k3 = 0.0,
    this.k4 = 0.0,
  });
}

/// `<feMerge>` containing ordered `<feMergeNode in="..." />` inputs.
final class SvgFeMerge extends SvgFilterPrimitive {
  final List<String?> inputs;

  const SvgFeMerge({super.inSource, super.result, required this.inputs});
}

/// `<feMorphology operator="erode|dilate" radius="rx [ry]" />`
final class SvgFeMorphology extends SvgFilterPrimitive {
  final bool isDilate;
  final double radiusX;
  final double radiusY;

  const SvgFeMorphology({
    super.inSource,
    super.result,
    this.isDilate = false,
    this.radiusX = 0.0,
    this.radiusY = 0.0,
  });
}

/// Transfer function type for `<feFuncR|G|B|A type="...">`.
enum SvgFeTransferFuncType { identity, linear, gamma, table, discrete }

/// Precompiled channel transfer function inside `<feComponentTransfer>`.
class SvgFeTransferFunc {
  final SvgFeTransferFuncType type;
  final double slope;
  final double intercept;
  final double amplitude;
  final double exponent;
  final double offset;
  final Float64List tableValues;

  SvgFeTransferFunc({
    this.type = SvgFeTransferFuncType.identity,
    this.slope = 1.0,
    this.intercept = 0.0,
    this.amplitude = 1.0,
    this.exponent = 1.0,
    this.offset = 0.0,
    Float64List? tableValues,
  }) : tableValues = tableValues ?? Float64List(0);

  /// Approximates this channel transfer as `(scale, bias255)` for `ColorFilter.matrix`.
  (double, double) toAffineRow() {
    switch (type) {
      case SvgFeTransferFuncType.identity:
        return (1.0, 0.0);
      case SvgFeTransferFuncType.linear:
        return (slope, intercept * 255.0);
      case SvgFeTransferFuncType.gamma:
        // First-order affine approximation around mid-tone for GPU ColorFilter
        final s = amplitude * exponent;
        final b = (offset + amplitude * (1.0 - exponent) * 0.5) * 255.0;
        return (s, b);
      case SvgFeTransferFuncType.table:
      case SvgFeTransferFuncType.discrete:
        if (tableValues.length >= 2) {
          final v0 = tableValues.first;
          final v1 = tableValues.last;
          return (v1 - v0, v0 * 255.0);
        }
        if (tableValues.length == 1) {
          return (0.0, tableValues.first * 255.0);
        }
        return (1.0, 0.0);
    }
  }
}

/// `<feComponentTransfer>` with optional `<feFuncR>`, `<feFuncG>`, `<feFuncB>`, `<feFuncA>`.
final class SvgFeComponentTransfer extends SvgFilterPrimitive {
  final SvgFeTransferFunc? funcR;
  final SvgFeTransferFunc? funcG;
  final SvgFeTransferFunc? funcB;
  final SvgFeTransferFunc? funcA;

  const SvgFeComponentTransfer({
    super.inSource,
    super.result,
    this.funcR,
    this.funcG,
    this.funcB,
    this.funcA,
  });
}

/// `<feTurbulence type="fractalNoise|turbulence" baseFrequency="..." numOctaves="..." seed="..." stitchTiles="..." />`
final class SvgFeTurbulence extends SvgFilterPrimitive {
  final bool isFractalNoise;
  final double baseFreqX;
  final double baseFreqY;
  final int numOctaves;
  final int seed;
  final bool stitchTiles;

  ui.Rect? _cachedRegion;
  SvgFilterPixelField? _cachedField;
  ui.Picture? _cachedPicture;

  SvgFeTurbulence({
    super.inSource,
    super.result,
    this.isFractalNoise = false,
    this.baseFreqX = 0.0,
    this.baseFreqY = 0.0,
    this.numOctaves = 1,
    this.seed = 0,
    this.stitchTiles = false,
  });

  /// Returns or builds the cached [SvgFilterPixelField] for [region].
  SvgFilterPixelField resolveField(ui.Rect region) {
    if (_cachedField != null && _cachedRegion == region) {
      return _cachedField!;
    }
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedRegion = region;
    _cachedField = SvgFilterNoiseEngine.generateTurbulenceField(
      region: region,
      isFractalNoise: isFractalNoise,
      baseFreqX: baseFreqX,
      baseFreqY: baseFreqY,
      numOctaves: numOctaves,
      seed: seed,
      stitchTiles: stitchTiles,
    );
    return _cachedField!;
  }

  /// Returns or records the cached [ui.Picture] mesh for [region].
  ui.Picture resolvePicture(ui.Rect region) {
    final field = resolveField(region);
    if (_cachedPicture != null) return _cachedPicture!;
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, region);
    SvgFilterNoiseEngine.paintFieldMesh(c, field);
    _cachedPicture = rec.endRecording();
    return _cachedPicture!;
  }

  void dispose() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedField = null;
    _cachedRegion = null;
  }
}

/// `<feDisplacementMap in="..." in2="..." scale="..." xChannelSelector="..." yChannelSelector="..." />`
final class SvgFeDisplacementMap extends SvgFilterPrimitive {
  final String? in2;
  final double scale;
  final SvgChannelSelector xChannel;
  final SvgChannelSelector yChannel;

  const SvgFeDisplacementMap({
    super.inSource,
    super.result,
    this.in2,
    this.scale = 0.0,
    this.xChannel = SvgChannelSelector.a,
    this.yChannel = SvgChannelSelector.a,
  });
}

/// Precompiled `<filter>` graph definition (W3C Filter Effects Level 1).
class SvgFilterNode {
  final String id;
  final SvgGradientUnits filterUnits;
  final SvgGradientUnits primitiveUnits;
  final double x;
  final double y;
  final double width;
  final double height;
  final List<SvgFilterPrimitive> primitives;

  const SvgFilterNode({
    required this.id,
    this.filterUnits = SvgGradientUnits.objectBoundingBox,
    this.primitiveUnits = SvgGradientUnits.userSpaceOnUse,
    this.x = -0.1,
    this.y = -0.1,
    this.width = 1.2,
    this.height = 1.2,
    required this.primitives,
  });

  /// Resolves the filter region in user-space coordinates for [targetBounds].
  ui.Rect resolveFilterRegion(ui.Rect targetBounds) {
    if (filterUnits == SvgGradientUnits.objectBoundingBox) {
      final w = targetBounds.width == 0.0 ? 100.0 : targetBounds.width;
      final h = targetBounds.height == 0.0 ? 100.0 : targetBounds.height;
      return ui.Rect.fromLTWH(
        targetBounds.left + x * w,
        targetBounds.top + y * h,
        width * w,
        height * h,
      );
    }
    return ui.Rect.fromLTWH(x, y, width, height);
  }

  /// Releases any cached procedural noise `ui.Picture` resources.
  void dispose() {
    for (final prim in primitives) {
      if (prim is SvgFeTurbulence) {
        prim.dispose();
      }
    }
  }
}
