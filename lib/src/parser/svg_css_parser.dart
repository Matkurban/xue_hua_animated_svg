import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Cubic;

import '../animation/svg_motion_morph.dart';
import '../animation/svg_timeline.dart';
import '../model/svg_node.dart';
import '../model/svg_style.dart';
import '../model/svg_transform.dart';
import 'svg_path_parser.dart';

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

/// Precompiles `<style>` blocks, inline `style="..."` attributes, `@keyframes`,
/// colors, numbers, transforms, and `transform-origin` during the XML build phase.
abstract final class SvgCssParser {
  // Standard easing curves
  static const Cubic ease = Cubic(0.25, 0.1, 0.25, 1.0);
  static const Cubic easeIn = Cubic(0.42, 0.0, 1.0, 1.0);
  static const Cubic easeOut = Cubic(0.0, 0.0, 0.58, 1.0);
  static const Cubic easeInOut = Cubic(0.42, 0.0, 0.58, 1.0);

  /// Parses one or more `<style>` text blocks into a unified [SvgStyleSheet].
  static SvgStyleSheet parseStyleSheet(String cssText) {
    final cleaned = _stripCssComments(cssText);
    final rules = <SvgCssRule>[];
    final keyframesByName = <String, List<SvgCssKeyframeStop>>{};

    int pos = 0;
    final len = cleaned.length;
    int ruleOrder = 0;

    while (pos < len) {
      pos = _skipWhitespace(cleaned, pos);
      if (pos >= len) break;

      if (cleaned.startsWith('@keyframes', pos) ||
          cleaned.startsWith('@-webkit-keyframes', pos)) {
        final openBrace = cleaned.indexOf('{', pos);
        if (openBrace == -1) break;
        final header = cleaned.substring(pos, openBrace).trim();
        final parts = header.split(RegExp(r'\s+'));
        final kfName = parts.length >= 2 ? parts.last.trim() : '';
        final closeBrace = _findMatchingBrace(cleaned, openBrace);
        if (closeBrace == -1) break;

        if (kfName.isNotEmpty) {
          final body = cleaned.substring(openBrace + 1, closeBrace);
          keyframesByName[kfName] = _parseKeyframesBody(body);
        }
        pos = closeBrace + 1;
      } else if (cleaned.codeUnitAt(pos) == 0x40) {
        // Skip unsupported @-rules (@media, @import, etc.)
        final openBrace = cleaned.indexOf('{', pos);
        final semicolon = cleaned.indexOf(';', pos);
        if (semicolon != -1 && (openBrace == -1 || semicolon < openBrace)) {
          pos = semicolon + 1;
        } else if (openBrace != -1) {
          final closeBrace = _findMatchingBrace(cleaned, openBrace);
          pos = closeBrace != -1 ? closeBrace + 1 : len;
        } else {
          break;
        }
      } else {
        final openBrace = cleaned.indexOf('{', pos);
        if (openBrace == -1) break;
        final selectorGroup = cleaned.substring(pos, openBrace).trim();
        final closeBrace = _findMatchingBrace(cleaned, openBrace);
        if (closeBrace == -1) break;
        final declText = cleaned.substring(openBrace + 1, closeBrace);

        final declMap = parseDeclarationsMap(declText);
        final style = SvgStyle();
        final animations = <SvgCssAnimationConfig>[];
        applyDeclarationsToStyle(declMap, style, animations);

        final selectorTokens = selectorGroup.split(',');
        for (final rawSel in selectorTokens) {
          final sel = _parseSimpleSelector(rawSel.trim());
          if (sel != null) {
            rules.add(
              SvgCssRule(
                selector: sel,
                style: style,
                animations: animations,
                orderIndex: ruleOrder++,
              ),
            );
          }
        }
        pos = closeBrace + 1;
      }
    }

    return SvgStyleSheet(rules: rules, keyframesByName: keyframesByName);
  }

  /// Parses only `#id`, `.class`, or `tagName` selectors (explicitly ignoring complex combinators).
  static SvgCssSelector? _parseSimpleSelector(String raw) {
    if (raw.isEmpty) return null;
    // Reject descendant/sibling/pseudo selectors per Out-of-Scope boundary
    if (raw.contains(' ') ||
        raw.contains('>') ||
        raw.contains('+') ||
        raw.contains('~') ||
        raw.contains(':')) {
      return null;
    }
    if (raw.startsWith('#') && raw.length > 1) {
      return SvgCssSelector(SvgCssSelectorType.id, raw.substring(1));
    }
    if (raw.startsWith('.') && raw.length > 1) {
      return SvgCssSelector(SvgCssSelectorType.className, raw.substring(1));
    }
    return SvgCssSelector(SvgCssSelectorType.tag, raw);
  }

  static List<SvgCssKeyframeStop> _parseKeyframesBody(String body) {
    final stopsByOffset = <double, Map<String, String>>{};
    final easingByOffset = <double, Cubic?>{};

    int pos = 0;
    final len = body.length;
    while (pos < len) {
      pos = _skipWhitespace(body, pos);
      if (pos >= len) break;
      final openBrace = body.indexOf('{', pos);
      if (openBrace == -1) break;
      final stopHeader = body.substring(pos, openBrace).trim();
      final closeBrace = _findMatchingBrace(body, openBrace);
      if (closeBrace == -1) break;

      final declText = body.substring(openBrace + 1, closeBrace);
      final decls = parseDeclarationsMap(declText);
      Cubic? stepEasing;
      final tfRaw = decls.remove('animation-timing-function');
      if (tfRaw != null) {
        stepEasing = parseTimingCubic(tfRaw);
      }

      final offsetTokens = stopHeader.split(',');
      for (final token in offsetTokens) {
        final t = token.trim().toLowerCase();
        double? offset;
        if (t == 'from') {
          offset = 0.0;
        } else if (t == 'to') {
          offset = 1.0;
        } else if (t.endsWith('%')) {
          final pct = double.tryParse(t.substring(0, t.length - 1).trim());
          if (pct != null) {
            offset = (pct / 100.0).clamp(0.0, 1.0);
          }
        }
        if (offset != null) {
          final existing = stopsByOffset.putIfAbsent(
            offset,
            () => <String, String>{},
          );
          existing.addAll(decls);
          if (stepEasing != null) {
            easingByOffset[offset] = stepEasing;
          }
        }
      }
      pos = closeBrace + 1;
    }

    final sortedOffsets = stopsByOffset.keys.toList()..sort();
    return [
      for (final off in sortedOffsets)
        SvgCssKeyframeStop(
          offset: off,
          declarations: stopsByOffset[off]!,
          easingToNext: easingByOffset[off],
        ),
    ];
  }

