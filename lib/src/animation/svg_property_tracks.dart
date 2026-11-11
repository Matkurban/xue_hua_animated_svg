import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/svg_gradient.dart';
import '../model/svg_node.dart';
import '../model/svg_style.dart';
import 'svg_animation_timing.dart';

/// Target scalar attribute for `<animate>`.
enum SvgScalarTarget {
  opacity,
  fillOpacity,
  strokeOpacity,
  strokeWidth,
  strokeDashoffset,
  blurSigma,
  x,
  y,
  width,
  height,
  rx,
  ry,
  cx,
  cy,
  r,
  x1,
  y1,
  x2,
  y2,
  fx,
  fy,
  stopOffset,
  stopOpacity,
}

/// Precompiled scalar (`double`) animation track (`<animate>` on numeric attributes).
class SvgScalarAnimationTrack extends SvgAnimationTrack {
  final Object target; // SvgElement, SvgGradientNode, or SvgGradientStop
  final SvgScalarTarget property;
  final Float64List keyframes;

  SvgScalarAnimationTrack({
    required super.timing,
    required this.target,
    required this.property,
    required this.keyframes,
  });

  @override
  void applyAt(int elapsedUs) {
    if (keyframes.isEmpty) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    final double value;
    if (keyframes.length == 1) {
      value = keyframes[0];
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      final v0 = keyframes[seg];
      final v1 = keyframes[seg + 1];
      value = v0 + (v1 - v0) * localT;
    }

    _writeScalarValue(value);
  }

