import 'package:flutter/animation.dart' show Cubic;

import '../animation/svg_timeline.dart';
import 'svg_css_selector.dart';

export 'svg_css_selector.dart';
export 'svg_css_variables.dart';

/// Precompiled CSS animation binding parsed from `animation` or `animation-*` properties.
class SvgCssAnimationConfig {
  String name;
  int durationUs;
  int delayUs;
  double iterationCount;
  SvgAnimationDirection direction;
  SvgAnimationFillMode fillMode;
  Cubic? timingCurve;
  SvgStepEasing? stepEasing;
  bool isDiscreteSteps;
  bool isPaused;

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

/// A single CSS rule linking a [SvgCssComplexSelector] to its raw normal and
/// `!important` declaration maps so `var()` custom properties and W3C cascade
/// precedence resolve accurately per matched element.
class SvgCssRule {
  final SvgCssComplexSelector selector;
  final Map<String, String> declarations;
  final Map<String, String> importantDeclarations;
  final int orderIndex;

  const SvgCssRule({
    required this.selector,
    required this.declarations,
    this.importantDeclarations = const {},
    required this.orderIndex,
  });
}

/// A single stop (`0%`..`100%`) inside a `@keyframes` block.
class SvgCssKeyframeStop {
  final double offset; // 0.0 .. 1.0
  final Map<String, String> declarations;
  final Cubic? easingToNext;
  final SvgStepEasing? stepEasingToNext;

  const SvgCssKeyframeStop({
    required this.offset,
    required this.declarations,
    this.easingToNext,
    this.stepEasingToNext,
  });
}

/// Parsed `<style>` sheet containing selector rules and `@keyframes` definitions.
class SvgStyleSheet {
  final List<SvgCssRule> rules;
  final Map<String, List<SvgCssKeyframeStop>> keyframesByName;

  const SvgStyleSheet({this.rules = const [], this.keyframesByName = const {}});
}
