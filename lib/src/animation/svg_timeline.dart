import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Cubic;
import 'package:flutter/foundation.dart' show protected;

import '../model/svg_gradient.dart';
import '../model/svg_node.dart';
import '../model/svg_style.dart';
import '../model/svg_transform.dart';

/// SMIL / CSS `fill` behavior when an animation is outside its active duration.
enum SvgAnimationFillMode {
  /// Resets the target attribute to its base value after the active duration ends.
  remove,

  /// Freezes the target attribute at its final active value after the active duration ends.
  freeze,

  /// Applies the first keyframe before `begin` (`backwards` or `both` in CSS).
  backwards,

  /// Applies both backwards before `begin` and freeze after `end` (`both` in CSS).
  both,
}

/// SMIL `calcMode` interpolation mode.
enum SvgCalcMode { linear, spline, discrete, paced }

/// SMIL / CSS `additive` composition mode.
enum SvgAdditiveMode { replace, sum }

/// CSS `animation-direction` mode.
enum SvgAnimationDirection { normal, reverse, alternate, alternateReverse }

/// Precompiled timing and easing evaluator for a single SMIL or CSS animation track.
///
/// Uses Flutter's built-in [Cubic] solver for `keySplines` cubic-bezier curves.
class SvgAnimationTiming {
  /// Start offsets in microseconds (supports multiple semicolon-separated `begin` times).
  final Int64List beginOffsetsUs;

  /// Simple duration of one cycle in microseconds.
  final int durationUs;

  /// Optional explicit end time in microseconds (`null` if unbounded or controlled by `repeatCount`).
  final int? endUs;

  /// Number of iterations (`double.infinity` for `indefinite` / `infinite`).
  final double repeatCount;

  final SvgAnimationFillMode fillMode;
  final SvgCalcMode calcMode;
  final SvgAdditiveMode additiveMode;
  final SvgAnimationDirection direction;

  /// Normalized keyframe timestamps `[0.0 .. 1.0]` of length `keyframeCount`.
  final Float64List keyTimes;

  /// Precompiled [Cubic] easing curves of length `keyframeCount - 1` when `calcMode == spline`.
  final List<Cubic>? keySplines;

  const SvgAnimationTiming({
    required this.beginOffsetsUs,
    required this.durationUs,
    this.endUs,
    this.repeatCount = 1.0,
    this.fillMode = SvgAnimationFillMode.remove,
    this.calcMode = SvgCalcMode.linear,
    this.additiveMode = SvgAdditiveMode.replace,
    this.direction = SvgAnimationDirection.normal,
    required this.keyTimes,
    this.keySplines,
  });

  /// Evaluates the normalized progress `t` in `[0.0, 1.0]` for [elapsedUs], or
  /// returns `-1.0` if this animation is currently inactive.
  double evaluateSimpleProgress(int elapsedUs) {
    if (durationUs <= 0) return -1.0;

    // Find the most recent active begin offset <= elapsedUs (or earliest future offset for backwards fill)
    int? activeBeginUs;
    int? earliestBeginUs;
    for (int i = 0; i < beginOffsetsUs.length; i++) {
      final b = beginOffsetsUs[i];
      if (earliestBeginUs == null || b < earliestBeginUs) {
        earliestBeginUs = b;
      }
      if (b <= elapsedUs) {
        if (activeBeginUs == null || b > activeBeginUs) {
          activeBeginUs = b;
        }
      }
    }

    if (activeBeginUs == null) {
      if (earliestBeginUs != null &&
          (fillMode == SvgAnimationFillMode.backwards ||
              fillMode == SvgAnimationFillMode.both)) {
        return _applyDirection(0.0, 0);
      }
      return -1.0;
    }

    int localElapsedUs = elapsedUs - activeBeginUs;
    final maxActiveUs = repeatCount.isInfinite
        ? null
        : (durationUs * repeatCount).round();

    int? effectiveActiveLimitUs = maxActiveUs;
    if (endUs != null) {
      final endRelativeUs = endUs! - activeBeginUs;
      if (endRelativeUs <= 0) return -1.0;
      if (effectiveActiveLimitUs == null ||
          endRelativeUs < effectiveActiveLimitUs) {
        effectiveActiveLimitUs = endRelativeUs;
      }
    }

    if (effectiveActiveLimitUs != null &&
        localElapsedUs >= effectiveActiveLimitUs) {
      if (fillMode == SvgAnimationFillMode.freeze ||
          fillMode == SvgAnimationFillMode.both) {
        final totalCycles = effectiveActiveLimitUs / durationUs;
        final exactFloor = totalCycles.floor();
        final remainder = totalCycles - exactFloor;
        if (remainder <= 1e-6 && exactFloor > 0) {
          return _applyDirection(1.0, exactFloor - 1);
        }
        return _applyDirection(remainder.clamp(0.0, 1.0), exactFloor);
      }
      return -1.0;
    }

    final cycleIndex = localElapsedUs ~/ durationUs;
    final cycleRemUs = localElapsedUs % durationUs;
    final rawProgress = (cycleRemUs / durationUs).clamp(0.0, 1.0);
    return _applyDirection(rawProgress, cycleIndex);
  }

