import 'dart:typed_data';

import 'package:flutter/animation.dart' show Cubic;
import 'package:flutter/foundation.dart' show protected;

import 'svg_step_easing.dart';

/// SMIL / CSS `fill` behavior when an animation is outside its active duration.
/// SMIL / CSS 动画处于活跃区间之外时的 `fill` 填充保持策略。
enum SvgAnimationFillMode {
  /// Resets the target attribute to its base value after the active duration ends.
  /// 动画结束后恢复为元素的基础属性值（`remove` / `none`）。
  remove,

  /// Freezes the target attribute at its final active value after the active duration ends.
  /// 动画结束后保持在最后一帧的值（`freeze` / `forwards`）。
  freeze,

  /// Applies the first keyframe before `begin` (`backwards` in CSS).
  /// 在 `begin` 开始前提前应用首帧值（CSS `backwards`）。
  backwards,

  /// Applies both backwards before `begin` and freeze after `end` (`both` in CSS).
  /// 同时在开始前应用首帧并在结束后保持末帧（CSS `both`）。
  both,
}

/// SMIL `calcMode` interpolation mode.
/// SMIL `calcMode` 插值计算模式。
enum SvgCalcMode {
  /// Linear interpolation between adjacent keyframes (`linear`).
  /// 相邻关键帧之间线性插值（`linear`）。
  linear,

  /// Cubic-bezier spline interpolation using `keySplines` (`spline`).
  /// 使用 `keySplines` 三次贝塞尔曲线插值（`spline`）。
  spline,

  /// Jumps directly between keyframe values without interpolation (`discrete`).
  /// 关键帧之间离散跳变，不做平滑插值（`discrete`）。
  discrete,

  /// Constant-velocity interpolation proportional to value distance (`paced`).
  /// 按数值距离等速插值（`paced`）。
  paced,
}

/// SMIL / CSS `additive` composition mode.
/// SMIL / CSS 动画的 `additive` 叠加合成模式。
enum SvgAdditiveMode {
  /// Replaces the underlying base or prior animated value (`replace`).
  /// 覆盖底层基础值或前置动画值（`replace`）。
  replace,

  /// Adds/composes onto the underlying base or prior animated value (`sum`).
  /// 叠加/复合到底层基础值或前置动画值之上（`sum`）。
  sum,
}

/// CSS `animation-direction` playback direction mode.
/// CSS `animation-direction` 播放方向模式。
enum SvgAnimationDirection {
  /// Plays forward from `0%` to `100%` on every cycle (`normal`).
  /// 每周期从 `0%` 正向播放至 `100%`（`normal`）。
  normal,

  /// Plays backward from `100%` to `0%` on every cycle (`reverse`).
  /// 每周期从 `100%` 反向播放至 `0%`（`reverse`）。
  reverse,

  /// Alternates forward on even cycles and backward on odd cycles (`alternate`).
  /// 偶数周期正向、奇数周期反向交替播放（`alternate`）。
  alternate,

  /// Alternates backward on even cycles and forward on odd cycles (`alternate-reverse`).
  /// 偶数周期反向、奇数周期正向交替播放（`alternate-reverse`）。
  alternateReverse,
}

/// Precompiled timing and easing evaluator for a single SMIL or CSS animation track.
/// 单个 SMIL 或 CSS 动画轨道的预编译时间轴与缓动求值器。
///
/// Uses Flutter's built-in [Cubic] solver for `keySplines` cubic-bezier curves
/// and [SvgStepEasing] for W3C CSS `steps(N, <position>)` curves.
/// 使用 Flutter 内置 [Cubic] 求解 `keySplines` 三次贝塞尔曲线，
/// 并使用 [SvgStepEasing] 求解 W3C CSS `steps(N, <position>)` 阶梯曲线。
class SvgAnimationTiming {
  /// Start offsets in microseconds (supports multiple semicolon-separated `begin` times).
  /// 微秒级起始偏移列表（支持分号分隔的多组 `begin` 时刻及 Syncbase 解析结果）。
  ///
  /// Mutable so SMIL syncbase timing resolution can append resolved offsets
  /// during compilation. Stored as [List<int>] rather than `Int64List` because
  /// dart2js / Flutter Web does not support `Int64List`.
  /// 保持可变以供编译期 SMIL Syncbase 同步解析写入；采用 `List<int>` 兼容 Flutter Web。
  final List<int> beginOffsetsUs;

  /// Simple duration of one cycle in microseconds.
  /// 单个动画周期的微秒时长。
  final int durationUs;

  /// Optional explicit end time in microseconds (`null` if unbounded or controlled by [repeatCount]).
  /// 可选的显式结束时间戳（微秒）；未指定时为 `null`。
  final int? endUs;

  /// Number of iterations (`double.infinity` for `indefinite` / `infinite`).
  /// 重复次数（`indefinite` / `infinite` 对应 `double.infinity`）。
  final double repeatCount;

