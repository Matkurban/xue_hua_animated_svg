import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Cubic;

import '../model/svg_style.dart';
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

    return svgNamedColors[s];
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
}