  double _applyDirection(double rawProgress, int cycleIndex) {
    switch (direction) {
      case SvgAnimationDirection.normal:
        return rawProgress;
      case SvgAnimationDirection.reverse:
        return 1.0 - rawProgress;
      case SvgAnimationDirection.alternate:
        return cycleIndex.isEven ? rawProgress : (1.0 - rawProgress);
      case SvgAnimationDirection.alternateReverse:
        return cycleIndex.isEven ? (1.0 - rawProgress) : rawProgress;
    }
  }

  /// Resolves the active keyframe segment index and segment-local eased progress
  /// for simple progress [t] in `[0.0, 1.0]`.
  ///
  /// Writes `segmentIndex` to `outSegment[0]` and returns `localT` in `[0.0, 1.0]`.
  double resolveSegment(double t, Int32List outSegment) {
    final count = keyTimes.length;
    if (count <= 1) {
      outSegment[0] = 0;
      return 0.0;
    }

    if (calcMode == SvgCalcMode.discrete) {
      int idx = 0;
      for (int i = 0; i < count; i++) {
        if (t >= keyTimes[i]) {
          idx = i;
        } else {
          break;
        }
      }
      if (idx >= count - 1) {
        outSegment[0] = count - 2;
        return 1.0;
      }
      outSegment[0] = idx;
      return 0.0;
    }

    if (t <= keyTimes[0]) {
      outSegment[0] = 0;
      return 0.0;
    }
    if (t >= keyTimes[count - 1]) {
      outSegment[0] = count - 2;
      return 1.0;
    }

    int seg = 0;
    for (int i = 0; i < count - 1; i++) {
      if (t >= keyTimes[i] && t <= keyTimes[i + 1]) {
        seg = i;
        break;
      }
    }

    outSegment[0] = seg;
    final t0 = keyTimes[seg];
    final t1 = keyTimes[seg + 1];
    final span = t1 - t0;
    if (span <= 1e-9) return 1.0;

    final linearLocalT = ((t - t0) / span).clamp(0.0, 1.0);
    if (calcMode == SvgCalcMode.spline &&
        keySplines != null &&
        seg < keySplines!.length) {
      return keySplines![seg].transform(linearLocalT).clamp(0.0, 1.0);
    }
    return linearLocalT;
  }
}

/// Base class for all precompiled animation tracks evaluated by [SvgTimelineEngine].
abstract class SvgAnimationTrack {
  final SvgAnimationTiming timing;

  /// Pre-allocated single-element buffer for segment index lookup.
  ///
  /// [SvgAnimationTiming.resolveSegment] writes the active keyframe index to
  /// element `0`. Every track, including motion and path-morph tracks defined
  /// in other libraries, reuses this buffer so segment resolution stays
  /// allocation-free.
  @protected
  final Int32List segBuffer = Int32List(1);

  SvgAnimationTrack({required this.timing});

  /// Applies this animation at [elapsedUs] in-place.
  void applyAt(int elapsedUs);
}

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

/// Precompiled `<animateTransform>` or CSS `@keyframes transform` track.
///
/// Mutates `target.transformMatrix` (or `gradient.currentGradientMatrix`) in-place
/// without allocating temporary `Matrix4` objects.
class SvgTransformAnimationTrack extends SvgAnimationTrack {
  final SvgElement? targetElement;
  final SvgGradientNode? targetGradient;
  final SvgTransformType transformType;
  final ui.Rect documentViewBox;

  /// Flattened keyframe parameter array (`stride = 3` per keyframe: `[v0, v1, v2]`).
  /// - `translate`: `[tx, ty, 0]`
  /// - `scale`: `[sx, sy, 0]`
  /// - `rotate`: `[angleDeg, cx, cy]`
  /// - `skewX` / `skewY` / `rotateX` / `rotateY` / `rotateZ` / `perspective`: `[val, 0, 0]`
  final Float64List keyframeValues;

  /// Whether `(cx, cy)` in `rotate(angle, cx, cy)` was explicitly provided.
  final bool hasExplicitRotateAnchor;

  SvgTransformAnimationTrack({
    required super.timing,
    this.targetElement,
    this.targetGradient,
    required this.transformType,
    required this.keyframeValues,
    required this.documentViewBox,
    this.hasExplicitRotateAnchor = false,
  });

