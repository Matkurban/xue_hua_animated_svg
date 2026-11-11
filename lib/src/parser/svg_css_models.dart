import 'package:flutter/animation.dart' show Cubic;

import '../animation/svg_timeline.dart';
import '../model/svg_node.dart';
import '../model/svg_style.dart';

/// Precompiled CSS selector supporting only `#id`, `.class`, and `tagName`.
enum SvgCssSelectorType { id, className, tag }

class SvgCssSelector {
  final SvgCssSelectorType type;
  final String name;

  const SvgCssSelector(this.type, this.name);

  /// Specificity score (`#id` = 100, `.class` = 10, `tag` = 1).
  int get specificity {
    switch (type) {
      case SvgCssSelectorType.id:
        return 100;
      case SvgCssSelectorType.className:
        return 10;
      case SvgCssSelectorType.tag:
        return 1;
    }
  }

  bool matches(SvgElement element) {
    switch (type) {
      case SvgCssSelectorType.id:
        return element.id == name;
      case SvgCssSelectorType.className:
        return element.classes.contains(name);
      case SvgCssSelectorType.tag:
        return element.tagName == name;
    }
  }
}

/// Precompiled CSS animation binding parsed from `animation` or `animation-*` properties.
class SvgCssAnimationConfig {
  String name;
  int durationUs;
  int delayUs;
  double iterationCount;
  SvgAnimationDirection direction;
  SvgAnimationFillMode fillMode;
  Cubic? timingCurve;
  bool isDiscreteSteps;

  SvgCssAnimationConfig({
    required this.name,
    this.durationUs = 0,
    this.delayUs = 0,
    this.iterationCount = 1.0,
    this.direction = SvgAnimationDirection.normal,
    this.fillMode = SvgAnimationFillMode.remove,
    this.timingCurve,
    this.isDiscreteSteps = false,
  });
}

/// A single CSS rule linking a simple selector to precompiled [SvgStyle] and
/// optional [SvgCssAnimationConfig] list.
class SvgCssRule {
  final SvgCssSelector selector;
  final SvgStyle style;
  final List<SvgCssAnimationConfig> animations;
  final int orderIndex;

  const SvgCssRule({
    required this.selector,
    required this.style,
    required this.animations,
    required this.orderIndex,
  });
}

/// A single stop (`0%`..`100%`) inside a `@keyframes` block.
class SvgCssKeyframeStop {
  final double offset; // 0.0 .. 1.0
  final Map<String, String> declarations;
  final Cubic? easingToNext;

  const SvgCssKeyframeStop({
    required this.offset,
    required this.declarations,
    this.easingToNext,
  });
}

/// Parsed `<style>` sheet containing simple rules and `@keyframes` definitions.
class SvgStyleSheet {
  final List<SvgCssRule> rules;
  final Map<String, List<SvgCssKeyframeStop>> keyframesByName;

  const SvgStyleSheet({this.rules = const [], this.keyframesByName = const {}});
}