  /// Parses semicolon-separated CSS declarations (`prop: value; ...`) into a Map.
  static Map<String, String> parseDeclarationsMap(String inlineStyle) {
    final map = <String, String>{};
    final parts = inlineStyle.split(';');
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      if (part.isEmpty) continue;
      final colonIdx = part.indexOf(':');
      if (colonIdx <= 0) continue;
      final key = part.substring(0, colonIdx).trim().toLowerCase();
      var val = part.substring(colonIdx + 1).trim();
      if (val.endsWith('!important')) {
        val = val.substring(0, val.length - 10).trim();
      }
      map[key] = val;
    }
    return map;
  }

  /// Applies parsed CSS declarations to [style] and extracts any `animation`
  /// configurations into [outAnimations].
  static void applyDeclarationsToStyle(
    Map<String, String> decls,
    SvgStyle style, [
    List<SvgCssAnimationConfig>? outAnimations,
  ]) {
    decls.forEach((key, value) {
      applySingleAttribute(key, value, style);
    });

    if (outAnimations == null) return;

    final shorthand = decls['animation'];
    if (shorthand != null && shorthand.isNotEmpty && shorthand != 'none') {
      final specs = _splitTopLevelComma(shorthand);
      for (final spec in specs) {
        final cfg = _parseAnimationShorthand(spec);
        if (cfg != null) {
          outAnimations.add(cfg);
        }
      }
    }

    final animName = decls['animation-name'];
    if (animName != null && animName.isNotEmpty && animName != 'none') {
      final names = animName.split(',').map((e) => e.trim()).toList();
      final durs = _splitList(decls['animation-duration']);
      final delays = _splitList(decls['animation-delay']);
      final counts = _splitList(decls['animation-iteration-count']);
      final dirs = _splitList(decls['animation-direction']);
      final fills = _splitList(decls['animation-fill-mode']);
      final funcs = _splitTopLevelComma(
        decls['animation-timing-function'] ?? '',
      );

      for (int i = 0; i < names.length; i++) {
        final name = names[i];
        if (name.isEmpty || name == 'none') continue;
        final cfg = i < outAnimations.length
            ? outAnimations[i]
            : SvgCssAnimationConfig(name: name);
        cfg.name = name;
        if (durs.isNotEmpty) {
          cfg.durationUs =
              parseClockMicroseconds(durs[i % durs.length]) ?? cfg.durationUs;
        }
        if (delays.isNotEmpty) {
          cfg.delayUs =
              parseClockMicroseconds(delays[i % delays.length]) ?? cfg.delayUs;
        }
        if (counts.isNotEmpty) {
          final cStr = counts[i % counts.length].toLowerCase();
          cfg.iterationCount = (cStr == 'infinite' || cStr == 'indefinite')
              ? double.infinity
              : (double.tryParse(cStr) ?? cfg.iterationCount);
        }
        if (dirs.isNotEmpty) {
          cfg.direction =
              _parseDirection(dirs[i % dirs.length]) ?? cfg.direction;
        }
        if (fills.isNotEmpty) {
          cfg.fillMode =
              _parseFillMode(fills[i % fills.length]) ?? cfg.fillMode;
        }
        if (funcs.isNotEmpty && funcs[i % funcs.length].isNotEmpty) {
          final fStr = funcs[i % funcs.length];
          if (fStr.startsWith('steps')) {
            cfg.isDiscreteSteps = true;
          } else {
            cfg.timingCurve = parseTimingCubic(fStr) ?? cfg.timingCurve;
          }
        }
        if (i >= outAnimations.length) {
          outAnimations.add(cfg);
        }
      }
    }
  }

  /// Applies a single presentation attribute or CSS property to [style].
  static void applySingleAttribute(String key, String rawVal, SvgStyle style) {
    final val = rawVal.trim();
    if (val.isEmpty) return;

    switch (key) {
      case 'fill':
        style.baseFill = parsePaintServer(val);
      case 'stroke':
        style.baseStroke = parsePaintServer(val);
      case 'fill-opacity':
        style.baseFillOpacity = parseNumberOrPercent(val);
      case 'stroke-opacity':
        style.baseStrokeOpacity = parseNumberOrPercent(val);
      case 'opacity':
        style.baseOpacity = parseNumberOrPercent(val);
      case 'stroke-width':
        style.baseStrokeWidth = parseLength(val);
      case 'stroke-linecap':
        if (val == 'round') {
          style.baseStrokeCap = ui.StrokeCap.round;
        } else if (val == 'square') {
          style.baseStrokeCap = ui.StrokeCap.square;
        } else if (val == 'butt') {
          style.baseStrokeCap = ui.StrokeCap.butt;
        }
      case 'stroke-linejoin':
        if (val == 'round') {
          style.baseStrokeJoin = ui.StrokeJoin.round;
        } else if (val == 'bevel') {
          style.baseStrokeJoin = ui.StrokeJoin.bevel;
        } else if (val == 'miter') {
          style.baseStrokeJoin = ui.StrokeJoin.miter;
        }
      case 'stroke-miterlimit':
        style.baseStrokeMiterLimit = parseLength(val);
      case 'fill-rule':
      case 'clip-rule':
        if (val == 'evenodd') {
          style.baseFillRule = ui.PathFillType.evenOdd;
        } else if (val == 'nonzero') {
          style.baseFillRule = ui.PathFillType.nonZero;
        }
      case 'stroke-dasharray':
        if (val == 'none') {
          style.baseStrokeDasharray = Float64List(0);
        } else {
          final nums = parseNumberList(val);
          if (nums.isNotEmpty) {
            style.baseStrokeDasharray = nums;
          }
        }
      case 'stroke-dashoffset':
        style.baseStrokeDashoffset = parseLength(val);
      case 'pathlength':
      case 'pathLength':
        style.basePathLength = parseLength(val);
      case 'filter':
        final blur = _parseBlurFilter(val);
        if (blur != null) {
          style.baseBlurSigma = blur;
        }
      case 'transform-origin':
        style.baseTransformOrigin = parseTransformOrigin(val);
      case 'transform':
        final ops = parseTransformOps(val);
        if (ops.isNotEmpty) {
          style.cssBaseTransformOps = ops;
        }
      case 'clip-path':
        style.clipPathId = extractUrlId(val);
      case 'display':
        style.displayNone = val == 'none';
      case 'visibility':
        style.visibilityHidden = val == 'hidden' || val == 'collapse';
    }
  }

  /// Compiles a matched [SvgCssAnimationConfig] and `@keyframes` stop list into
  /// internal [SvgAnimationTrack] instances on [target].
  static List<SvgAnimationTrack> compileKeyframesForElement({
    required SvgElement target,
    required SvgCssAnimationConfig config,
    required List<SvgCssKeyframeStop> stops,
    required ui.Rect documentViewBox,
  }) {
    final tracks = <SvgAnimationTrack>[];
    if (stops.isEmpty || config.durationUs <= 0) return tracks;

    // Collect all animated property names across keyframe stops
    final animatedProps = <String>{};
    for (final stop in stops) {
      animatedProps.addAll(stop.declarations.keys);
    }

    // Ensure 0.0 and 1.0 stops exist by synthesizing from element's base state if omitted
    final normalizedStops = List<SvgCssKeyframeStop>.from(stops);
    if (normalizedStops.first.offset > 0.0) {
      normalizedStops.insert(
        0,
        const SvgCssKeyframeStop(offset: 0.0, declarations: {}),
      );
    }
    if (normalizedStops.last.offset < 1.0) {
      normalizedStops.add(
        const SvgCssKeyframeStop(offset: 1.0, declarations: {}),
      );
    }

    for (final prop in animatedProps) {
      final track = _compilePropertyKeyframeTrack(
        target: target,
        property: prop,
        config: config,
        stops: normalizedStops,
        documentViewBox: documentViewBox,
      );
      if (track != null) {
        tracks.add(track);
      }
    }

    return tracks;
  }

  static SvgAnimationTrack? _compilePropertyKeyframeTrack({
    required SvgElement target,
    required String property,
    required SvgCssAnimationConfig config,
    required List<SvgCssKeyframeStop> stops,
    required ui.Rect documentViewBox,
  }) {
    // Filter stops that define this property, or include endpoints 0.0 and 1.0
    final keyTimesList = <double>[];
    final rawValues = <String>[];
    final splines = <Cubic>[];
    bool hasCustomSpline = config.timingCurve != null;

    for (int i = 0; i < stops.length; i++) {
      final stop = stops[i];
      final val =
          stop.declarations[property] ??
          ((i == 0 || i == stops.length - 1)
              ? _defaultPropertyStringForElement(target, property)
              : null);
      if (val != null) {
        keyTimesList.add(stop.offset);
        rawValues.add(val);
        if (stop.easingToNext != null) {
          hasCustomSpline = true;
          splines.add(stop.easingToNext!);
        } else {
          splines.add(config.timingCurve ?? const Cubic(0.0, 0.0, 1.0, 1.0));
        }
      }
    }

    if (rawValues.length < 2) return null;
    if (splines.length >= rawValues.length) {
      splines.removeLast();
    }

    final beginOffsets = List<int>.unmodifiable([config.delayUs]);
    final timing = SvgAnimationTiming(
      beginOffsetsUs: beginOffsets,
      durationUs: config.durationUs,
      repeatCount: config.iterationCount,
      fillMode: config.fillMode,
      direction: config.direction,
      calcMode: config.isDiscreteSteps
          ? SvgCalcMode.discrete
          : (hasCustomSpline ? SvgCalcMode.spline : SvgCalcMode.linear),
      keyTimes: Float64List.fromList(keyTimesList),
      keySplines: hasCustomSpline ? splines : null,
    );

    switch (property) {
      case 'transform':
        final opsPerKeyframe = <List<SvgTransformOp>>[];
        for (final raw in rawValues) {
          opsPerKeyframe.add(
            raw == 'none' ? const <SvgTransformOp>[] : parseTransformOps(raw),
          );
        }
        return SvgCssMultiTransformTrack(
          timing: timing,
          target: target,
          keyframeOps: opsPerKeyframe,
          documentViewBox: documentViewBox,
        );

      case 'opacity':
      case 'fill-opacity':
      case 'stroke-opacity':
      case 'stroke-width':
      case 'stroke-dashoffset':
      case 'rx':
      case 'ry':
      case 'r':
      case 'cx':
      case 'cy':
      case 'x':
      case 'y':
      case 'width':
      case 'height':
        final scalarTarget = _mapScalarProperty(property);
        if (scalarTarget == null) return null;
        final values = Float64List(rawValues.length);
        for (int i = 0; i < rawValues.length; i++) {
          values[i] =
              (property.contains('opacity')
                  ? parseNumberOrPercent(rawValues[i])
                  : parseLength(rawValues[i])) ??
              0.0;
        }
        if (property == 'stroke-dashoffset' && target is SvgGeometryNode) {
          target.needsPathMetrics = true;
        }
        return SvgScalarAnimationTrack(
          timing: timing,
          target: target,
          property: scalarTarget,
          keyframes: values,
        );

      case 'filter':
        final values = Float64List(rawValues.length);
        for (int i = 0; i < rawValues.length; i++) {
          values[i] = _parseBlurFilter(rawValues[i]) ?? 0.0;
        }
        return SvgScalarAnimationTrack(
          timing: timing,
          target: target,
          property: SvgScalarTarget.blurSigma,
          keyframes: values,
        );

      case 'fill':
      case 'stroke':
        final colors = <ui.Color>[];
        for (final raw in rawValues) {
          colors.add(parseColor(raw) ?? const ui.Color(0xFF000000));
        }
        return SvgColorAnimationTrack(
          timing: timing,
          target: target,
          property: property == 'fill'
              ? SvgColorTarget.fill
              : SvgColorTarget.stroke,
          keyframes: colors,
        );

      case 'stroke-dasharray':
        final rawArrays = <Float64List>[];
        for (final raw in rawValues) {
          rawArrays.add(parseNumberList(raw));
        }
        final normalized = normalizeDashArrayKeyframes(rawArrays);
        if (normalized.isEmpty) return null;
        if (target is SvgGeometryNode) {
          target.needsPathMetrics = true;
        }
        return SvgDashArrayAnimationTrack(
          timing: timing,
          target: target,
          keyframes: normalized,
        );

      case 'd':
        if (target is SvgPathNode) {
          final coordsList = <Float64List>[];
          for (final raw in rawValues) {
            final cleaned = raw
                .replaceAll(RegExp(r'^path\s*\(\s*["\x27]?'), '')
                .replaceAll(RegExp(r'["\x27]?\s*\)$'), '');
            final parsed = SvgPathParser.parse(cleaned);
            if (parsed.isIsomorphicWith(target.precompiledPath)) {
              coordsList.add(parsed.coords);
            }
          }
          if (coordsList.length == rawValues.length) {
            return SvgPathMorphAnimationTrack(
              timing: timing,
              target: target,
              keyframeCoords: coordsList,
            );
          }
        }
        return null;

      default:
        return null;
    }
  }

  static String? _defaultPropertyStringForElement(
    SvgElement target,
    String property,
  ) {
    final s = target.style;
    switch (property) {
      case 'transform':
        return 'none';
      case 'opacity':
        return '${s.baseOpacity ?? 1.0}';
      case 'fill-opacity':
        return '${s.baseFillOpacity ?? 1.0}';
      case 'stroke-opacity':
        return '${s.baseStrokeOpacity ?? 1.0}';
      case 'stroke-width':
        return '${s.baseStrokeWidth ?? 1.0}';
      case 'stroke-dashoffset':
        return '${s.baseStrokeDashoffset ?? 0.0}';
      case 'filter':
        return 'blur(${s.baseBlurSigma ?? 0.0}px)';
      case 'fill':
        final c = s.baseFill?.color ?? const ui.Color(0xFF000000);
        return '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      case 'stroke':
        final c = s.baseStroke?.color ?? const ui.Color(0xFF000000);
        return '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      default:
        return null;
    }
  }

  static SvgScalarTarget? _mapScalarProperty(String prop) {
    switch (prop) {
      case 'opacity':
        return SvgScalarTarget.opacity;
      case 'fill-opacity':
        return SvgScalarTarget.fillOpacity;
      case 'stroke-opacity':
        return SvgScalarTarget.strokeOpacity;
      case 'stroke-width':
        return SvgScalarTarget.strokeWidth;
      case 'stroke-dashoffset':
        return SvgScalarTarget.strokeDashoffset;
      case 'x':
        return SvgScalarTarget.x;
      case 'y':
        return SvgScalarTarget.y;
      case 'width':
        return SvgScalarTarget.width;
      case 'height':
        return SvgScalarTarget.height;
      case 'rx':
        return SvgScalarTarget.rx;
      case 'ry':
        return SvgScalarTarget.ry;
      case 'cx':
        return SvgScalarTarget.cx;
      case 'cy':
        return SvgScalarTarget.cy;
      case 'r':
        return SvgScalarTarget.r;
      default:
        return null;
    }
  }

  /// Normalizes a list of `stroke-dasharray` keyframe arrays to their least
  /// common multiple (LCM) length so they can be interpolated element-by-element.
  static List<Float64List> normalizeDashArrayKeyframes(
    List<Float64List> arrays,
  ) {
    final nonEmpty = arrays.where((a) => a.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return const [];

    int lcmLen = 1;
    for (final a in nonEmpty) {
      final evenLen = a.length.isOdd ? a.length * 2 : a.length;
      lcmLen = _lcm(lcmLen, evenLen);
    }

    return [
      for (final a in arrays)
        if (a.isEmpty)
          Float64List(lcmLen)
        else
          Float64List.fromList([
            for (int i = 0; i < lcmLen; i++) a[i % a.length],
          ]),
    ];
  }

  static int _gcd(int a, int b) {
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a;
  }

  static int _lcm(int a, int b) =>
      (a == 0 || b == 0) ? 0 : (a * b) ~/ _gcd(a, b);

  /// Parses `transform-origin` supporting pixel lengths, percentages (`50% 50%`),
  /// and keywords (`center`, `left`, `right`, `top`, `bottom`).
  static SvgTransformOrigin parseTransformOrigin(String raw) {
    final tokens = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return SvgTransformOrigin.zero;

    String xTok = tokens[0].toLowerCase();
    String yTok = tokens.length > 1 ? tokens[1].toLowerCase() : 'center';

    // Handle swapped order like "top left" or "bottom right"
    if ((xTok == 'top' || xTok == 'bottom') &&
        (yTok == 'left' || yTok == 'right' || yTok == 'center')) {
      final tmp = xTok;
      xTok = yTok;
      yTok = tmp;
    }

    final (xVal, xUnit) = _parseOriginAxis(xTok);
    final (yVal, yUnit) = _parseOriginAxis(yTok);
    return SvgTransformOrigin(x: xVal, y: yVal, unitX: xUnit, unitY: yUnit);
  }

  static (double, SvgOriginUnit) _parseOriginAxis(String token) {
    switch (token) {
      case 'center':
        return (0.5, SvgOriginUnit.boundingBoxPercent);
      case 'left':
      case 'top':
        return (0.0, SvgOriginUnit.boundingBoxPercent);
      case 'right':
      case 'bottom':
        return (1.0, SvgOriginUnit.boundingBoxPercent);
      default:
        if (token.endsWith('%')) {
          final numVal =
              double.tryParse(token.substring(0, token.length - 1).trim()) ??
              0.0;
          return (numVal / 100.0, SvgOriginUnit.boundingBoxPercent);
        }
        return (parseLength(token) ?? 0.0, SvgOriginUnit.pixels);
    }
  }

  /// Parses an SVG or CSS `transform` string into a list of [SvgTransformOp].
  static List<SvgTransformOp> parseTransformOps(String raw) {
    final ops = <SvgTransformOp>[];
    final matches = RegExp(r'([a-zA-Z0-9]+)\s*\(([^)]*)\)').allMatches(raw);
    for (final match in matches) {
      final func = match.group(1)!.trim();
      final argsStr = match.group(2)!.trim();
      final rawArgs = argsStr
          .split(RegExp(r'[\s,]+'))
          .where((s) => s.isNotEmpty)
          .toList();
      final nums = <double>[
        for (final a in rawArgs) parseAngleOrLength(a) ?? 0.0,
      ];
      if (nums.isEmpty) continue;

      switch (func) {
        case 'translate':
        case 'translate3d':
          ops.add(
            SvgTransformOp.translate(nums[0], nums.length > 1 ? nums[1] : 0.0),
          );
        case 'translateX':
          ops.add(SvgTransformOp.translate(nums[0], 0.0));
        case 'translateY':
          ops.add(SvgTransformOp.translate(0.0, nums[0]));
        case 'scale':
        case 'scale3d':
          ops.add(
            SvgTransformOp.scale(nums[0], nums.length > 1 ? nums[1] : nums[0]),
          );
        case 'scaleX':
          ops.add(SvgTransformOp.scale(nums[0], 1.0));
        case 'scaleY':
          ops.add(SvgTransformOp.scale(1.0, nums[0]));
        case 'rotate':
          ops.add(
            SvgTransformOp.rotate(
              nums[0],
              nums.length > 1 ? nums[1] : 0.0,
              nums.length > 2 ? nums[2] : 0.0,
            ),
          );
        case 'rotateZ':
          ops.add(SvgTransformOp.rotateZ(nums[0]));
        case 'rotateX':
          ops.add(SvgTransformOp.rotateX(nums[0]));
        case 'rotateY':
          ops.add(SvgTransformOp.rotateY(nums[0]));
        case 'skewX':
          ops.add(SvgTransformOp.skewX(nums[0]));
        case 'skewY':
          ops.add(SvgTransformOp.skewY(nums[0]));
        case 'perspective':
          ops.add(SvgTransformOp.perspective(nums[0]));
        case 'matrix':
          if (nums.length >= 6) {
            ops.add(
              SvgTransformOp.matrix(
                nums[0],
                nums[1],
                nums[2],
                nums[3],
                nums[4],
                nums[5],
              ),
            );
          }
      }
    }
    return ops;
  }

  /// Parses an angle (`deg`, `rad`, `turn`, `grad`) or length into degrees / pixels.
  static double? parseAngleOrLength(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.endsWith('deg')) {
      return double.tryParse(s.substring(0, s.length - 3).trim());
    }
    if (s.endsWith('rad')) {
      final rad = double.tryParse(s.substring(0, s.length - 3).trim());
      return rad != null ? rad * (180.0 / math.pi) : null;
    }
    if (s.endsWith('turn')) {
      final turn = double.tryParse(s.substring(0, s.length - 4).trim());
      return turn != null ? turn * 360.0 : null;
    }
    if (s.endsWith('grad')) {
      final grad = double.tryParse(s.substring(0, s.length - 4).trim());
      return grad != null ? grad * 0.9 : null;
    }
    return parseLength(s);
  }

  /// Parses an SVG/CSS clock duration (`500ms`, `2.5s`, `02:30`, `1.5h`) into microseconds.
  static int? parseClockMicroseconds(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty || s == 'indefinite') return null;

    if (s.endsWith('ms')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? (v * 1000.0).round() : null;
    }
    if (s.endsWith('s')) {
      final v = double.tryParse(s.substring(0, s.length - 1).trim());
      return v != null ? (v * 1000000.0).round() : null;
    }
    if (s.endsWith('min')) {
      final v = double.tryParse(s.substring(0, s.length - 3).trim());
      return v != null ? (v * 60.0 * 1000000.0).round() : null;
    }
    if (s.endsWith('h')) {
      final v = double.tryParse(s.substring(0, s.length - 1).trim());
      return v != null ? (v * 3600.0 * 1000000.0).round() : null;
    }
    if (s.contains(':')) {
      final parts = s.split(':');
      if (parts.length == 2) {
        final mins = double.tryParse(parts[0]) ?? 0.0;
        final secs = double.tryParse(parts[1]) ?? 0.0;
        return ((mins * 60.0 + secs) * 1000000.0).round();
      } else if (parts.length == 3) {
        final hrs = double.tryParse(parts[0]) ?? 0.0;
        final mins = double.tryParse(parts[1]) ?? 0.0;
        final secs = double.tryParse(parts[2]) ?? 0.0;
        return ((hrs * 3600.0 + mins * 60.0 + secs) * 1000000.0).round();
      }
    }
    final secVal = double.tryParse(s);
    return secVal != null ? (secVal * 1000000.0).round() : null;
  }

  /// Parses a CSS timing function (`ease`, `linear`, `ease-in`, `ease-out`,
  /// `ease-in-out`, `cubic-bezier(x1, y1, x2, y2)`) into a Flutter [Cubic].
  static Cubic? parseTimingCubic(String raw) {
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'linear':
        return const Cubic(0.0, 0.0, 1.0, 1.0);
      case 'ease':
        return ease;
      case 'ease-in':
        return easeIn;
      case 'ease-out':
        return easeOut;
      case 'ease-in-out':
        return easeInOut;
      default:
        if (s.startsWith('cubic-bezier(') && s.endsWith(')')) {
          final inner = s.substring(13, s.length - 1);
          final nums = parseNumberList(inner);
          if (nums.length >= 4) {
            return Cubic(nums[0], nums[1], nums[2], nums[3]);
          }
        }
        return null;
    }
  }

  static SvgCssAnimationConfig? _parseAnimationShorthand(String spec) {
    final tokens = _tokenizeAnimationShorthand(spec.trim());
    if (tokens.isEmpty) return null;

    String? name;
    int? durationUs;
    int? delayUs;
    double iterationCount = 1.0;
    SvgAnimationDirection direction = SvgAnimationDirection.normal;
    SvgAnimationFillMode fillMode = SvgAnimationFillMode.remove;
    Cubic? timingCurve;
    bool isDiscrete = false;

    for (final tok in tokens) {
      final lower = tok.toLowerCase();
      if (lower == 'none') continue;

      final dir = _parseDirection(lower);
      if (dir != null) {
        direction = dir;
        continue;
      }

      final fill = _parseFillMode(lower);
      if (fill != null) {
        fillMode = fill;
        continue;
      }

      if (lower == 'infinite' || lower == 'indefinite') {
        iterationCount = double.infinity;
        continue;
      }

      if (lower.startsWith('steps')) {
        isDiscrete = true;
        continue;
      }

      final cubic = parseTimingCubic(lower);
      if (cubic != null) {
        timingCurve = cubic;
        continue;
      }

      if (lower.endsWith('ms') || lower.endsWith('s')) {
        final timeVal = parseClockMicroseconds(lower);
        if (timeVal != null) {
          if (durationUs == null) {
            durationUs = timeVal;
          } else {
            delayUs = timeVal;
          }
          continue;
        }
      }

      final numVal = double.tryParse(lower);
      if (numVal != null) {
        iterationCount = numVal;
        continue;
      }

      name ??= tok;
    }

    if (name == null || name.isEmpty) return null;
    return SvgCssAnimationConfig(
      name: name,
      durationUs: durationUs ?? 0,
      delayUs: delayUs ?? 0,
      iterationCount: iterationCount,
      direction: direction,
      fillMode: fillMode,
      timingCurve: timingCurve,
      isDiscreteSteps: isDiscrete,
    );
  }

  static List<String> _tokenizeAnimationShorthand(String spec) {
    final result = <String>[];
    int start = 0;
    int depth = 0;
    for (int i = 0; i < spec.length; i++) {
      final c = spec.codeUnitAt(i);
      if (c == 0x28) {
        depth++;
      } else if (c == 0x29) {
        if (depth > 0) depth--;
      } else if ((c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) &&
          depth == 0) {
        if (i > start) {
          result.add(spec.substring(start, i));
        }
        start = i + 1;
      }
    }
    if (start < spec.length) {
      result.add(spec.substring(start));
    }
    return result;
  }

  static SvgAnimationDirection? _parseDirection(String s) {
    switch (s.trim().toLowerCase()) {
      case 'normal':
        return SvgAnimationDirection.normal;
      case 'reverse':
        return SvgAnimationDirection.reverse;
      case 'alternate':
        return SvgAnimationDirection.alternate;
      case 'alternate-reverse':
        return SvgAnimationDirection.alternateReverse;
      default:
        return null;
    }
  }

  static SvgAnimationFillMode? _parseFillMode(String s) {
    switch (s.trim().toLowerCase()) {
      case 'forwards':
      case 'freeze':
        return SvgAnimationFillMode.freeze;
      case 'backwards':
        return SvgAnimationFillMode.backwards;
      case 'both':
        return SvgAnimationFillMode.both;
      case 'none':
      case 'remove':
        return SvgAnimationFillMode.remove;
      default:
        return null;
    }
  }

  static double? _parseBlurFilter(String val) {
    final m = RegExp(r'blur\s*\(\s*([^)]+)\s*\)').firstMatch(val);
    if (m != null) {
      return parseLength(m.group(1)!);
    }
    return null;
  }

  /// Extracts `id` from `url(#id)`, or from a bare `#id` that is not a color.
  ///
  /// `url(#ffffff)` still returns `ffffff`. A bare hex color (`#rgb`, `#rgba`,
  /// `#rrggbb`, `#rrggbbaa`) returns null so fill and stroke can stay solid
  /// colors. Non-hex bare references such as `#clip1` still resolve for
  /// `clip-path` and href-style uses.
  static String? extractUrlId(String raw) {
    final s = raw.trim();
    if (s.startsWith('url(') && s.endsWith(')')) {
      var inner = s.substring(4, s.length - 1).trim();
      if ((inner.startsWith('"') && inner.endsWith('"')) ||
          (inner.startsWith("'") && inner.endsWith("'"))) {
        inner = inner.substring(1, inner.length - 1).trim();
      }
      if (inner.startsWith('#')) {
        return inner.substring(1);
      }
      return inner;
    }
    if (s.startsWith('#')) {
      if (_isHexColor(s)) return null;
      return s.substring(1);
    }
    return null;
  }

  /// True for `#rgb`, `#rgba`, `#rrggbb`, and `#rrggbbaa` (case-insensitive).
  static bool _isHexColor(String raw) {
    final n = raw.length - 1;
    if (raw.isEmpty || raw.codeUnitAt(0) != 0x23) return false;
    if (n != 3 && n != 4 && n != 6 && n != 8) return false;
    for (var i = 1; i < raw.length; i++) {
      final c = raw.codeUnitAt(i);
      final isHex =
          (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x46) ||
          (c >= 0x61 && c <= 0x66);
      if (!isHex) return false;
    }
    return true;
  }

  /// Parses an SVG `fill` or `stroke` value into an [SvgPaintServer].
  ///
  /// Solid colors (hex, `rgb()` / `rgba()`, named) are resolved before
  /// `url(#id)` paint servers. Bare `#rrggbb` is never a gradient id.
  /// `none` and `transparent` are handled after those two forms.
  static SvgPaintServer? parsePaintServer(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final color = parseColor(s);
    if (color != null) {
      return SvgPaintServer.fromColor(color);
    }

    if (s.startsWith('url(')) {
      final urlId = extractUrlId(s);
      if (urlId != null && urlId.isNotEmpty) {
        return SvgPaintServer.fromGradient(urlId);
      }
    }

    if (s == 'none') return SvgPaintServer.none;
    if (s == 'transparent') {
      return SvgPaintServer.fromColor(const ui.Color(0x00000000));
    }
    return null;
  }

  /// Parses hex (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`), `rgb()`, `rgba()`,
  /// and standard SVG named colors into a [ui.Color] at parse time.
  static ui.Color? parseColor(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty || s == 'none') return null;
    if (s == 'transparent') return const ui.Color(0x00000000);

    if (s.startsWith('#')) {
      final hex = s.substring(1);
      if (hex.length == 3) {
        final r = int.tryParse('${hex[0]}${hex[0]}', radix: 16);
        final g = int.tryParse('${hex[1]}${hex[1]}', radix: 16);
        final b = int.tryParse('${hex[2]}${hex[2]}', radix: 16);
        if (r != null && g != null && b != null) {
          return ui.Color.fromARGB(255, r, g, b);
        }
      } else if (hex.length == 4) {
        final r = int.tryParse('${hex[0]}${hex[0]}', radix: 16);
        final g = int.tryParse('${hex[1]}${hex[1]}', radix: 16);
        final b = int.tryParse('${hex[2]}${hex[2]}', radix: 16);
        final a = int.tryParse('${hex[3]}${hex[3]}', radix: 16);
        if (r != null && g != null && b != null && a != null) {
          return ui.Color.fromARGB(a, r, g, b);
        }
      } else if (hex.length == 6) {
        final v = int.tryParse(hex, radix: 16);
        if (v != null) {
          return ui.Color(0xFF000000 | v);
        }
      } else if (hex.length == 8) {
        final rrggbb = int.tryParse(hex.substring(0, 6), radix: 16);
        final aa = int.tryParse(hex.substring(6, 8), radix: 16);
        if (rrggbb != null && aa != null) {
          return ui.Color((aa << 24) | rrggbb);
        }
      }
      return null;
    }

    if (s.startsWith('rgb(') || s.startsWith('rgba(')) {
      final open = s.indexOf('(');
      final close = s.lastIndexOf(')');
      if (open != -1 && close > open) {
        final parts = s
            .substring(open + 1, close)
            .split(RegExp(r'[\s,/]+'))
            .where((e) => e.isNotEmpty)
            .toList();
        if (parts.length >= 3) {
          int parseChannel(String p) {
            if (p.endsWith('%')) {
              final pct = double.tryParse(p.substring(0, p.length - 1)) ?? 0.0;
              return ((pct / 100.0) * 255.0).round().clamp(0, 255);
            }
            return (double.tryParse(p) ?? 0.0).round().clamp(0, 255);
          }

          final r = parseChannel(parts[0]);
          final g = parseChannel(parts[1]);
          final b = parseChannel(parts[2]);
          int a = 255;
          if (parts.length >= 4) {
            final aRatio = parseNumberOrPercent(parts[3]) ?? 1.0;
            a = (aRatio.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
          }
          return ui.Color.fromARGB(a, r, g, b);
        }
      }
      return null;
    }

    return _namedColors[s];
  }

  /// Parses a number or percentage (`50%` -> `0.5`).
  static double? parseNumberOrPercent(String? raw, {double? referenceExtent}) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.endsWith('%')) {
      final v = double.tryParse(s.substring(0, s.length - 1).trim());
      if (v == null) return null;
      final ratio = v / 100.0;
      return referenceExtent != null ? ratio * referenceExtent : ratio;
    }
    return parseLength(s);
  }

  /// Parses an SVG length (`px`, `pt`, `pc`, `mm`, `cm`, `in`, or unitless number).
  static double? parseLength(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.endsWith('px')) {
      return double.tryParse(s.substring(0, s.length - 2).trim());
    }
    if (s.endsWith('pt')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? v * (96.0 / 72.0) : null;
    }
    if (s.endsWith('pc')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? v * 16.0 : null;
    }
    if (s.endsWith('mm')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? v * (96.0 / 25.4) : null;
    }
    if (s.endsWith('cm')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? v * (96.0 / 2.54) : null;
    }
    if (s.endsWith('in')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? v * 96.0 : null;
    }
    if (s.endsWith('%')) {
      final v = double.tryParse(s.substring(0, s.length - 1).trim());
      return v != null ? v / 100.0 : null;
    }
    return double.tryParse(s);
  }

  /// Parses a whitespace- or comma-separated list of numbers/lengths into a [Float64List].
  static Float64List parseNumberList(String? raw) {
    if (raw == null || raw.isEmpty) return Float64List(0);
    final tokens = raw
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final values = <double>[];
    for (int i = 0; i < tokens.length; i++) {
      final v = parseLength(tokens[i]);
      if (v != null) values.add(v);
    }
    return Float64List.fromList(values);
  }

  static String _stripCssComments(String css) {
    return css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  }

  static int _skipWhitespace(String s, int pos) {
    while (pos < s.length) {
      final c = s.codeUnitAt(pos);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        pos++;
      } else {
        break;
      }
    }
    return pos;
  }

  static int _findMatchingBrace(String s, int openBracePos) {
    int depth = 0;
    for (int i = openBracePos; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static List<String> _splitList(String? s) {
    if (s == null || s.trim().isEmpty) return const [];
    return s.split(',').map((e) => e.trim()).toList();
  }

  static List<String> _splitTopLevelComma(String s) {
    if (s.trim().isEmpty) return const [];
    final result = <String>[];
    int start = 0;
    int depth = 0;
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x28) {
        depth++;
      } else if (c == 0x29) {
        if (depth > 0) depth--;
      } else if (c == 0x2C && depth == 0) {
        result.add(s.substring(start, i).trim());
        start = i + 1;
      }
    }
    result.add(s.substring(start).trim());
    return result;
  }

  static const Map<String, ui.Color> _namedColors = {
    'black': ui.Color(0xFF000000),
    'white': ui.Color(0xFFFFFFFF),
    'red': ui.Color(0xFFFF0000),
    'green': ui.Color(0xFF008000),
    'lime': ui.Color(0xFF00FF00),
    'blue': ui.Color(0xFF0000FF),
    'yellow': ui.Color(0xFFFFFF00),
    'cyan': ui.Color(0xFF00FFFF),
    'aqua': ui.Color(0xFF00FFFF),
    'magenta': ui.Color(0xFFFF00FF),
    'fuchsia': ui.Color(0xFFFF00FF),
    'silver': ui.Color(0xFFC0C0C0),
    'gray': ui.Color(0xFF808080),
    'grey': ui.Color(0xFF808080),
    'maroon': ui.Color(0xFF800000),
    'olive': ui.Color(0xFF808000),
    'purple': ui.Color(0xFF800080),
    'teal': ui.Color(0xFF008080),
    'navy': ui.Color(0xFF000080),
    'orange': ui.Color(0xFFFFA500),
    'gold': ui.Color(0xFFFFD700),
    'pink': ui.Color(0xFFFFC0CB),
    'hotpink': ui.Color(0xFFFF69B4),
    'deeppink': ui.Color(0xFFFF1493),
    'coral': ui.Color(0xFFFF7F50),
    'tomato': ui.Color(0xFFFF6347),
    'crimson': ui.Color(0xFFDC143C),
    'indigo': ui.Color(0xFF4B0082),
    'violet': ui.Color(0xFFEE82EE),
    'plum': ui.Color(0xFFDDA0DD),
    'orchid': ui.Color(0xFFDA70D6),
    'skyblue': ui.Color(0xFF87CEEB),
    'deepskyblue': ui.Color(0xFF00BFFF),
    'dodgerblue': ui.Color(0xFF1E90FF),
    'royalblue': ui.Color(0xFF4169E1),
    'steelblue': ui.Color(0xFF4682B4),
    'turquoise': ui.Color(0xFF40E0D0),
    'mediumturquoise': ui.Color(0xFF48D1CC),
    'darkturquoise': ui.Color(0xFF00CED1),
    'aquamarine': ui.Color(0xFF7FFFD4),
    'springgreen': ui.Color(0xFF00FF7F),
    'mediumseagreen': ui.Color(0xFF3CB371),
    'seagreen': ui.Color(0xFF2E8B57),
    'forestgreen': ui.Color(0xFF228B22),
    'darkgreen': ui.Color(0xFF006400),
    'yellowgreen': ui.Color(0xFF9ACD32),
    'chartreuse': ui.Color(0xFF7FFF00),
    'khaki': ui.Color(0xFFF0E68C),
    'salmon': ui.Color(0xFFFA8072),
    'darkorange': ui.Color(0xFFFF8C00),
    'orangered': ui.Color(0xFFFF4500),
    'firebrick': ui.Color(0xFFB22222),
    'darkred': ui.Color(0xFF8B0000),
    'saddlebrown': ui.Color(0xFF8B4513),
    'sienna': ui.Color(0xFFA0522D),
    'chocolate': ui.Color(0xFFD2691E),
    'peru': ui.Color(0xFFCD853F),
    'tan': ui.Color(0xFFD2B48C),
    'wheat': ui.Color(0xFFF5DEB3),
    'beige': ui.Color(0xFFF5F5DC),
    'ivory': ui.Color(0xFFFFFFF0),
    'aliceblue': ui.Color(0xFFF0F8FF),
    'ghostwhite': ui.Color(0xFFF8F8FF),
    'whitesmoke': ui.Color(0xFFF5F5F5),
    'gainsboro': ui.Color(0xFFDCDCDC),
    'lightgray': ui.Color(0xFFD3D3D3),
    'lightgrey': ui.Color(0xFFD3D3D3),
    'darkgray': ui.Color(0xFFA9A9A9),
    'darkgrey': ui.Color(0xFFA9A9A9),
    'dimgray': ui.Color(0xFF696969),
    'dimgrey': ui.Color(0xFF696969),
    'slategray': ui.Color(0xFF708090),
    'slategrey': ui.Color(0xFF708090),
    'darkslategray': ui.Color(0xFF2F4F4F),
    'darkslategrey': ui.Color(0xFF2F4F4F),
    'midnightblue': ui.Color(0xFF191970),
    'cornflowerblue': ui.Color(0xFF6495ED),
    'slateblue': ui.Color(0xFF6A5ACD),
    'darkslateblue': ui.Color(0xFF483D8B),
    'mediumslateblue': ui.Color(0xFF7B68EE),
    'mediumpurple': ui.Color(0xFF9370DB),
    'blueviolet': ui.Color(0xFF8A2BE2),
    'darkviolet': ui.Color(0xFF9400D3),
    'darkorchid': ui.Color(0xFF9932CC),
    'darkmagenta': ui.Color(0xFF8B008B),
  };
}
