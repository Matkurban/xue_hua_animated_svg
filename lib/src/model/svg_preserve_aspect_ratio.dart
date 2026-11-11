import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_transform.dart';

/// Alignment mode for SVG `preserveAspectRatio`.
enum SvgAspectRatioAlign {
  none,
  xMinYMin,
  xMidYMin,
  xMaxYMin,
  xMinYMid,
  xMidYMid,
  xMaxYMid,
  xMinYMax,
  xMidYMax,
  xMaxYMax,
}

/// Meet or slice scaling mode for SVG `preserveAspectRatio`.
enum SvgMeetOrSlice { meet, slice }

/// Precompiled `preserveAspectRatio` configuration.
class SvgPreserveAspectRatio {
  final SvgAspectRatioAlign align;
  final SvgMeetOrSlice meetOrSlice;

  const SvgPreserveAspectRatio({
    this.align = SvgAspectRatioAlign.xMidYMid,
    this.meetOrSlice = SvgMeetOrSlice.meet,
  });

  static const SvgPreserveAspectRatio defaultValue = SvgPreserveAspectRatio();

  /// Computes the 4x4 transformation matrix mapping [viewBox] into [viewportSize]
  /// in-place into [outMatrix] without allocating memory.
  void computeMatrixInPlace(
    ui.Rect viewBox,
    ui.Size viewportSize,
    Float64List outMatrix,
  ) {
    SvgMatrixMath.resetToIdentity(outMatrix);
    if (viewBox.width <= 0.0 ||
        viewBox.height <= 0.0 ||
        viewportSize.width <= 0.0 ||
        viewportSize.height <= 0.0) {
      return;
    }

    final scaleX = viewportSize.width / viewBox.width;
    final scaleY = viewportSize.height / viewBox.height;

    if (align == SvgAspectRatioAlign.none) {
      SvgMatrixMath.scaleInPlace(outMatrix, scaleX, scaleY);
      SvgMatrixMath.translateInPlace(outMatrix, -viewBox.left, -viewBox.top);
      return;
    }

    final uniformScale = meetOrSlice == SvgMeetOrSlice.meet
        ? math.min(scaleX, scaleY)
        : math.max(scaleX, scaleY);

    final scaledWidth = viewBox.width * uniformScale;
    final scaledHeight = viewBox.height * uniformScale;
    final spareX = viewportSize.width - scaledWidth;
    final spareY = viewportSize.height - scaledHeight;

    double offsetX = 0.0;
    double offsetY = 0.0;

    switch (align) {
      case SvgAspectRatioAlign.xMinYMin:
      case SvgAspectRatioAlign.xMinYMid:
      case SvgAspectRatioAlign.xMinYMax:
        offsetX = 0.0;
      case SvgAspectRatioAlign.xMidYMin:
      case SvgAspectRatioAlign.xMidYMid:
      case SvgAspectRatioAlign.xMidYMax:
        offsetX = spareX * 0.5;
      case SvgAspectRatioAlign.xMaxYMin:
      case SvgAspectRatioAlign.xMaxYMid:
      case SvgAspectRatioAlign.xMaxYMax:
        offsetX = spareX;
      case SvgAspectRatioAlign.none:
        break;
    }

    switch (align) {
      case SvgAspectRatioAlign.xMinYMin:
      case SvgAspectRatioAlign.xMidYMin:
      case SvgAspectRatioAlign.xMaxYMin:
        offsetY = 0.0;
      case SvgAspectRatioAlign.xMinYMid:
      case SvgAspectRatioAlign.xMidYMid:
      case SvgAspectRatioAlign.xMaxYMid:
        offsetY = spareY * 0.5;
      case SvgAspectRatioAlign.xMinYMax:
      case SvgAspectRatioAlign.xMidYMax:
      case SvgAspectRatioAlign.xMaxYMax:
        offsetY = spareY;
      case SvgAspectRatioAlign.none:
        break;
    }

    SvgMatrixMath.translateInPlace(outMatrix, offsetX, offsetY);
    SvgMatrixMath.scaleInPlace(outMatrix, uniformScale, uniformScale);
    SvgMatrixMath.translateInPlace(outMatrix, -viewBox.left, -viewBox.top);
  }
}
