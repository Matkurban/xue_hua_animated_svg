import 'package:flutter/animation.dart' show Cubic;

import '../animation/svg_timeline.dart';
import 'svg_css_selector.dart';

export 'svg_css_selector.dart';
export 'svg_css_variables.dart';

/// Precompiled CSS animation binding parsed from `animation` or `animation-*` properties.
/// 从 CSS `animation` 简写或 `animation-*` 长写属性解析得到的预编译动画配置。
class SvgCssAnimationConfig {
  /// Referenced `@keyframes` rule name.
  /// 引用的 `@keyframes` 关键帧规则名称。
  String name;

  /// Single-cycle duration in microseconds (`animation-duration`).
  /// 单周期时长，单位微秒（`animation-duration`）。
  int durationUs;

  /// Signed start delay in microseconds (`animation-delay`, supports negative values).
  /// 带符号起始延迟，单位微秒（`animation-delay`，支持负值中途起播）。
  int delayUs;

  /// Iteration count (`double.infinity` for `infinite`).
  /// 迭代次数（`infinite` 对应 `double.infinity`）。
  double iterationCount;

  /// Playback direction across iterations (`animation-direction`).
  /// 迭代播放方向（`animation-direction`）。
  SvgAnimationDirection direction;

  /// Fill behavior before start and after end (`animation-fill-mode`).
  /// 起止区间外的填充保持策略（`animation-fill-mode`）。
  SvgAnimationFillMode fillMode;

  /// Optional cubic-bezier timing curve (`animation-timing-function`).
  /// 可选的三次贝塞尔缓动曲线（`animation-timing-function`）。
  Cubic? timingCurve;

  /// Optional CSS `steps(...)` / `step-start` / `step-end` easing curve.
  /// 可选的 CSS `steps(...)` / `step-start` / `step-end` 阶梯缓动曲线。
  SvgStepEasing? stepEasing;

  /// Legacy fallback flag for discrete step transitions when [stepEasing] is absent.
  /// 当 [stepEasing] 为空时的离散阶梯过渡回退标记。
  bool isDiscreteSteps;

  /// Whether `animation-play-state: paused` freezes this animation at `t = 0`.
  /// 是否因 `animation-play-state: paused` 将动画冻结在 `t = 0`。
  bool isPaused;

  /// Creates an [SvgCssAnimationConfig].
  /// 创建一个 [SvgCssAnimationConfig] 实例。
  ///
  /// - [name]: Target `@keyframes` identifier. 目标 `@keyframes` 名称。
  /// - [durationUs]: Single-cycle duration in microseconds. 单周期微秒时长。
  /// - [delayUs]: Signed start delay in microseconds. 带符号微秒延迟。
  /// - [iterationCount]: Repeat count (`double.infinity` for infinite). 重复次数。
  /// - [direction]: Playback direction. 播放方向。
  /// - [fillMode]: Fill mode outside active range. 填充保持模式。
  /// - [timingCurve]: Optional cubic-bezier easing. 可选贝塞尔缓动曲线。
  /// - [stepEasing]: Optional step easing curve. 可选阶梯缓动曲线。
  /// - [isDiscreteSteps]: Fallback discrete step flag. 离散阶梯回退标记。
  /// - [isPaused]: Whether animation is paused. 是否暂停。
  SvgCssAnimationConfig({
    required this.name,
    this.durationUs = 0,
    this.delayUs = 0,
    this.iterationCount = 1.0,
    this.direction = SvgAnimationDirection.normal,
    this.fillMode = SvgAnimationFillMode.remove,
    this.timingCurve,
    this.stepEasing,
    this.isDiscreteSteps = false,
    this.isPaused = false,
  });
}

/// A single CSS rule linking an [SvgCssComplexSelector] to its raw normal and
/// `!important` declaration maps so `var()` custom properties and W3C cascade
/// precedence resolve accurately per matched element.
/// 单条 CSS 规则，将 [SvgCssComplexSelector] 关联至普通声明与 `!important` 声明映射表。
class SvgCssRule {
  /// Parsed W3C Selectors Level 4 complex selector.
  /// 解析后的 W3C Selectors Level 4 复合选择器。
  final SvgCssComplexSelector selector;