  @override
  void applyAt(int elapsedUs) {
    final keyframeCount = keyframeValues.length ~/ 3;
    if (keyframeCount == 0) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    double v0, v1, v2;
    if (keyframeCount == 1) {
      v0 = keyframeValues[0];
      v1 = keyframeValues[1];
      v2 = keyframeValues[2];
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      final i0 = seg * 3;
      final i1 = (seg + 1) * 3;
      v0 =
          keyframeValues[i0] +
          (keyframeValues[i1] - keyframeValues[i0]) * localT;
      v1 =
          keyframeValues[i0 + 1] +
          (keyframeValues[i1 + 1] - keyframeValues[i0 + 1]) * localT;
      v2 =
          keyframeValues[i0 + 2] +
          (keyframeValues[i1 + 2] - keyframeValues[i0 + 2]) * localT;
    }

    final Float64List matrix;
    double originX = 0.0;
    double originY = 0.0;

    if (targetElement != null) {
      final elem = targetElement!;
      matrix = elem.transformMatrix;
      if (timing.additiveMode == SvgAdditiveMode.replace) {
        SvgMatrixMath.resetToIdentity(matrix);
      }
      final origin = elem.style.currentTransformOrigin;
      originX = origin.resolveX(elem.cachedBounds, documentViewBox);
      originY = origin.resolveY(elem.cachedBounds, documentViewBox);
    } else if (targetGradient != null) {
      final grad = targetGradient!;
      matrix = grad.currentGradientMatrix;
      if (timing.additiveMode == SvgAdditiveMode.replace) {
        SvgMatrixMath.resetToIdentity(matrix);
      }
    } else {
      return;
    }

    final useOrigin =
        (originX != 0.0 || originY != 0.0) &&
        !(transformType == SvgTransformType.rotate && hasExplicitRotateAnchor);

    if (useOrigin) {
      SvgMatrixMath.translateInPlace(matrix, originX, originY);
    }

    switch (transformType) {
      case SvgTransformType.translate:
        SvgMatrixMath.translateInPlace(matrix, v0, v1);
      case SvgTransformType.scale:
        SvgMatrixMath.scaleInPlace(matrix, v0, v1);
      case SvgTransformType.rotate:
        SvgMatrixMath.rotateAroundAnchorInPlace(matrix, v0, v1, v2);
      case SvgTransformType.skewX:
        SvgMatrixMath.skewXInPlace(matrix, v0);
      case SvgTransformType.skewY:
        SvgMatrixMath.skewYInPlace(matrix, v0);
      case SvgTransformType.rotateX:
        SvgMatrixMath.rotateXInPlace(matrix, v0);
      case SvgTransformType.rotateY:
        SvgMatrixMath.rotateYInPlace(matrix, v0);
      case SvgTransformType.rotateZ:
        SvgMatrixMath.rotateAroundAnchorInPlace(matrix, v0, 0.0, 0.0);
      case SvgTransformType.perspective:
        SvgMatrixMath.perspectiveInPlace(matrix, v0);
      case SvgTransformType.matrix:
        break;
    }

    if (useOrigin) {
      SvgMatrixMath.translateInPlace(matrix, -originX, -originY);
    }
  }
}

/// Precompiled multi-operation CSS `@keyframes` transform track where each keyframe
/// contains a sequence of [SvgTransformOp] instructions (e.g., `perspective(400px) rotateY(180deg) scale(1.1)`).
class SvgCssMultiTransformTrack extends SvgAnimationTrack {
  final SvgElement target;
  final List<List<SvgTransformOp>> keyframeOps;
  final ui.Rect documentViewBox;

  SvgCssMultiTransformTrack({
    required super.timing,
    required this.target,
    required this.keyframeOps,
    required this.documentViewBox,
  });