  void _writeScalarValue(double value) {
    final isSum = timing.additiveMode == SvgAdditiveMode.sum;
    final t = target;
    if (t is SvgElement) {
      switch (property) {
        case SvgScalarTarget.opacity:
          t.style.currentOpacity =
              (isSum ? t.style.currentOpacity + value : value).clamp(0.0, 1.0);
        case SvgScalarTarget.fillOpacity:
          t.style.currentFillOpacity =
              (isSum ? t.style.currentFillOpacity + value : value).clamp(
                0.0,
                1.0,
              );
        case SvgScalarTarget.strokeOpacity:
          t.style.currentStrokeOpacity =
              (isSum ? t.style.currentStrokeOpacity + value : value).clamp(
                0.0,
                1.0,
              );
        case SvgScalarTarget.strokeWidth:
          t.style.currentStrokeWidth = math.max(
            0.0,
            isSum ? t.style.currentStrokeWidth + value : value,
          );
        case SvgScalarTarget.strokeDashoffset:
          t.style.currentStrokeDashoffset = isSum
              ? t.style.currentStrokeDashoffset + value
              : value;
        case SvgScalarTarget.blurSigma:
          t.style.currentBlurSigma = math.max(
            0.0,
            isSum ? t.style.currentBlurSigma + value : value,
          );
        case SvgScalarTarget.x:
          if (t is SvgRectNode) {
            t.currentX = isSum ? t.currentX + value : value;
            t.markGeometryDirty();
          } else if (t is SvgUseNode) {
            t.currentX = isSum ? t.currentX + value : value;
          }
        case SvgScalarTarget.y:
          if (t is SvgRectNode) {
            t.currentY = isSum ? t.currentY + value : value;
            t.markGeometryDirty();
          } else if (t is SvgUseNode) {
            t.currentY = isSum ? t.currentY + value : value;
          }
        case SvgScalarTarget.width:
          if (t is SvgRectNode) {
            t.currentWidth = math.max(
              0.0,
              isSum ? t.currentWidth + value : value,
            );
            t.markGeometryDirty();
          }
        case SvgScalarTarget.height:
          if (t is SvgRectNode) {
            t.currentHeight = math.max(
              0.0,
              isSum ? t.currentHeight + value : value,
            );
            t.markGeometryDirty();
          }
        case SvgScalarTarget.rx:
          if (t is SvgRectNode) {
            t.currentRx = math.max(0.0, isSum ? t.currentRx + value : value);
            t.markGeometryDirty();
          } else if (t is SvgEllipseNode) {
            t.currentRx = math.max(0.0, isSum ? t.currentRx + value : value);
            t.markGeometryDirty();
          }
        case SvgScalarTarget.ry:
          if (t is SvgRectNode) {
            t.currentRy = math.max(0.0, isSum ? t.currentRy + value : value);
            t.markGeometryDirty();
          } else if (t is SvgEllipseNode) {
            t.currentRy = math.max(0.0, isSum ? t.currentRy + value : value);
            t.markGeometryDirty();
          }
        case SvgScalarTarget.cx:
          if (t is SvgCircleNode) {
            t.currentCx = isSum ? t.currentCx + value : value;
            t.markGeometryDirty();
          } else if (t is SvgEllipseNode) {
            t.currentCx = isSum ? t.currentCx + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.cy:
          if (t is SvgCircleNode) {
            t.currentCy = isSum ? t.currentCy + value : value;
            t.markGeometryDirty();
          } else if (t is SvgEllipseNode) {
            t.currentCy = isSum ? t.currentCy + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.r:
          if (t is SvgCircleNode) {
            t.currentR = math.max(0.0, isSum ? t.currentR + value : value);
            t.markGeometryDirty();
          }
        case SvgScalarTarget.x1:
          if (t is SvgLineNode) {
            t.currentX1 = isSum ? t.currentX1 + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.y1:
          if (t is SvgLineNode) {
            t.currentY1 = isSum ? t.currentY1 + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.x2:
          if (t is SvgLineNode) {
            t.currentX2 = isSum ? t.currentX2 + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.y2:
          if (t is SvgLineNode) {
            t.currentY2 = isSum ? t.currentY2 + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.fx:
        case SvgScalarTarget.fy:
        case SvgScalarTarget.stopOffset:
        case SvgScalarTarget.stopOpacity:
          break;
      }
    } else if (t is SvgLinearGradientNode) {
      switch (property) {
        case SvgScalarTarget.x1:
          t.currentX1 = isSum ? t.currentX1 + value : value;
        case SvgScalarTarget.y1:
          t.currentY1 = isSum ? t.currentY1 + value : value;
        case SvgScalarTarget.x2:
          t.currentX2 = isSum ? t.currentX2 + value : value;
        case SvgScalarTarget.y2:
          t.currentY2 = isSum ? t.currentY2 + value : value;
        default:
          break;
      }
    } else if (t is SvgRadialGradientNode) {
      switch (property) {
        case SvgScalarTarget.cx:
          t.currentCx = isSum ? t.currentCx + value : value;
        case SvgScalarTarget.cy:
          t.currentCy = isSum ? t.currentCy + value : value;
        case SvgScalarTarget.r:
          t.currentR = math.max(0.0, isSum ? t.currentR + value : value);
        case SvgScalarTarget.fx:
          t.currentFx = isSum ? t.currentFx + value : value;
        case SvgScalarTarget.fy:
          t.currentFy = isSum ? t.currentFy + value : value;
        default:
          break;
      }
    } else if (t is SvgGradientStop) {
      switch (property) {
        case SvgScalarTarget.stopOffset:
          t.currentOffset = (isSum ? t.currentOffset + value : value).clamp(
            0.0,
            1.0,
          );
        case SvgScalarTarget.stopOpacity:
          t.currentOpacity = (isSum ? t.currentOpacity + value : value).clamp(
            0.0,
            1.0,
          );
        default:
          break;
      }
    }
  }
}

/// Target color attribute for `<animate>`.
enum SvgColorTarget { fill, stroke, stopColor }

/// Precompiled color animation track (`fill`, `stroke`, `stop-color`).
class SvgColorAnimationTrack extends SvgAnimationTrack {
  final Object target; // SvgElement or SvgGradientStop
  final SvgColorTarget property;
  final List<ui.Color> keyframes;

  SvgColorAnimationTrack({
    required super.timing,
    required this.target,
    required this.property,
    required this.keyframes,
  });

  @override
  void applyAt(int elapsedUs) {
    if (keyframes.isEmpty) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    final ui.Color color;
    if (keyframes.length == 1) {
      color = keyframes[0];
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      color =
          ui.Color.lerp(keyframes[seg], keyframes[seg + 1], localT) ??
          keyframes[seg];
    }

    final t = target;
    if (t is SvgElement) {
      if (property == SvgColorTarget.fill) {
        t.style.resolvedFill = SvgPaintServer.fromColor(color);
        t.style.currentFillColor = color;
      } else if (property == SvgColorTarget.stroke) {
        t.style.resolvedStroke = SvgPaintServer.fromColor(color);
        t.style.currentStrokeColor = color;
      }
    } else if (t is SvgGradientStop && property == SvgColorTarget.stopColor) {
      t.currentColor = color;
    }
  }
}

/// Precompiled `stroke-dasharray` animation track with pre-normalized equal-length
/// `Float64List` keyframes for zero-allocation in-place interpolation.
class SvgDashArrayAnimationTrack extends SvgAnimationTrack {
  final SvgElement target;
  final List<Float64List> keyframes;
  late final Float64List _interpolatedBuffer;

  SvgDashArrayAnimationTrack({
    required super.timing,
    required this.target,
    required this.keyframes,
  }) : _interpolatedBuffer = Float64List(
         keyframes.isEmpty ? 0 : keyframes[0].length,
       );

  @override
  void applyAt(int elapsedUs) {
    if (keyframes.isEmpty || _interpolatedBuffer.isEmpty) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    if (keyframes.length == 1) {
      final k0 = keyframes[0];
      for (int i = 0; i < _interpolatedBuffer.length; i++) {
        _interpolatedBuffer[i] = k0[i];
      }
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      final k0 = keyframes[seg];
      final k1 = keyframes[seg + 1];
      for (int i = 0; i < _interpolatedBuffer.length; i++) {
        _interpolatedBuffer[i] = k0[i] + (k1[i] - k0[i]) * localT;
      }
    }
    target.style.currentStrokeDasharray = _interpolatedBuffer;
  }
}