  /// Normal-priority CSS property declarations.
  /// 普通优先级的 CSS 属性声明映射。
  final Map<String, String> declarations;

  /// `!important` CSS property declarations overriding normal rules and inline styles.
  /// `!important` 高优先级 CSS 属性声明映射。
  final Map<String, String> importantDeclarations;

  /// Source order index used to break specificity ties per W3C Cascade rules.
  /// 源码出现顺序索引，用于在选择器权重相同时按 W3C 级联规则决胜。
  final int orderIndex;

  /// Creates an [SvgCssRule].
  /// 创建一个 [SvgCssRule] 规则对象。
  ///
  /// - [selector]: Parsed complex selector. 已解析的复合选择器。
  /// - [declarations]: Normal declarations map. 普通声明表。
  /// - [importantDeclarations]: `!important` declarations map. `!important` 声明表。
  /// - [orderIndex]: Monotonic stylesheet declaration order. 样式表源码顺序索引。
  const SvgCssRule({
    required this.selector,
    required this.declarations,
    this.importantDeclarations = const {},
    required this.orderIndex,
  });
}

/// A single stop (`0%`..`100%`) inside a `@keyframes` block.
/// `@keyframes` 关键帧块中的单个百分比节点（`0%`..`100%`）。
class SvgCssKeyframeStop {
  /// Normalized keyframe offset in `[0.0 .. 1.0]`.
  /// 归一化关键帧偏移位置（`[0.0 .. 1.0]`）。
  final double offset;

  /// CSS property declarations defined at this keyframe stop.
  /// 该关键帧节点定义的 CSS 属性声明表。
  final Map<String, String> declarations;

  /// Optional per-keyframe cubic-bezier easing toward the next stop.
  /// 可选的指向下一关键帧的三次贝塞尔缓动曲线。
  final Cubic? easingToNext;

  /// Optional per-keyframe `steps(...)` easing toward the next stop.
  /// 可选的指向下一关键帧的 `steps(...)` 阶梯缓动曲线。
  final SvgStepEasing? stepEasingToNext;

  /// Creates an [SvgCssKeyframeStop].
  /// 创建一个 [SvgCssKeyframeStop] 关键帧节点。
  ///
  /// - [offset]: Normalized keyframe offset (`0.0`..`1.0`). 归一化偏移。
  /// - [declarations]: Property declarations at this stop. 该节点声明表。
  /// - [easingToNext]: Optional cubic-bezier curve to next stop. 可选贝塞尔缓动。
  /// - [stepEasingToNext]: Optional step easing to next stop. 可选阶梯缓动。
  const SvgCssKeyframeStop({
    required this.offset,
    required this.declarations,
    this.easingToNext,
    this.stepEasingToNext,
  });
}

/// Parsed `<style>` sheet containing selector rules and `@keyframes` definitions.
/// 解析后的 `<style>` 样式表，包含选择器规则列表与 `@keyframes` 关键帧定义映射。
class SvgStyleSheet {
  /// All parsed selector rules in stylesheet source order.
  /// 按源码顺序排列的全部已解析选择器规则。
  final List<SvgCssRule> rules;

  /// `@keyframes` stop lists keyed by animation name.
  /// 按动画名称索引的 `@keyframes` 关键帧节点列表映射。
  final Map<String, List<SvgCssKeyframeStop>> keyframesByName;

  /// Creates an [SvgStyleSheet].
  /// 创建一个 [SvgStyleSheet] 样式表对象。
  ///
  /// - [rules]: Parsed CSS selector rules. 已解析的 CSS 选择器规则列表。
  /// - [keyframesByName]: `@keyframes` definitions indexed by name. 按名称索引的关键帧表。
  const SvgStyleSheet({this.rules = const [], this.keyframesByName = const {}});
}