  /// Fill behavior outside the active duration.
  /// 活跃区间外的填充保持模式。
  final SvgAnimationFillMode fillMode;

  /// Interpolation mode between keyframes.
  /// 关键帧之间的插值模式。
  final SvgCalcMode calcMode;

  /// Additive composition mode (`replace` or `sum`).
  /// 叠加合成模式（覆盖或累加）。
  final SvgAdditiveMode additiveMode;

  /// Playback direction across iterations.
  /// 各重复周期的播放方向。
  final SvgAnimationDirection direction;

  /// SMIL `accumulate="sum"` flag: adds `cycleIndex * lastKeyframe` across repeats.
  /// SMIL `accumulate="sum"` 标志：跨重复周期累加 `cycleIndex * lastKeyframe`。
  final bool accumulateSum;

  /// CSS `animation-play-state: paused` flag: freezes evaluation at `t = 0`.
  /// CSS `animation-play-state: paused` 标志：将时间轴冻结在 `t = 0`。
  final bool isPaused;

  /// Normalized keyframe timestamps `[0.0 .. 1.0]` of length `keyframeCount`.
  /// 归一化关键帧时间点数组（`[0.0 .. 1.0]`），长度等于关键帧数量。
  final Float64List keyTimes;

  /// Precompiled [Cubic] easing curves of length `keyframeCount - 1` when `calcMode == spline`.
  /// `calcMode == spline` 时每段关键帧对应的预编译 [Cubic] 缓动曲线列表。
  final List<Cubic>? keySplines;

  /// Optional per-segment CSS `steps(...)` easing curves.
  /// 可选的逐段 CSS `steps(...)` 阶梯缓动列表。
  final List<SvgStepEasing?>? keyStepEasings;

  /// Optional uniform CSS `steps(...)` easing curve applied to each segment.
  /// 可选的全局统一 CSS `steps(...)` 阶梯缓动曲线。
  final SvgStepEasing? stepEasing;

  /// Creates an [SvgAnimationTiming] evaluator.
  /// 创建一个 [SvgAnimationTiming] 时间轴求值器。
  ///
  /// - [beginOffsetsUs]: Start time offsets in microseconds. 微秒起始偏移列表。
  /// - [durationUs]: Single-cycle duration in microseconds. 单周期微秒时长。
  /// - [endUs]: Optional explicit end timestamp in microseconds. 可选显式结束微秒时间。
  /// - [repeatCount]: Iteration count (`double.infinity` for infinite). 重复次数。
  /// - [fillMode]: Fill behavior outside active range. 填充保持模式。
  /// - [calcMode]: Interpolation mode. 插值计算模式。
  /// - [additiveMode]: Additive composition mode. 叠加合成模式。
  /// - [direction]: Playback direction mode. 播放方向模式。
  /// - [accumulateSum]: Whether SMIL `accumulate="sum"` is enabled. 是否启用跨周期累加。
  /// - [isPaused]: Whether CSS `animation-play-state: paused` is active. 是否处于暂停状态。
  /// - [keyTimes]: Normalized keyframe timestamps in `[0.0 .. 1.0]`. 归一化关键帧时间点。
  /// - [keySplines]: Optional cubic-bezier segment curves. 可选贝塞尔缓动列表。
  /// - [keyStepEasings]: Optional per-segment step easings. 可选逐段阶梯缓动列表。
  /// - [stepEasing]: Optional uniform step easing. 可选统一阶梯缓动。
  const SvgAnimationTiming({
    required this.beginOffsetsUs,
    required this.durationUs,
    this.endUs,
    this.repeatCount = 1.0,
    this.fillMode = SvgAnimationFillMode.remove,
    this.calcMode = SvgCalcMode.linear,
    this.additiveMode = SvgAdditiveMode.replace,
    this.direction = SvgAnimationDirection.normal,
    this.accumulateSum = false,
    this.isPaused = false,
    required this.keyTimes,
    this.keySplines,
    this.keyStepEasings,
    this.stepEasing,
  });

