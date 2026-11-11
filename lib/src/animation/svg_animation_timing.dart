import 'dart:typed_data';

import 'package:flutter/animation.dart' show Cubic;
import 'package:flutter/foundation.dart' show protected;

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
  ///
  /// Stored as [List<int>] rather than [Int64List] because dart2js / Flutter Web
  /// does not support `Int64List`.
  final List<int> beginOffsetsUs;

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

/// Base class for all precompiled animation tracks evaluated by `SvgTimelineEngine`.
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
