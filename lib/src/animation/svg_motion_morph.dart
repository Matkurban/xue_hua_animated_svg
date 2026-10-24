import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/svg_node.dart';
import '../model/svg_transform.dart';
import 'svg_timeline.dart';

/// Rotation mode for `<animateMotion rotate="...">`.
enum SvgMotionRotateMode {
  /// Fixed rotation angle in degrees (default `0.0`).
  fixedAngle,

  /// Rotates along the path tangent direction (`rotate="auto"`).
  auto,

  /// Rotates along the path tangent direction + 180 degrees (`rotate="auto-reverse"`).
  autoReverse,
}

/// Precompiled `<animateMotion>` track.
///
/// Caches `List<ui.PathMetric>` at initialization (either from an inline `path`
/// attribute, `values`/`from`/`to` coordinates, or an `<mpath>` referencing a
/// `<path>` node in the document) and updates `target.motionMatrix` in-place
/// each frame using `PathMetric.getPosTanForOffset()`.
class SvgMotionAnimationTrack extends SvgAnimationTrack {
  final SvgElement target;
  final SvgMotionRotateMode rotateMode;
  final double fixedAngleDeg;

  /// Optional `keyPoints` remapping (`[0.0 .. 1.0]` distances along the motion path).
  final Float64List? keyPoints;

  final List<ui.PathMetric> _metrics;
  final Float64List _contourStartOffsets;
  final double _totalLength;

  SvgMotionAnimationTrack._({
    required super.timing,
    required this.target,
    required this.rotateMode,
    required this.fixedAngleDeg,
    this.keyPoints,
    required this._metrics,
    required this._contourStartOffsets,
    required this._totalLength,
  });

  /// Creates a precompiled `<animateMotion>` track from a [motionPath] (or
  /// pre-cached [existingMetrics] from an `<mpath>` target node).
  factory SvgMotionAnimationTrack.fromPath({
    required SvgAnimationTiming timing,
    required SvgElement target,
    required ui.Path motionPath,
    List<ui.PathMetric>? existingMetrics,
    SvgMotionRotateMode rotateMode = SvgMotionRotateMode.fixedAngle,
    double fixedAngleDeg = 0.0,
    Float64List? keyPoints,
  }) {
    final metrics =
        existingMetrics ??
        motionPath.computeMetrics(forceClosed: false).toList();
    final starts = Float64List(metrics.length);
    double sum = 0.0;
    for (int i = 0; i < metrics.length; i++) {
      starts[i] = sum;
      sum += metrics[i].length;
    }
    return SvgMotionAnimationTrack._(
      timing: timing,
      target: target,
      rotateMode: rotateMode,
      fixedAngleDeg: fixedAngleDeg,
      keyPoints: keyPoints,
      metrics: metrics,
      contourStartOffsets: starts,
      totalLength: sum,
    );
  }

  @override
  void applyAt(int elapsedUs) {
    if (_metrics.isEmpty || _totalLength <= 0.0) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    double distanceFraction;
    final kp = keyPoints;
    if (kp != null && kp.length >= 2 && timing.keyTimes.length == kp.length) {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      distanceFraction = kp[seg] + (kp[seg + 1] - kp[seg]) * localT;
    } else if (timing.keyTimes.length >= 2) {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      final spanCount = timing.keyTimes.length - 1;
      distanceFraction = (seg + localT) / spanCount;
    } else {
      distanceFraction = progress;
    }

    final targetDist = (distanceFraction.clamp(0.0, 1.0)) * _totalLength;

    // Locate the contour metric containing targetDist
    int metricIdx = _metrics.length - 1;
    for (int i = 0; i < _metrics.length - 1; i++) {
      if (targetDist < _contourStartOffsets[i + 1]) {
        metricIdx = i;
        break;
      }
    }

    final metric = _metrics[metricIdx];
    final localDist = (targetDist - _contourStartOffsets[metricIdx]).clamp(
      0.0,
      metric.length,
    );
    final tangent = metric.getTangentForOffset(localDist);
    if (tangent == null) return;

    final pos = tangent.position;
    final vec = tangent.vector;

    final m = target.motionMatrix;
    if (timing.additiveMode == SvgAdditiveMode.replace) {
      SvgMatrixMath.resetToIdentity(m);
    }

    SvgMatrixMath.translateInPlace(m, pos.dx, pos.dy);

    switch (rotateMode) {
      case SvgMotionRotateMode.fixedAngle:
        if (fixedAngleDeg != 0.0) {
          SvgMatrixMath.rotateAroundAnchorInPlace(m, fixedAngleDeg);
        }
      case SvgMotionRotateMode.auto:
        final angleRad = math.atan2(vec.dy, vec.dx);
        final cosA = math.cos(angleRad);
        final sinA = math.sin(angleRad);
        SvgMatrixMath.multiplyAffine2DInPlace(m, cosA, sinA, -sinA, cosA, 0, 0);
      case SvgMotionRotateMode.autoReverse:
        final angleRad = math.atan2(vec.dy, vec.dx) + math.pi;
        final cosA = math.cos(angleRad);
        final sinA = math.sin(angleRad);
        SvgMatrixMath.multiplyAffine2DInPlace(m, cosA, sinA, -sinA, cosA, 0, 0);
    }
  }
}

/// Precompiled isomorphic Path Morphing (`<animate attributeName="d" />`) track.
///
/// All keyframes are validated at parse time to have identical command sequences
/// (`List<SvgPathCmdType>`) and coordinate buffer lengths (`Float64List`).
/// During `applyAt(elapsedUs)`, control points are linearly or cubic-spline
/// interpolated in-place into `target.morphedCoords` with zero heap allocations.
class SvgPathMorphAnimationTrack extends SvgAnimationTrack {
  final SvgPathNode target;
  final List<Float64List> keyframeCoords;

  SvgPathMorphAnimationTrack({
    required super.timing,
    required this.target,
    required this.keyframeCoords,
  });

  @override
  void applyAt(int elapsedUs) {
    if (keyframeCoords.isEmpty) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    final outCoords = target.morphedCoords;
    final coordLen = outCoords.length;

    if (keyframeCoords.length == 1) {
      final k0 = keyframeCoords[0];
      if (k0.length != coordLen) return;
      for (int i = 0; i < coordLen; i++) {
        outCoords[i] = k0[i];
      }
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      final k0 = keyframeCoords[seg];
      final k1 = keyframeCoords[seg + 1];
      if (k0.length != coordLen || k1.length != coordLen) return;
      for (int i = 0; i < coordLen; i++) {
        outCoords[i] = k0[i] + (k1[i] - k0[i]) * localT;
      }
    }

    target.isMorphed = true;
    target.markGeometryDirty();
  }
}