  /// Evaluates the normalized progress `t` in `[0.0, 1.0]` for [elapsedUs], or
  /// returns `-1.0` if this animation is currently inactive.
  /// 计算 [elapsedUs] 时刻对应的归一化周期进度 `t`（`[0.0, 1.0]`）；若未激活则返回 `-1.0`。
  ///
  /// - [elapsedUs]: Current virtual timeline position in microseconds. 当前虚拟时间轴微秒位置。
  double evaluateSimpleProgress(int elapsedUs) {
    if (durationUs <= 0 || beginOffsetsUs.isEmpty) return -1.0;
    final effectiveElapsedUs = isPaused ? 0 : elapsedUs;

    // Find the most recent active begin offset <= effectiveElapsedUs
    int? activeBeginUs;
    int? earliestBeginUs;
    for (int i = 0; i < beginOffsetsUs.length; i++) {
      final b = beginOffsetsUs[i];
      if (earliestBeginUs == null || b < earliestBeginUs) {
        earliestBeginUs = b;
      }
      if (b <= effectiveElapsedUs) {
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

    final localElapsedUs = effectiveElapsedUs - activeBeginUs;
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

  /// Evaluates the completed repeat iteration index (`>= 0`) at [elapsedUs]
  /// for SMIL `accumulate="sum"`, or returns `-1` if inactive.
  /// 计算 [elapsedUs] 时刻已完成的重复周期索引（供 SMIL `accumulate="sum"` 使用）；未激活时返回 `-1`。
  ///
  /// - [elapsedUs]: Current virtual timeline position in microseconds. 当前虚拟时间轴微秒位置。
  int evaluateCycleIndex(int elapsedUs) {
    if (durationUs <= 0 || beginOffsetsUs.isEmpty) return -1;
    final effectiveElapsedUs = isPaused ? 0 : elapsedUs;

    int? activeBeginUs;
    for (int i = 0; i < beginOffsetsUs.length; i++) {
      final b = beginOffsetsUs[i];
      if (b <= effectiveElapsedUs) {
        if (activeBeginUs == null || b > activeBeginUs) {
          activeBeginUs = b;
        }
      }
    }
    if (activeBeginUs == null) return 0;

    final localElapsedUs = effectiveElapsedUs - activeBeginUs;
    final maxActiveUs = repeatCount.isInfinite
        ? null
        : (durationUs * repeatCount).round();

    int? effectiveActiveLimitUs = maxActiveUs;
    if (endUs != null) {
      final endRelativeUs = endUs! - activeBeginUs;
      if (endRelativeUs <= 0) return -1;
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
          return exactFloor - 1;
        }
        return exactFloor;
      }
      return -1;
    }

    return localElapsedUs ~/ durationUs;
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
  /// 根据归一化进度 [t]（`[0.0, 1.0]`）解析当前所在关键帧区间索引及段内缓动进度。
  ///
  /// Writes `segmentIndex` to `outSegment[0]` and returns `localT` in `[0.0, 1.0]`.
  /// 将区间索引写入 `outSegment[0]`，并返回段内缓动后的进度 `localT`。
  ///
  /// - [t]: Simple cycle progress in `[0.0, 1.0]`. 归一化周期进度。
  /// - [outSegment]: Pre-allocated single-element buffer receiving the segment index.
  ///   预分配的单元素缓冲区，用于接收区间索引。
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
      final segStep = (keyStepEasings != null && keyStepEasings!.isNotEmpty)
          ? keyStepEasings![0]
          : stepEasing;
      return segStep != null ? segStep.transform(0.0) : 0.0;
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
    final segStep = (keyStepEasings != null && seg < keyStepEasings!.length)
        ? keyStepEasings![seg]
        : stepEasing;
    if (segStep != null) {
      return segStep.transform(linearLocalT);
    }
    if (calcMode == SvgCalcMode.spline &&
        keySplines != null &&
        seg < keySplines!.length) {
      final cubic = keySplines![seg];
      if (cubic.a == 0.0 &&
          cubic.b == 0.0 &&
          cubic.c == 1.0 &&
          cubic.d == 1.0) {
        return linearLocalT;
      }
      return cubic.transform(linearLocalT).clamp(0.0, 1.0);
    }
    return linearLocalT;
  }
}

/// Base class for all precompiled animation tracks evaluated by `SvgTimelineEngine`.
/// 所有由 `SvgTimelineEngine` 求值的预编译动画轨道抽象基类。
abstract class SvgAnimationTrack {
  /// Timing and easing configuration governing when and how this track plays.
  /// 控制该轨道播放时机与缓动曲线的时间轴配置。
  final SvgAnimationTiming timing;

  /// Pre-allocated single-element buffer for segment index lookup.
  /// 预分配的单元素缓冲区，用于零分配关键帧区间索引查询。
  ///
  /// [SvgAnimationTiming.resolveSegment] writes the active keyframe index to
  /// element `0`. Every track reuses this buffer so segment resolution stays
  /// allocation-free.
  /// [SvgAnimationTiming.resolveSegment] 会将活跃关键帧索引写入下标 `0`。
  @protected
  final Int32List segBuffer = Int32List(1);

  /// Creates an [SvgAnimationTrack] bound to [timing].
  /// 创建一个绑定到 [timing] 的动画轨道基类实例。
  ///
  /// - [timing]: Precompiled timing evaluator for this track. 该轨道的预编译时间求值器。
  SvgAnimationTrack({required this.timing});

  /// Applies this animation at [elapsedUs] in-place.
  /// 在微秒时间点 [elapsedUs] 处原地应用本动画轨道。
  ///
  /// - [elapsedUs]: Virtual timeline timestamp in microseconds. 虚拟时间轴微秒时间戳。
  void applyAt(int elapsedUs);
}
