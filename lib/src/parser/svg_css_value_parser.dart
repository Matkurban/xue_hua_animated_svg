import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Cubic;

import '../model/svg_filter_node.dart';
import '../model/svg_style.dart';
import '../model/svg_text_style.dart';
import '../model/svg_transform.dart';
import 'svg_named_colors.dart';

/// Stateless value parsers for CSS / SVG lengths, angles, colors, paint servers,
/// transforms, and clock values.
abstract final class SvgCssValueParser {
  // Standard easing curves
  static const Cubic ease = Cubic(0.25, 0.1, 0.25, 1.0);
  static const Cubic easeIn = Cubic(0.42, 0.0, 1.0, 1.0);
  static const Cubic easeOut = Cubic(0.0, 0.0, 0.58, 1.0);
  static const Cubic easeInOut = Cubic(0.42, 0.0, 0.58, 1.0);

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

  /// Parses `blur(...)` filter value into sigma pixels.
  static double? parseBlurFilter(String val) {
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
  /// Solid colors (hex, `rgb()` / `rgba()`, `hsl()` / `hsla()`, `hwb()`, named)
  /// are resolved before `url(#id)` paint servers. Bare `#rrggbb` is never a
  /// gradient id. `currentColor`, `none`, and `transparent` are handled cleanly.
  static SvgPaintServer? parsePaintServer(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    if (s.toLowerCase() == 'currentcolor') {
      return SvgPaintServer.currentColor;
    }

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

  /// Parses hex (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`), `rgb()` / `rgba()`,
  /// `hsl()` / `hsla()`, `hwb()`, and standard SVG named colors into a [ui.Color].
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

    if (s.startsWith('hsl(') || s.startsWith('hsla(')) {
      return _parseHslColor(s);
    }

    if (s.startsWith('hwb(')) {
      return _parseHwbColor(s);
    }

    return svgNamedColors[s];
  }

  /// Parses CSS Color 4 `hsl()` / `hsla()` (both comma and space/`/` syntax,
  /// supporting `deg`, `rad`, `grad`, `turn` hue units).
  static ui.Color? _parseHslColor(String s) {
    final open = s.indexOf('(');
    final close = s.lastIndexOf(')');
    if (open == -1 || close <= open) return null;
    final parts = s
        .substring(open + 1, close)
        .split(RegExp(r'[\s,/]+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length < 3) return null;

    final rawHue = parseAngleOrLength(parts[0]);
    final rawSat = _parseUnitPercentOrNumber(parts[1]);
    final rawLight = _parseUnitPercentOrNumber(parts[2]);
    if (rawHue == null || rawSat == null || rawLight == null) return null;

    final h = ((rawHue % 360.0) + 360.0) % 360.0;
    final sat = rawSat.clamp(0.0, 1.0);
    final light = rawLight.clamp(0.0, 1.0);

    // W3C CSS Color 4 §7.1 HSL to sRGB conversion
    final c = (1.0 - (2.0 * light - 1.0).abs()) * sat;
    final x = c * (1.0 - (((h / 60.0) % 2.0) - 1.0).abs());
    final m = light - c * 0.5;

    final double r1, g1, b1;
    if (h < 60.0) {
      r1 = c;
      g1 = x;
      b1 = 0.0;
    } else if (h < 120.0) {
      r1 = x;
      g1 = c;
      b1 = 0.0;
    } else if (h < 180.0) {
      r1 = 0.0;
      g1 = c;
      b1 = x;
    } else if (h < 240.0) {
      r1 = 0.0;
      g1 = x;
      b1 = c;
    } else if (h < 300.0) {
      r1 = x;
      g1 = 0.0;
      b1 = c;
    } else {
      r1 = c;
      g1 = 0.0;
      b1 = x;
    }

    final r = ((r1 + m) * 255.0).round().clamp(0, 255);
    final g = ((g1 + m) * 255.0).round().clamp(0, 255);
    final b = ((b1 + m) * 255.0).round().clamp(0, 255);
    int a = 255;
    if (parts.length >= 4) {
      final aRatio = parseNumberOrPercent(parts[3]) ?? 1.0;
      a = (aRatio.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
    }
    return ui.Color.fromARGB(a, r, g, b);
  }

  /// Parses CSS Color 4 `hwb(H W% B% [/ A])` into sRGB.
  static ui.Color? _parseHwbColor(String s) {
    final open = s.indexOf('(');
    final close = s.lastIndexOf(')');
    if (open == -1 || close <= open) return null;
    final parts = s
        .substring(open + 1, close)
        .split(RegExp(r'[\s,/]+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length < 3) return null;

    final rawHue = parseAngleOrLength(parts[0]);
    final rawWhite = _parseUnitPercentOrNumber(parts[1]);
    final rawBlack = _parseUnitPercentOrNumber(parts[2]);
    if (rawHue == null || rawWhite == null || rawBlack == null) return null;

    final h = ((rawHue % 360.0) + 360.0) % 360.0;
    final w = rawWhite.clamp(0.0, 1.0);
    final bl = rawBlack.clamp(0.0, 1.0);
    int a = 255;
    if (parts.length >= 4) {
      final aRatio = parseNumberOrPercent(parts[3]) ?? 1.0;
      a = (aRatio.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
    }
    if (w + bl >= 1.0) {
      final gray = ((w / (w + bl)) * 255.0).round().clamp(0, 255);
      return ui.Color.fromARGB(a, gray, gray, gray);
    }

    final x = 1.0 - (((h / 60.0) % 2.0) - 1.0).abs();
    final double r0, g0, b0;
    if (h < 60.0) {
      r0 = 1.0;
      g0 = x;
      b0 = 0.0;
    } else if (h < 120.0) {
      r0 = x;
      g0 = 1.0;
      b0 = 0.0;
    } else if (h < 180.0) {
      r0 = 0.0;
      g0 = 1.0;
      b0 = x;
    } else if (h < 240.0) {
      r0 = 0.0;
      g0 = x;
      b0 = 1.0;
    } else if (h < 300.0) {
      r0 = x;
      g0 = 0.0;
      b0 = 1.0;
    } else {
      r0 = 1.0;
      g0 = 0.0;
      b0 = x;
    }

    final factor = 1.0 - w - bl;
    final r = ((r0 * factor + w) * 255.0).round().clamp(0, 255);
    final g = ((g0 * factor + w) * 255.0).round().clamp(0, 255);
    final b = ((b0 * factor + w) * 255.0).round().clamp(0, 255);
    return ui.Color.fromARGB(a, r, g, b);
  }

  /// Parses percentage (`75%` -> `0.75`) or CSS Color 4 0..100 number (`75` -> `0.75`).
  static double? _parseUnitPercentOrNumber(String raw) {
    final t = raw.trim();
    if (t.endsWith('%')) {
      final v = double.tryParse(t.substring(0, t.length - 1).trim());
      return v != null ? v / 100.0 : null;
    }
    final v = double.tryParse(t);
    return v != null ? v / 100.0 : null;
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

  /// Parses an SVG text length (`px`, `pt`, `pc`, `mm`, `cm`, `in`, `em`, `rem`, `%`, or unitless).
  static SvgTextLength? parseTextLength(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty || s == 'normal' || s == 'none' || s == 'auto') return null;
    if (s.endsWith('rem')) {
      final v = double.tryParse(s.substring(0, s.length - 3).trim());
      return v != null ? SvgTextLength(v, SvgTextLengthUnit.rem) : null;
    }
    if (s.endsWith('em')) {
      final v = double.tryParse(s.substring(0, s.length - 2).trim());
      return v != null ? SvgTextLength(v, SvgTextLengthUnit.em) : null;
    }
    if (s.endsWith('%')) {
      final v = double.tryParse(s.substring(0, s.length - 1).trim());
      return v != null
          ? SvgTextLength(v / 100.0, SvgTextLengthUnit.percent)
          : null;
    }
    final px = parseLength(s);
    return px != null ? SvgTextLength(px, SvgTextLengthUnit.pixels) : null;
  }

  /// Parses a whitespace- or comma-separated list of [SvgTextLength] values (`x`, `y`, `dx`, `dy`).
  static List<SvgTextLength> parseTextLengthList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final tokens = raw
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((e) => e.isNotEmpty);
    final result = <SvgTextLength>[];
    for (final tok in tokens) {
      final parsed = parseTextLength(tok);
      if (parsed != null) result.add(parsed);
    }
    return result;
  }

  /// Parses `font-size` supporting absolute/relative lengths, percentages, and CSS keywords.
  static SvgTextLength? parseFontSize(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    switch (s) {
      case 'xx-small':
        return const SvgTextLength(9.0);
      case 'x-small':
        return const SvgTextLength(10.0);
      case 'small':
        return const SvgTextLength(13.0);
      case 'medium':
        return const SvgTextLength(16.0);
      case 'large':
        return const SvgTextLength(18.0);
      case 'x-large':
        return const SvgTextLength(24.0);
      case 'xx-large':
        return const SvgTextLength(32.0);
      case 'xxx-large':
        return const SvgTextLength(48.0);
      case 'smaller':
        return const SvgTextLength(0.8333, SvgTextLengthUnit.em);
      case 'larger':
        return const SvgTextLength(1.2, SvgTextLengthUnit.em);
      default:
        return parseTextLength(s);
    }
  }

  /// Parses `font-family` into a primary family name and cross-platform fallback list.
  static (String?, List<String>?) parseFontFamily(String? raw) {
    if (raw == null || raw.trim().isEmpty) return (null, null);
    final parts = raw.split(',');
    final families = <String>[];
    for (final part in parts) {
      var name = part.trim();
      if (name.length >= 2 &&
          ((name.startsWith('"') && name.endsWith('"')) ||
              (name.startsWith("'") && name.endsWith("'")))) {
        name = name.substring(1, name.length - 1).trim();
      }
      if (name.isEmpty) continue;
      final lower = name.toLowerCase();
      switch (lower) {
        case 'monospace':
          families.addAll(const [
            'monospace',
            'Menlo',
            'Courier New',
            'Courier',
          ]);
        case 'serif':
          families.addAll(const ['serif', 'Georgia', 'Times New Roman']);
        case 'sans-serif':
          families.addAll(const [
            'sans-serif',
            'Helvetica Neue',
            'Arial',
            'Roboto',
          ]);
        case 'cursive':
          families.addAll(const ['cursive', 'Apple Chancery', 'Comic Sans MS']);
        case 'fantasy':
          families.addAll(const ['fantasy', 'Impact', 'Papyrus']);
        case 'system-ui':
          families.addAll(const [
            '.SF Pro Text',
            'Segoe UI',
            'Roboto',
            'sans-serif',
          ]);
        default:
          families.add(name);
      }
    }
    if (families.isEmpty) return (null, null);
    final seen = <String>{};
    final deduped = <String>[];
    for (final f in families) {
      if (seen.add(f)) deduped.add(f);
    }
    return (
      deduped.first,
      deduped.length > 1 ? List<String>.unmodifiable(deduped.sublist(1)) : null,
    );
  }

  /// Parses `font-weight` (`normal`, `bold`, `bolder`, `lighter`, `100`..`900`).
  static ui.FontWeight? parseFontWeight(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'normal':
        return ui.FontWeight.w400;
      case 'bold':
        return ui.FontWeight.w700;
      case 'bolder':
        return ui.FontWeight.w700;
      case 'lighter':
        return ui.FontWeight.w300;
      default:
        final n = double.tryParse(s);
        if (n == null) return null;
        if (n < 150) return ui.FontWeight.w100;
        if (n < 250) return ui.FontWeight.w200;
        if (n < 350) return ui.FontWeight.w300;
        if (n < 450) return ui.FontWeight.w400;
        if (n < 550) return ui.FontWeight.w500;
        if (n < 650) return ui.FontWeight.w600;
        if (n < 750) return ui.FontWeight.w700;
        if (n < 850) return ui.FontWeight.w800;
        return ui.FontWeight.w900;
    }
  }

  /// Parses `font-style` (`normal`, `italic`, `oblique`).
  static ui.FontStyle? parseFontStyle(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s == 'italic' || s.startsWith('oblique')) {
      return ui.FontStyle.italic;
    }
    if (s == 'normal') return ui.FontStyle.normal;
    return null;
  }

  /// Parses CSS `font` shorthand (e.g., `italic bold 30px/1.2 'Helvetica', sans-serif`).
  static void applyFontShorthand(String raw, SvgStyle style) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    final tokens = <String>[];
    final buf = StringBuffer();
    bool inSingle = false;
    bool inDouble = false;
    for (int i = 0; i < trimmed.length; i++) {
      final c = trimmed.codeUnitAt(i);
      if (c == 0x27 && !inDouble) {
        inSingle = !inSingle;
        buf.writeCharCode(c);
      } else if (c == 0x22 && !inSingle) {
        inDouble = !inDouble;
        buf.writeCharCode(c);
      } else if ((c == 0x20 || c == 0x09) && !inSingle && !inDouble) {
        if (buf.isNotEmpty) {
          tokens.add(buf.toString());
          buf.clear();
        }
      } else {
        buf.writeCharCode(c);
      }
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());

    int sizeIdx = -1;
    for (int i = 0; i < tokens.length; i++) {
      final tok = tokens[i];
      final slashIdx = tok.indexOf('/');
      final sizePart = slashIdx != -1 ? tok.substring(0, slashIdx) : tok;
      final lower = sizePart.toLowerCase();
      final isWeightNumber =
          RegExp(r'^[1-9]00$').hasMatch(lower) && i + 1 < tokens.length;
      if (isWeightNumber) continue;
      final parsedSize = parseFontSize(sizePart);
      if (parsedSize != null) {
        style.baseFontSizeSpec = parsedSize;
        sizeIdx = i;
        break;
      }
    }

    if (sizeIdx == -1) return;

    for (int i = 0; i < sizeIdx; i++) {
      final lower = tokens[i].toLowerCase();
      final fStyle = parseFontStyle(lower);
      if (fStyle != null) {
        style.baseFontStyle = fStyle;
        continue;
      }
      if (lower == 'small-caps') {
        style.baseFontVariantSmallCaps = true;
        continue;
      }
      final fWeight = parseFontWeight(lower);
      if (fWeight != null) {
        style.baseFontWeight = fWeight;
      }
    }

    if (sizeIdx + 1 < tokens.length) {
      final familyStr = tokens.sublist(sizeIdx + 1).join(' ');
      final (fam, fb) = parseFontFamily(familyStr);
      if (fam != null) {
        style.baseFontFamily = fam;
        style.baseFontFamilyFallback = fb;
      }
    }
  }

  /// Parses `text-anchor` (`start`, `middle`, `end`).
  static SvgTextAnchor? parseTextAnchor(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'start':
        return SvgTextAnchor.start;
      case 'middle':
        return SvgTextAnchor.middle;
      case 'end':
        return SvgTextAnchor.end;
      default:
        return null;
    }
  }

  /// Parses `dominant-baseline` or `alignment-baseline`.
  static SvgDominantBaseline? parseDominantBaseline(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'auto':
      case 'use-script':
      case 'no-change':
      case 'reset-size':
      case 'baseline':
        return SvgDominantBaseline.auto;
      case 'alphabetic':
        return SvgDominantBaseline.alphabetic;
      case 'ideographic':
        return SvgDominantBaseline.ideographic;
      case 'hanging':
        return SvgDominantBaseline.hanging;
      case 'mathematical':
        return SvgDominantBaseline.mathematical;
      case 'central':
        return SvgDominantBaseline.central;
      case 'middle':
        return SvgDominantBaseline.middle;
      case 'text-before-edge':
      case 'before-edge':
      case 'text-top':
        return SvgDominantBaseline.textBeforeEdge;
      case 'text-after-edge':
      case 'after-edge':
      case 'text-bottom':
        return SvgDominantBaseline.textAfterEdge;
      default:
        return null;
    }
  }

  /// Parses `baseline-shift` (`baseline`, `sub`, `super`, `<length>`, `<percentage>`).
  static SvgBaselineShift? parseBaselineShift(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'baseline':
      case '0':
        return SvgBaselineShift.baseline;
      case 'sub':
        return SvgBaselineShift.sub;
      case 'super':
        return SvgBaselineShift.superScript;
      default:
        if (s.endsWith('%')) {
          final v = double.tryParse(s.substring(0, s.length - 1).trim());
          return v != null
              ? SvgBaselineShift(SvgBaselineShiftKind.percentage, v / 100.0)
              : null;
        }
        final len = parseLength(s);
        return len != null
            ? SvgBaselineShift(SvgBaselineShiftKind.length, len)
            : null;
    }
  }

