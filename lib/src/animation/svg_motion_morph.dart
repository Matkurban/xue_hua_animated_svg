import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/svg_node.dart';
import '../model/svg_transform.dart';
import 'svg_timeline.dart';

/// Rotation mode for `<animateMotion rotate="...">`.
/// `<animateMotion rotate="...">` 的路径朝向旋转模式。
enum SvgMotionRotateMode {
  /// Fixed rotation angle in degrees (default `0.0`).
  /// 固定旋转角度（单位：度，默认 `0.0`）。
  fixedAngle,

  /// Rotates along the path tangent direction (`rotate="auto"`).
  /// 沿路径切线方向自动旋转（`rotate="auto"`）。
  auto,

  /// Rotates along the path tangent direction + 180 degrees (`rotate="auto-reverse"`).
  /// 沿路径切线反方向（加 180°）自动旋转（`rotate="auto-reverse"`）。
  autoReverse,
}

/// Precompiled `<animateMotion>` track.
/// 预编译的 `<animateMotion>` 路径运动动画轨道。
///
/// Caches `List<ui.PathMetric>` at initialization (either from an inline `path`
/// attribute, `values`/`from`/`to` coordinates, or an `<mpath>` referencing a
/// `<path>` node in the document) and updates `target.motionMatrix` in-place
/// each frame using `PathMetric.getTangentForOffset()`.
/// 初始化阶段缓存路径度量列表，每帧原地更新 `target.motionMatrix`。
class SvgMotionAnimationTrack extends SvgAnimationTrack {
  /// Scene element moved along the motion path.
  /// 沿运动路径移动的目标场景元素。
  final SvgElement target;

  /// Rotation mode applied along the path tangent.
  /// 沿路径切线应用的旋转模式。
  final SvgMotionRotateMode rotateMode;

  /// Fixed rotation angle in degrees when [rotateMode] is [SvgMotionRotateMode.fixedAngle].
  /// 当 [rotateMode] 为 [SvgMotionRotateMode.fixedAngle] 时的固定角度（度）。
  final double fixedAngleDeg;

  /// Optional `keyPoints` remapping (`[0.0 .. 1.0]` distances along the motion path).
  /// 可选的 `keyPoints` 路径归一化距离重映射数组（`[0.0 .. 1.0]`）。
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
  /// 从 [motionPath]（或 `<mpath>` 目标节点已缓存的 [existingMetrics]）创建预编译运动轨道。
  ///
  /// - [timing]: Timing and easing evaluator. 时间轴与缓动求值器。
  /// - [target]: Target element to move. 目标运动元素。
  /// - [motionPath]: Path geometry describing the trajectory. 运动轨迹路径。
  /// - [existingMetrics]: Optional precomputed `PathMetric` list to reuse. 可选复用的路径度量缓存。
  /// - [rotateMode]: Tangent rotation mode. 切线旋转模式。
  /// - [fixedAngleDeg]: Fixed angle in degrees when using fixed rotation. 固定旋转角度（度）。
  /// - [keyPoints]: Optional normalized `keyPoints` list. 可选归一化 `keyPoints` 列表。
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

  /// Updates [target]'s motion transform matrix in-place at [elapsedUs].
  /// 在微秒时间点 [elapsedUs] 处原地更新 [target] 的运动变换矩阵。
  ///
  /// - [elapsedUs]: Virtual timeline timestamp in microseconds. 虚拟时间轴微秒时间戳。
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
/// 预编译的同构路径形变（`<animate attributeName="d" />`）动画轨道。
///
/// All keyframes are validated at parse time to have identical command sequences
/// and coordinate buffer lengths. During [applyAt], control points are interpolated
/// in-place into `target.morphedCoords` with zero heap allocations.
/// 所有关键帧在解析期已校验同构，运行期零分配原地插值控制点。
class SvgPathMorphAnimationTrack extends SvgAnimationTrack {
  /// Target `<path>` node whose geometry coordinates are morphed.
  /// 被执行路径形变的目标 `<path>` 节点。
  final SvgPathNode target;

  /// Precompiled flattened coordinate arrays for each isomorphic keyframe.
  /// 每个同构关键帧对应的扁平坐标数组列表。
  final List<Float64List> keyframeCoords;

  /// Creates an [SvgPathMorphAnimationTrack].
  /// 创建一个 [SvgPathMorphAnimationTrack] 路径形变轨道。
  ///
  /// - [timing]: Timing and easing evaluator. 时间轴与缓动求值器。
  /// - [target]: Target `<path>` node. 目标路径节点。
  /// - [keyframeCoords]: Equal-length coordinate buffers for each keyframe. 各关键帧等长坐标缓冲。
  SvgPathMorphAnimationTrack({
    required super.timing,
    required this.target,
    required this.keyframeCoords,
  });

  /// Interpolates [keyframeCoords] into [target]'s morphed coordinate buffer at [elapsedUs].
  /// 在微秒时间点 [elapsedUs] 处插值 [keyframeCoords] 并写入 [target] 的形变坐标缓冲区。
  ///
  /// - [elapsedUs]: Virtual timeline timestamp in microseconds. 虚拟时间轴微秒时间戳。
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
