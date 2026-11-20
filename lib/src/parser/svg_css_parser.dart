import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Cubic;

import '../animation/svg_timeline.dart';
import '../model/svg_css_clip_shape.dart';
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

        final (normalDecls, importantDecls) = parseDeclarationsSplit(declText);
        final selectorTokens = _splitTopLevelComma(selectorGroup);
        for (final rawSel in selectorTokens) {
          final sel = SvgCssSelectorParser.parse(rawSel.trim());
          if (sel != null) {
            rules.add(
              SvgCssRule(
                selector: sel,
                declarations: normalDecls,
                importantDeclarations: importantDecls,
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

  static List<SvgCssKeyframeStop> _parseKeyframesBody(String body) {
    final stopsByOffset = <double, Map<String, String>>{};
    final easingByOffset = <double, Cubic?>{};
    final stepEasingByOffset = <double, SvgStepEasing?>{};

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
      Cubic? cubicEasing;
      SvgStepEasing? stepEasing;
      final tfRaw = decls.remove('animation-timing-function');
      if (tfRaw != null) {
        stepEasing = SvgStepEasing.parse(tfRaw);
        if (stepEasing == null) {
          cubicEasing = parseTimingCubic(tfRaw);
        }
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
          if (cubicEasing != null) {
            easingByOffset[offset] = cubicEasing;
          }
          if (stepEasing != null) {
            stepEasingByOffset[offset] = stepEasing;
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
          stepEasingToNext: stepEasingByOffset[off],
        ),
    ];
  }

  /// Parses semicolon-separated CSS declarations (`prop: value; ...`) into a
  /// single merged Map (preserving `--custom-property` case sensitivity).
  static Map<String, String> parseDeclarationsMap(String inlineStyle) {
    final (normal, important) = parseDeclarationsSplit(inlineStyle);
    if (important.isEmpty) return normal;
    return <String, String>{...normal, ...important};
  }

  /// Parses semicolon-separated CSS declarations into `(normal, important)` maps
  /// so W3C `!important` cascade precedence is honored.
  static (Map<String, String>, Map<String, String>) parseDeclarationsSplit(
    String inlineStyle,
  ) {
    final normal = <String, String>{};
    final important = <String, String>{};
    final parts = inlineStyle.split(';');
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      if (part.isEmpty) continue;
      final colonIdx = part.indexOf(':');
      if (colonIdx <= 0) continue;
      final rawKey = part.substring(0, colonIdx).trim();
      // CSS custom properties (`--*`) are case-sensitive per W3C spec
      final key = rawKey.startsWith('--') ? rawKey : rawKey.toLowerCase();
      var val = part.substring(colonIdx + 1).trim();
      bool isImportant = false;
      final lowerVal = val.toLowerCase();
      if (lowerVal.endsWith('!important')) {
        isImportant = true;
        val = val.substring(0, val.length - 10).trim();
      }
      if (isImportant) {
        important[key] = val;
      } else {
        normal[key] = val;
      }
    }
    return (normal, important);
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
      final playStates = _splitList(decls['animation-play-state']);

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
          final parsedStep = SvgStepEasing.parse(fStr);
          if (parsedStep != null) {
            cfg.stepEasing = parsedStep;
            cfg.isDiscreteSteps = false;
          } else if (fStr.toLowerCase().startsWith('steps')) {
            cfg.isDiscreteSteps = true;
          } else {
            cfg.timingCurve = parseTimingCubic(fStr) ?? cfg.timingCurve;
          }
        }
        if (playStates.isNotEmpty) {
          final ps = playStates[i % playStates.length].toLowerCase();
          if (ps == 'paused') {
            cfg.isPaused = true;
          } else if (ps == 'running') {
            cfg.isPaused = false;
          }
        }
        if (i >= outAnimations.length) {
          outAnimations.add(cfg);
        }
      }
    } else if (outAnimations.isNotEmpty) {
      // Standalone longhand overrides after `animation:` shorthand or higher-specificity rules
      final playStates = _splitList(decls['animation-play-state']);
      if (playStates.isNotEmpty) {
        for (int i = 0; i < outAnimations.length; i++) {
          final ps = playStates[i % playStates.length].toLowerCase();
          if (ps == 'paused') {
            outAnimations[i].isPaused = true;
          } else if (ps == 'running') {
            outAnimations[i].isPaused = false;
          }
        }
      }
      final delays = _splitList(decls['animation-delay']);
      if (delays.isNotEmpty) {
        for (int i = 0; i < outAnimations.length; i++) {
          outAnimations[i].delayUs =
              parseClockMicroseconds(delays[i % delays.length]) ??
              outAnimations[i].delayUs;
        }
      }
      final funcs = _splitTopLevelComma(
        decls['animation-timing-function'] ?? '',
      );
      if (funcs.isNotEmpty && funcs.first.isNotEmpty) {
        for (int i = 0; i < outAnimations.length; i++) {
          final fStr = funcs[i % funcs.length];
          final parsedStep = SvgStepEasing.parse(fStr);
          if (parsedStep != null) {
            outAnimations[i].stepEasing = parsedStep;
            outAnimations[i].isDiscreteSteps = false;
          } else {
            outAnimations[i].timingCurve =
                parseTimingCubic(fStr) ?? outAnimations[i].timingCurve;
          }
        }
      }
    }
  }

  /// Applies a single presentation attribute or CSS property to [style].
  static void applySingleAttribute(String key, String rawVal, SvgStyle style) {
    final trimmedRaw = rawVal.trim();
    if (trimmedRaw.isEmpty) return;
    if (key.startsWith('--')) {
      style.customProperties[key] = trimmedRaw;
      return;
    }
    final val = trimmedRaw.contains('var(')
        ? SvgCssVariables.resolve(trimmedRaw, style.customProperties).trim()
        : trimmedRaw;
    if (val.isEmpty) return;

    switch (key) {
      case 'color':
        style.baseColor = parseColor(val);
      case 'fill':
        style.baseFill = parsePaintServer(val);
      case 'stroke':
        style.baseStroke = parsePaintServer(val);
      case 'shape-rendering':
        final sr = val.toLowerCase();
        if (sr == 'crispedges' || sr == 'optimizespeed') {
          style.baseShapeRenderingCrisp = true;
        } else if (sr == 'auto' || sr == 'geometricprecision') {
          style.baseShapeRenderingCrisp = false;
        }
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
        if (val == 'none') {
          style.filterId = null;
          style.baseBlurSigma = 0.0;
          style.baseCssFilterPrimitives = null;
        } else {
          final fId = extractUrlId(val);
          if (fId != null && fId.isNotEmpty) {
            style.filterId = fId;
          }
          final chain = SvgCssValueParser.parseCssFilterChain(val);
          if (chain.length == 1 && chain.first is SvgFeGaussianBlur) {
            final blur = chain.first as SvgFeGaussianBlur;
            style.baseBlurSigma = blur.sigmaX;
            style.baseCssFilterPrimitives = null;
          } else if (chain.isNotEmpty) {
            style.baseCssFilterPrimitives = chain;
          }
        }
      case 'transform-origin':
        style.baseTransformOrigin = parseTransformOrigin(val);
      case 'transform-box':
        final tb = val.toLowerCase();
        if (tb == 'view-box') {
          style.baseTransformBox = SvgTransformBox.viewBox;
        } else if (tb == 'fill-box' ||
            tb == 'border-box' ||
            tb == 'content-box') {
          style.baseTransformBox = SvgTransformBox.fillBox;
        }
      case 'translate':
        if (val.toLowerCase() == 'none') {
          style.baseCssTranslateOp = null;
        } else {
          final nums = parseNumberList(val);
          if (nums.isNotEmpty) {
            style.baseCssTranslateOp = SvgTransformOp.translate(
              nums[0],
              nums.length > 1 ? nums[1] : 0.0,
            );
          }
        }
      case 'rotate':
        if (val.toLowerCase() == 'none') {
          style.baseCssRotateOp = null;
        } else {
          final deg = parseAngleOrLength(val);
          if (deg != null) {
            style.baseCssRotateOp = SvgTransformOp.rotateZ(deg);
          }
        }
      case 'scale':
        if (val.toLowerCase() == 'none') {
          style.baseCssScaleOp = null;
        } else {
          final nums = parseNumberList(val);
          if (nums.isNotEmpty) {
            style.baseCssScaleOp = SvgTransformOp.scale(
              nums[0],
              nums.length > 1 ? nums[1] : nums[0],
            );
          }
        }
      case 'transform':
        final ops = parseTransformOps(val);
        if (ops.isNotEmpty) {
          style.cssBaseTransformOps = ops;
        }
      case 'x':
      case 'y':
      case 'width':
      case 'height':
      case 'cx':
      case 'cy':
      case 'r':
      case 'rx':
      case 'ry':
      case 'd':
        (style.cssGeometryProps ??= <String, String>{})[key] = val;
      case 'clip-path':
        if (val.toLowerCase() == 'none') {
          style.clipPathId = null;
          style.cssClipShape = null;
        } else {
          final cId = extractUrlId(val);
          if (cId != null && cId.isNotEmpty) {
            style.clipPathId = cId;
            style.cssClipShape = null;
          } else {
            final shape = SvgCssClipShapeParser.parse(val);
            if (shape != null) {
              style.cssClipShape = shape;
              style.clipPathId = null;
            }
          }
        }
      case 'vector-effect':
        final ve = val.toLowerCase();
        if (ve == 'non-scaling-stroke') {
          style.baseNonScalingStroke = true;
        } else if (ve == 'none') {
          style.baseNonScalingStroke = false;
        }
      case 'mask':
        style.maskId = val == 'none' ? null : extractUrlId(val);
      case 'marker':
        final markerId = val == 'none' ? null : extractUrlId(val);
        style.baseMarkerStartId = markerId;
        style.baseMarkerMidId = markerId;
        style.baseMarkerEndId = markerId;
      case 'marker-start':
        style.baseMarkerStartId = val == 'none' ? null : extractUrlId(val);
      case 'marker-mid':
        style.baseMarkerMidId = val == 'none' ? null : extractUrlId(val);
      case 'marker-end':
        style.baseMarkerEndId = val == 'none' ? null : extractUrlId(val);
      case 'display':
        style.baseDisplayNone = val == 'none';
        style.displayNone = style.baseDisplayNone;
      case 'visibility':
        style.baseVisibilityHidden = val == 'hidden' || val == 'collapse';
        style.visibilityHidden = style.baseVisibilityHidden!;
      case 'overflow':
        final lower = val.toLowerCase();
        if (lower == 'visible') {
          style.baseOverflowVisible = true;
        } else if (lower == 'hidden' || lower == 'scroll' || lower == 'auto') {
          style.baseOverflowVisible = false;
        }
      case 'mix-blend-mode':
        final bm = SvgCssValueParser.parseBlendMode(val);
        if (bm != null) style.baseMixBlendMode = bm;
      case 'isolation':
        final iso = val.toLowerCase();
        if (iso == 'isolate') {
          style.baseIsolationIsolate = true;
        } else if (iso == 'auto') {
          style.baseIsolationIsolate = false;
        }
      case 'font':
        SvgCssValueParser.applyFontShorthand(val, style);
      case 'font-family':
        final (fam, fb) = SvgCssValueParser.parseFontFamily(val);
        if (fam != null) {
          style.baseFontFamily = fam;
          style.baseFontFamilyFallback = fb;
        }
      case 'font-size':
        final fs = SvgCssValueParser.parseFontSize(val);
        if (fs != null) style.baseFontSizeSpec = fs;
      case 'font-weight':
        final fw = SvgCssValueParser.parseFontWeight(val);
        if (fw != null) style.baseFontWeight = fw;
      case 'font-style':
        final fst = SvgCssValueParser.parseFontStyle(val);
        if (fst != null) style.baseFontStyle = fst;
      case 'font-variant':
        final lower = val.toLowerCase();
        if (lower == 'small-caps') {
          style.baseFontVariantSmallCaps = true;
        } else if (lower == 'normal') {
          style.baseFontVariantSmallCaps = false;
        }
      case 'text-anchor':
        final anchor = SvgCssValueParser.parseTextAnchor(val);
        if (anchor != null) style.baseTextAnchor = anchor;
      case 'dominant-baseline':
        final db = SvgCssValueParser.parseDominantBaseline(val);
        if (db != null) style.baseDominantBaseline = db;
      case 'alignment-baseline':
        final ab = SvgCssValueParser.parseDominantBaseline(val);
        if (ab != null) style.baseAlignmentBaseline = ab;
      case 'baseline-shift':
        final bs = SvgCssValueParser.parseBaselineShift(val);
        if (bs != null) style.baseBaselineShift = bs;
      case 'letter-spacing':
        if (val.toLowerCase() == 'normal') {
          style.baseLetterSpacingSpec = const SvgTextLength(0.0);
        } else {
          final ls = SvgCssValueParser.parseTextLength(val);
          if (ls != null) style.baseLetterSpacingSpec = ls;
        }
      case 'word-spacing':
        if (val.toLowerCase() == 'normal') {
          style.baseWordSpacingSpec = const SvgTextLength(0.0);
        } else {
          final ws = SvgCssValueParser.parseTextLength(val);
          if (ws != null) style.baseWordSpacingSpec = ws;
        }
      case 'text-decoration':
        final td = SvgCssValueParser.parseTextDecoration(val);
        if (td != null) style.baseTextDecoration = td;
      case 'direction':
        final lower = val.toLowerCase();
        if (lower == 'rtl') {
          style.baseTextDirection = ui.TextDirection.rtl;
        } else if (lower == 'ltr') {
          style.baseTextDirection = ui.TextDirection.ltr;
        }
      case 'xml:space':
      case 'space':
        if (val == 'preserve') {
          style.baseWhiteSpace = SvgWhiteSpace.preserve;
        } else if (val == 'default') {
          style.baseWhiteSpace = SvgWhiteSpace.normal;
        }
      case 'white-space':
        final lower = val.toLowerCase();
        if (lower == 'pre' || lower == 'pre-wrap' || lower == 'break-spaces') {
          style.baseWhiteSpace = SvgWhiteSpace.preserve;
        } else if (lower == 'normal' ||
            lower == 'nowrap' ||
            lower == 'pre-line') {
          style.baseWhiteSpace = SvgWhiteSpace.normal;
        }
      case 'text-transform':
        final tt = SvgCssValueParser.parseTextTransform(val);
        if (tt != null) style.baseTextTransform = tt;
      case 'writing-mode':
        final wm = SvgCssValueParser.parseWritingMode(val);
        if (wm != null) style.baseWritingMode = wm;
      case 'paint-order':
        final po = SvgCssValueParser.parsePaintOrder(val);
        if (po != null) style.basePaintOrder = po;
        final layers = SvgCssValueParser.parsePaintOrderLayers(val);
        if (layers != null) style.basePaintOrderLayers = layers;
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
    SvgStepEasing? stepEasing;
    bool isDiscrete = false;
    bool isPaused = false;

    for (final tok in tokens) {
      final lower = tok.toLowerCase();
      if (lower == 'none') continue;

      if (lower == 'paused') {
        isPaused = true;
        continue;
      }
      if (lower == 'running') {
        isPaused = false;
        continue;
      }

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

      final parsedStep = SvgStepEasing.parse(lower);
      if (parsedStep != null) {
        stepEasing = parsedStep;
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
      stepEasing: stepEasing,
      isDiscreteSteps: isDiscrete,
      isPaused: isPaused,
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