  /// Parses `text-decoration` (`none`, `underline`, `overline`, `line-through`).
  static ui.TextDecoration? parseTextDecoration(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final tokens = raw.trim().toLowerCase().split(RegExp(r'\s+'));
    if (tokens.contains('none')) return ui.TextDecoration.none;
    final decos = <ui.TextDecoration>[];
    for (final tok in tokens) {
      switch (tok) {
        case 'underline':
          decos.add(ui.TextDecoration.underline);
        case 'overline':
          decos.add(ui.TextDecoration.overline);
        case 'line-through':
          decos.add(ui.TextDecoration.lineThrough);
      }
    }
    if (decos.isEmpty) return null;
    return ui.TextDecoration.combine(decos);
  }

  /// Parses `paint-order` (SVG 2: `normal`, `stroke`, `stroke fill`, `fill stroke`, etc.).
  static SvgPaintOrder? parsePaintOrder(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final tokens = raw.trim().toLowerCase().split(RegExp(r'\s+'));
    for (final tok in tokens) {
      if (tok == 'normal' || tok == 'fill') return SvgPaintOrder.fillStroke;
      if (tok == 'stroke') return SvgPaintOrder.strokeFill;
    }
    return null;
  }

  /// Parses W3C CSS Compositing & Blending `mix-blend-mode` / `<feBlend mode>`.
  static ui.BlendMode? parseBlendMode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    switch (raw.trim().toLowerCase()) {
      case 'normal':
        return ui.BlendMode.srcOver;
      case 'multiply':
        return ui.BlendMode.multiply;
      case 'screen':
        return ui.BlendMode.screen;
      case 'overlay':
        return ui.BlendMode.overlay;
      case 'darken':
        return ui.BlendMode.darken;
      case 'lighten':
        return ui.BlendMode.lighten;
      case 'color-dodge':
        return ui.BlendMode.colorDodge;
      case 'color-burn':
        return ui.BlendMode.colorBurn;
      case 'hard-light':
        return ui.BlendMode.hardLight;
      case 'soft-light':
        return ui.BlendMode.softLight;
      case 'difference':
        return ui.BlendMode.difference;
      case 'exclusion':
        return ui.BlendMode.exclusion;
      case 'hue':
        return ui.BlendMode.hue;
      case 'saturation':
        return ui.BlendMode.saturation;
      case 'color':
        return ui.BlendMode.color;
      case 'luminosity':
        return ui.BlendMode.luminosity;
      default:
        return null;
    }
  }

  /// Parses a CSS `filter` function chain (`blur()`, `drop-shadow()`,
  /// `brightness()`, `contrast()`, `grayscale()`, `saturate()`, `sepia()`,
  /// `hue-rotate()`, `invert()`, `opacity()`) into [SvgFilterPrimitive] nodes.
  static List<SvgFilterPrimitive> parseCssFilterChain(String raw) {
    final primitives = <SvgFilterPrimitive>[];
    final matches = RegExp(r'([a-zA-Z-]+)\s*\(([^)]*)\)').allMatches(raw);
    for (final m in matches) {
      final fn = m.group(1)!.trim().toLowerCase();
      final args = m.group(2)!.trim();
      if (fn == 'url') continue;

      switch (fn) {
        case 'blur':
          final sigma = parseLength(args) ?? 0.0;
          if (sigma > 0.0) {
            primitives.add(SvgFeGaussianBlur(sigmaX: sigma, sigmaY: sigma));
          }
        case 'brightness':
          final b = (parseNumberOrPercent(args) ?? 1.0).clamp(0.0, 100.0);
          primitives.add(
            SvgFeColorMatrix(
              type: SvgFeColorMatrixType.matrix,
              values: Float64List.fromList(<double>[
                b,
                0,
                0,
                0,
                0,
                0,
                b,
                0,
                0,
                0,
                0,
                0,
                b,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
              ]),
            ),
          );
        case 'contrast':
          final c = (parseNumberOrPercent(args) ?? 1.0).clamp(0.0, 100.0);
          final t = 0.5 * (1.0 - c);
          primitives.add(
            SvgFeColorMatrix(
              type: SvgFeColorMatrixType.matrix,
              values: Float64List.fromList(<double>[
                c,
                0,
                0,
                0,
                t,
                0,
                c,
                0,
                0,
                t,
                0,
                0,
                c,
                0,
                t,
                0,
                0,
                0,
                1,
                0,
              ]),
            ),
          );
        case 'grayscale':
          final g = (parseNumberOrPercent(args) ?? 1.0).clamp(0.0, 1.0);
          primitives.add(
            SvgFeColorMatrix(
              type: SvgFeColorMatrixType.saturate,
              values: Float64List.fromList(<double>[1.0 - g]),
            ),
          );
        case 'saturate':
          final s = (parseNumberOrPercent(args) ?? 1.0).clamp(0.0, 100.0);
          primitives.add(
            SvgFeColorMatrix(
              type: SvgFeColorMatrixType.saturate,
              values: Float64List.fromList(<double>[s]),
            ),
          );
        case 'sepia':
          final a = (parseNumberOrPercent(args) ?? 1.0).clamp(0.0, 1.0);
          final inv = 1.0 - a;
          primitives.add(
            SvgFeColorMatrix(
              type: SvgFeColorMatrixType.matrix,
              values: Float64List.fromList(<double>[
                0.393 + 0.607 * inv,
                0.769 - 0.769 * inv,
                0.189 - 0.189 * inv,
                0,
                0,
                0.349 - 0.349 * inv,
                0.686 + 0.314 * inv,
                0.168 - 0.168 * inv,
                0,
                0,
                0.272 - 0.272 * inv,
                0.534 - 0.534 * inv,
                0.131 + 0.869 * inv,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
              ]),
            ),
          );
        case 'hue-rotate':
          final deg = parseAngleOrLength(args) ?? 0.0;
          primitives.add(
            SvgFeColorMatrix(
              type: SvgFeColorMatrixType.hueRotate,
              values: Float64List.fromList(<double>[deg]),
            ),
          );
        case 'invert':
          final a = (parseNumberOrPercent(args) ?? 1.0).clamp(0.0, 1.0);
          final s = 1.0 - 2.0 * a;
          primitives.add(
            SvgFeColorMatrix(
              type: SvgFeColorMatrixType.matrix,
              values: Float64List.fromList(<double>[
                s,
                0,
                0,
                0,
                a,
                0,
                s,
                0,
                0,
                a,
                0,
                0,
                s,
                0,
                a,
                0,
                0,
                0,
                1,
                0,
              ]),
            ),
          );
        case 'opacity':
          final a = (parseNumberOrPercent(args) ?? 1.0).clamp(0.0, 1.0);
          primitives.add(
            SvgFeColorMatrix(
              type: SvgFeColorMatrixType.matrix,
              values: Float64List.fromList(<double>[
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                0,
                0,
                a,
                0,
              ]),
            ),
          );
        case 'drop-shadow':
          final ds = _parseCssDropShadow(args);
          if (ds != null) primitives.add(ds);
      }
    }
    return primitives;
  }

  static SvgFeDropShadow? _parseCssDropShadow(String args) {
    if (args.isEmpty) return null;
    // Extract optional color function (rgb/rgba/hsl/hsla/hwb) first so spaces inside parens stay intact
    ui.Color? color;
    var remaining = args;
    final fnColorMatch = RegExp(
      r'(?:rgba?|hsla?|hwb)\s*\([^)]*\)',
      caseSensitive: false,
    ).firstMatch(remaining);
    if (fnColorMatch != null) {
      color = parseColor(fnColorMatch.group(0));
      remaining = remaining.replaceRange(
        fnColorMatch.start,
        fnColorMatch.end,
        ' ',
      );
    }
    final tokens = remaining
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final lengths = <double>[];
    for (final tok in tokens) {
      final c = color == null ? parseColor(tok) : null;
      if (c != null) {
        color = c;
      } else {
        final len = parseLength(tok);
        if (len != null) lengths.add(len);
      }
    }
    if (lengths.length < 2) return null;
    final sigma = lengths.length >= 3 ? lengths[2] * 0.5 : 0.0;
    return SvgFeDropShadow(
      dx: lengths[0],
      dy: lengths[1],
      sigmaX: sigma,
      sigmaY: sigma,
      floodColor: color ?? const ui.Color(0xFF000000),
      floodOpacity: 1.0,
    );
  }
}