  @override
  void applyAt(int elapsedUs) {
    if (keyframeOps.isEmpty) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    final matrix = target.transformMatrix;
    if (timing.additiveMode == SvgAdditiveMode.replace) {
      SvgMatrixMath.resetToIdentity(matrix);
    }

    final origin = target.style.currentTransformOrigin;
    final ox = origin.resolveX(target.cachedBounds, documentViewBox);
    final oy = origin.resolveY(target.cachedBounds, documentViewBox);
    final hasOrigin = ox != 0.0 || oy != 0.0;

    if (hasOrigin) {
      SvgMatrixMath.translateInPlace(matrix, ox, oy);
    }

    if (keyframeOps.length == 1) {
      final ops = keyframeOps[0];
      for (int i = 0; i < ops.length; i++) {
        SvgMatrixMath.applyOpInPlace(matrix, ops[i]);
      }
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      final opsA = keyframeOps[seg];
      final opsB = keyframeOps[seg + 1];
      final maxLen = math.max(opsA.length, opsB.length);

      for (int i = 0; i < maxLen; i++) {
        final opA = i < opsA.length ? opsA[i] : null;
        final opB = i < opsB.length ? opsB[i] : null;
        final type = (opA ?? opB)!.type;
        if (opA != null && opB != null && opA.type == opB.type) {
          _applyInterpolatedOp(matrix, type, opA.values, opB.values, localT);
        } else if (opA != null && opB == null) {
          final identityVals = _identityValuesFor(opA.type);
          _applyInterpolatedOp(
            matrix,
            opA.type,
            opA.values,
            identityVals,
            localT,
          );
        } else if (opA == null && opB != null) {
          final identityVals = _identityValuesFor(opB.type);
          _applyInterpolatedOp(
            matrix,
            opB.type,
            identityVals,
            opB.values,
            localT,
          );
        } else if (opA != null) {
          SvgMatrixMath.applyOpInPlace(matrix, localT < 0.5 ? opA : opB!);
        }
      }
    }

    if (hasOrigin) {
      SvgMatrixMath.translateInPlace(matrix, -ox, -oy);
    }
  }

  static final Float64List _zero3 = Float64List(3);
  static final Float64List _one2 = Float64List.fromList([1.0, 1.0]);
  static final Float64List _idMatrix6 = Float64List.fromList([
    1.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
  ]);

  static Float64List _identityValuesFor(SvgTransformType type) {
    switch (type) {
      case SvgTransformType.scale:
        return _one2;
      case SvgTransformType.matrix:
        return _idMatrix6;
      default:
        return _zero3;
    }
  }

  static void _applyInterpolatedOp(
    Float64List m,
    SvgTransformType type,
    Float64List a,
    Float64List b,
    double t,
  ) {
    double lerpAt(int idx, double fallback) {
      final va = idx < a.length ? a[idx] : fallback;
      final vb = idx < b.length ? b[idx] : fallback;
      return va + (vb - va) * t;
    }

    switch (type) {
      case SvgTransformType.translate:
        SvgMatrixMath.translateInPlace(m, lerpAt(0, 0.0), lerpAt(1, 0.0));
      case SvgTransformType.scale:
        SvgMatrixMath.scaleInPlace(m, lerpAt(0, 1.0), lerpAt(1, 1.0));
      case SvgTransformType.rotate:
        SvgMatrixMath.rotateAroundAnchorInPlace(
          m,
          lerpAt(0, 0.0),
          lerpAt(1, 0.0),
          lerpAt(2, 0.0),
        );
      case SvgTransformType.skewX:
        SvgMatrixMath.skewXInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.skewY:
        SvgMatrixMath.skewYInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.rotateX:
        SvgMatrixMath.rotateXInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.rotateY:
        SvgMatrixMath.rotateYInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.rotateZ:
        SvgMatrixMath.rotateAroundAnchorInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.perspective:
        SvgMatrixMath.perspectiveInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.matrix:
        SvgMatrixMath.multiplyAffine2DInPlace(
          m,
          lerpAt(0, 1.0),
          lerpAt(1, 0.0),
          lerpAt(2, 0.0),
          lerpAt(3, 1.0),
          lerpAt(4, 0.0),
          lerpAt(5, 0.0),
        );
    }
  }
}

/// High-performance precompiled Timeline Engine driving all SMIL and CSS animations
/// in an [SvgDocument] with zero heap allocations per frame.
class SvgTimelineEngine {
  final List<SvgElement> animatedElements;
  final List<SvgGradientNode> animatedGradients;
  final List<SvgAnimationTrack> tracks;

  /// Finite duration of the timeline, or `null` if any track repeats indefinitely.
  final Duration? finiteDuration;

  /// Representative cycle duration used for UI progress bars / looping controllers.
  final Duration cycleDuration;

  SvgTimelineEngine({
    required this.animatedElements,
    required this.animatedGradients,
    required this.tracks,
    required this.finiteDuration,
    required this.cycleDuration,
  });

  bool get hasAnimations => tracks.isNotEmpty;

  /// Evaluates all animation tracks at [elapsed] in-place.
  void seekMicroseconds(int elapsedUs) {
    if (tracks.isEmpty) return;

    // 1. Reset animated elements and gradients to their precompiled base states
    for (int i = 0; i < animatedElements.length; i++) {
      animatedElements[i].resetFrameState();
    }
    for (int i = 0; i < animatedGradients.length; i++) {
      animatedGradients[i].resetToBase();
    }

    // 2. Apply all active animation tracks in document order (supporting additive="sum")
    for (int i = 0; i < tracks.length; i++) {
      tracks[i].applyAt(elapsedUs);
    }
  }
}
