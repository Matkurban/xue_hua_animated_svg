import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Cubic;

import '../animation/svg_timeline.dart';
import '../model/svg_node.dart';
import '../model/svg_style.dart';
import '../model/svg_transform.dart';
import 'svg_css_keyframe_compiler.dart';
import 'svg_css_models.dart';
import 'svg_css_value_parser.dart';

export 'svg_css_keyframe_compiler.dart';
export 'svg_css_models.dart';
export 'svg_css_value_parser.dart';

/// Precompiles `<style>` blocks, inline `style="..."` attributes, `@keyframes`,
/// colors, numbers, transforms, and `transform-origin` during the XML build phase.
abstract final class SvgCssParser {
  // Standard easing curves
  static const Cubic ease = SvgCssValueParser.ease;
  static const Cubic easeIn = SvgCssValueParser.easeIn;
  static const Cubic easeOut = SvgCssValueParser.easeOut;
  static const Cubic easeInOut = SvgCssValueParser.easeInOut;

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
        final blur = SvgCssValueParser.parseBlurFilter(val);
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
  }) => SvgCssKeyframeCompiler.compileKeyframesForElement(
    target: target,
    config: config,
    stops: stops,
    documentViewBox: documentViewBox,
  );

  /// Normalizes a list of `stroke-dasharray` keyframe arrays to their least
  /// common multiple (LCM) length so they can be interpolated element-by-element.
  static List<Float64List> normalizeDashArrayKeyframes(
    List<Float64List> arrays,
  ) => SvgCssValueParser.normalizeDashArrayKeyframes(arrays);

  /// Parses `transform-origin` supporting pixel lengths, percentages (`50% 50%`),
  /// and keywords (`center`, `left`, `right`, `top`, `bottom`).
  static SvgTransformOrigin parseTransformOrigin(String raw) =>
      SvgCssValueParser.parseTransformOrigin(raw);

  /// Parses an SVG or CSS `transform` string into a list of [SvgTransformOp].
  static List<SvgTransformOp> parseTransformOps(String raw) =>
      SvgCssValueParser.parseTransformOps(raw);

  /// Parses an angle (`deg`, `rad`, `turn`, `grad`) or length into degrees / pixels.
  static double? parseAngleOrLength(String raw) =>
      SvgCssValueParser.parseAngleOrLength(raw);

  /// Parses an SVG/CSS clock duration (`500ms`, `2.5s`, `02:30`, `1.5h`) into microseconds.
  static int? parseClockMicroseconds(String? raw) =>
      SvgCssValueParser.parseClockMicroseconds(raw);

  /// Parses a CSS timing function (`ease`, `linear`, `ease-in`, `ease-out`,
  /// `ease-in-out`, `cubic-bezier(x1, y1, x2, y2)`) into a Flutter [Cubic].
  static Cubic? parseTimingCubic(String raw) =>
      SvgCssValueParser.parseTimingCubic(raw);

  /// Extracts `id` from `url(#id)`, or from a bare `#id` that is not a color.
  static String? extractUrlId(String raw) =>
      SvgCssValueParser.extractUrlId(raw);

  /// Parses an SVG `fill` or `stroke` value into an [SvgPaintServer].
  static SvgPaintServer? parsePaintServer(String raw) =>
      SvgCssValueParser.parsePaintServer(raw);

  /// Parses hex (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`), `rgb()`, `rgba()`,
  /// and standard SVG named colors into a [ui.Color] at parse time.
  static ui.Color? parseColor(String? raw) => SvgCssValueParser.parseColor(raw);

  /// Parses a number or percentage (`50%` -> `0.5`).
  static double? parseNumberOrPercent(String? raw, {double? referenceExtent}) =>
      SvgCssValueParser.parseNumberOrPercent(
        raw,
        referenceExtent: referenceExtent,
      );

  /// Parses an SVG length (`px`, `pt`, `pc`, `mm`, `cm`, `in`, or unitless number).
  static double? parseLength(String? raw) => SvgCssValueParser.parseLength(raw);

  /// Parses a whitespace- or comma-separated list of numbers/lengths into a [Float64List].
  static Float64List parseNumberList(String? raw) =>
      SvgCssValueParser.parseNumberList(raw);

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
}
