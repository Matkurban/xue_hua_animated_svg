import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_gradient.dart';

/// Base sealed class for precompiled SVG `<filter>` primitives (`fe*`).
sealed class SvgFilterPrimitive {
  final String? inSource;
  final String? result;

  const SvgFilterPrimitive({this.inSource, this.result});
}

/// `<feGaussianBlur stdDeviation="sx [sy]" />`
final class SvgFeGaussianBlur extends SvgFilterPrimitive {
  final double sigmaX;
  final double sigmaY;

  const SvgFeGaussianBlur({
    super.inSource,
    super.result,
    required this.sigmaX,
    required this.sigmaY,
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

/// `<feComposite in="..." in2="..." operator="..." />`
final class SvgFeComposite extends SvgFilterPrimitive {
  final String? in2;
  final ui.BlendMode operatorMode;

  const SvgFeComposite({
    super.inSource,
    super.result,
    this.in2,
    this.operatorMode = ui.BlendMode.srcOver,
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
}
