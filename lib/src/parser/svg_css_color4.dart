import 'dart:math' as math;
import 'dart:ui' as ui;

/// Pure-Dart W3C CSS Color Level 4 modern color space conversions and mixing:
/// `oklab()`, `oklch()`, `lab()`, `lch()`, and `color-mix()`.
abstract final class SvgCssColor4 {
  /// Attempts to parse `oklab()`, `oklch()`, `lab()`, `lch()`, or `color-mix()`.
  ///
  /// [parseBaseColor] is a callback to parse nested sRGB / named / hex colors
  /// inside `color-mix()`.
  static ui.Color? parse(
    String rawLower, {
    required ui.Color? Function(String) parseBaseColor,
  }) {
    if (rawLower.startsWith('oklab(')) {
      return _parseOklab(rawLower);
    }
    if (rawLower.startsWith('oklch(')) {
      return _parseOklch(rawLower);
    }
    if (rawLower.startsWith('lab(')) {
      return _parseLab(rawLower);
    }
    if (rawLower.startsWith('lch(')) {
      return _parseLch(rawLower);
    }
    if (rawLower.startsWith('color-mix(')) {
      return _parseColorMix(rawLower, parseBaseColor);
    }
    return null;
  }

  static ui.Color? _parseOklab(String s) {
    final parts = _extractArgs(s);
    if (parts == null || parts.length < 3) return null;
    final l = _parsePercentOrNumber(parts[0], percentScale: 1.0);
    final a = _parsePercentOrNumber(parts[1], percentScale: 0.4);
    final b = _parsePercentOrNumber(parts[2], percentScale: 0.4);
    if (l == null || a == null || b == null) return null;
    final alpha = parts.length >= 4
        ? (_parsePercentOrNumber(parts[3], percentScale: 1.0) ?? 1.0)
        : 1.0;
    return _oklabToSrgb(l.clamp(0.0, 1.0), a, b, alpha.clamp(0.0, 1.0));
  }

  static ui.Color? _parseOklch(String s) {
    final parts = _extractArgs(s);
    if (parts == null || parts.length < 3) return null;
    final l = _parsePercentOrNumber(parts[0], percentScale: 1.0);
    final c = _parsePercentOrNumber(parts[1], percentScale: 0.4);
    final hDeg = _parseHueDegrees(parts[2]);
    if (l == null || c == null || hDeg == null) return null;
    final alpha = parts.length >= 4
        ? (_parsePercentOrNumber(parts[3], percentScale: 1.0) ?? 1.0)
        : 1.0;
    final hRad = hDeg * (math.pi / 180.0);
    final chroma = math.max(0.0, c);
    return _oklabToSrgb(
      l.clamp(0.0, 1.0),
      chroma * math.cos(hRad),
      chroma * math.sin(hRad),
      alpha.clamp(0.0, 1.0),
    );
  }

  static ui.Color? _parseLab(String s) {
    final parts = _extractArgs(s);
    if (parts == null || parts.length < 3) return null;
    final l = _parsePercentOrNumber(parts[0], percentScale: 100.0);
    final a = _parsePercentOrNumber(parts[1], percentScale: 125.0);
    final b = _parsePercentOrNumber(parts[2], percentScale: 125.0);
    if (l == null || a == null || b == null) return null;
    final alpha = parts.length >= 4
        ? (_parsePercentOrNumber(parts[3], percentScale: 1.0) ?? 1.0)
        : 1.0;
    return _cieLabToSrgb(l.clamp(0.0, 100.0), a, b, alpha.clamp(0.0, 1.0));
  }

  static ui.Color? _parseLch(String s) {
    final parts = _extractArgs(s);
    if (parts == null || parts.length < 3) return null;
    final l = _parsePercentOrNumber(parts[0], percentScale: 100.0);
    final c = _parsePercentOrNumber(parts[1], percentScale: 150.0);
    final hDeg = _parseHueDegrees(parts[2]);
    if (l == null || c == null || hDeg == null) return null;
    final alpha = parts.length >= 4
        ? (_parsePercentOrNumber(parts[3], percentScale: 1.0) ?? 1.0)
        : 1.0;
    final hRad = hDeg * (math.pi / 180.0);
    final chroma = math.max(0.0, c);
    return _cieLabToSrgb(
      l.clamp(0.0, 100.0),
      chroma * math.cos(hRad),
      chroma * math.sin(hRad),
      alpha.clamp(0.0, 1.0),
    );
  }

  static ui.Color? _parseColorMix(
    String s,
    ui.Color? Function(String) parseBaseColor,
  ) {
    final open = s.indexOf('(');
    final close = s.lastIndexOf(')');
    if (open == -1 || close <= open) return null;
    final inner = s.substring(open + 1, close).trim();
    final args = _splitTopLevelComma(inner);
    if (args.length < 3) return null;

    final method = args[0].trim().toLowerCase();
    if (!method.startsWith('in ')) return null;
    final space = method.substring(3).trim().split(RegExp(r'\s+')).first;

    final (c1, p1) = _parseMixComponent(args[1].trim(), parseBaseColor);
    final (c2, p2) = _parseMixComponent(args[2].trim(), parseBaseColor);
    if (c1 == null || c2 == null) return null;

    // W3C CSS Color 5 §2.2 percentage normalization
    double w1;
    double w2;
    if (p1 == null && p2 == null) {
      w1 = 0.5;
      w2 = 0.5;
    } else if (p1 != null && p2 == null) {
      w1 = p1.clamp(0.0, 1.0);
      w2 = 1.0 - w1;
    } else if (p1 == null && p2 != null) {
      w2 = p2.clamp(0.0, 1.0);
      w1 = 1.0 - w2;
    } else {
      w1 = p1!.clamp(0.0, 1.0);
      w2 = p2!.clamp(0.0, 1.0);
    }

    final sum = w1 + w2;
    if (sum <= 1e-6) return const ui.Color(0x00000000);
    final alphaMultiplier = sum < 1.0 ? sum : 1.0;
    final n1 = w1 / sum;
    final n2 = w2 / sum;

    if (space == 'oklab' || space == 'oklch') {
      final (l1, a1, b1) = _srgbToOklab(c1);
      final (l2, a2, b2) = _srgbToOklab(c2);
      final al = (c1.a * n1 + c2.a * n2).clamp(0.0, 1.0);
      if (al <= 1e-6) return const ui.Color(0x00000000);
      final l = (l1 * c1.a * n1 + l2 * c2.a * n2) / al;
      final a = (a1 * c1.a * n1 + a2 * c2.a * n2) / al;
      final b = (b1 * c1.a * n1 + b2 * c2.a * n2) / al;
      return _oklabToSrgb(l, a, b, (al * alphaMultiplier).clamp(0.0, 1.0));
    }

    if (space == 'srgb-linear') {
      final r1 = _srgbToLinear(c1.r);
      final g1 = _srgbToLinear(c1.g);
      final b1 = _srgbToLinear(c1.b);
      final r2 = _srgbToLinear(c2.r);
      final g2 = _srgbToLinear(c2.g);
      final b2 = _srgbToLinear(c2.b);
      final al = (c1.a * n1 + c2.a * n2).clamp(0.0, 1.0);
      if (al <= 1e-6) return const ui.Color(0x00000000);
      final r = _linearToSrgb((r1 * c1.a * n1 + r2 * c2.a * n2) / al);
      final g = _linearToSrgb((g1 * c1.a * n1 + g2 * c2.a * n2) / al);
      final b = _linearToSrgb((b1 * c1.a * n1 + b2 * c2.a * n2) / al);
      return _fromFloats(r, g, b, (al * alphaMultiplier).clamp(0.0, 1.0));
    }

    // Default: premultiplied sRGB interpolation
    final al = (c1.a * n1 + c2.a * n2).clamp(0.0, 1.0);
    if (al <= 1e-6) return const ui.Color(0x00000000);
    final r = (c1.r * c1.a * n1 + c2.r * c2.a * n2) / al;
    final g = (c1.g * c1.a * n1 + c2.g * c2.a * n2) / al;
    final b = (c1.b * c1.a * n1 + c2.b * c2.a * n2) / al;
    return _fromFloats(r, g, b, (al * alphaMultiplier).clamp(0.0, 1.0));
  }

  static (ui.Color?, double?) _parseMixComponent(
    String raw,
    ui.Color? Function(String) parseBaseColor,
  ) {
    final tokens = _splitTopLevelSpaces(raw);
    if (tokens.isEmpty) return (null, null);
    ui.Color? color;
    double? pct;
    for (final tok in tokens) {
      if (tok.endsWith('%')) {
        final v = double.tryParse(tok.substring(0, tok.length - 1).trim());
        if (v != null) {
          pct = v / 100.0;
          continue;
        }
      }
      color ??= parseBaseColor(tok);
    }
    return (color, pct);
  }

  /// Björn Ottosson / W3C CSS Color 4 §9.2 OKLab -> linear sRGB -> sRGB.
  static ui.Color _oklabToSrgb(double l, double a, double b, double alpha) {
    final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = l - 0.0894841775 * a - 1.2914855480 * b;

    final l3 = l_ * l_ * l_;
    final m3 = m_ * m_ * m_;
    final s3 = s_ * s_ * s_;

    final lr = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
    final lg = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
    final lb = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;

    return _fromFloats(
      _linearToSrgb(lr),
      _linearToSrgb(lg),
      _linearToSrgb(lb),
      alpha,
    );
  }

  static (double, double, double) _srgbToOklab(ui.Color c) {
    final r = _srgbToLinear(c.r);
    final g = _srgbToLinear(c.g);
    final b = _srgbToLinear(c.b);

    final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);

    return (
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    );
  }

  /// W3C CSS Color 4 §9.1 CIE Lab (D50) -> XYZ D50 -> Bradford XYZ D65 -> sRGB.
  static ui.Color _cieLabToSrgb(double l, double a, double b, double alpha) {
    const k = 24389.0 / 27.0;
    const e = 216.0 / 24389.0;
    const d50X = 0.9642956764295677;
    const d50Y = 1.0;
    const d50Z = 0.8251046025104602;

    final fy = (l + 16.0) / 116.0;
    final fx = a / 500.0 + fy;
    final fz = fy - b / 200.0;

    final fx3 = fx * fx * fx;
    final fz3 = fz * fz * fz;
    final xr = fx3 > e ? fx3 : (116.0 * fx - 16.0) / k;
    final yr = l > k * e ? math.pow((l + 16.0) / 116.0, 3).toDouble() : l / k;
    final zr = fz3 > e ? fz3 : (116.0 * fz - 16.0) / k;

    final x50 = xr * d50X;
    final y50 = yr * d50Y;
    final z50 = zr * d50Z;

    // Bradford chromatic adaptation D50 -> D65
    final x65 = 0.9554734527042182 * x50 - 0.023098536874261423 * y50 + 0.0632593086610217 * z50;
    final y65 = -0.028369706963208136 * x50 + 1.0099954580058226 * y50 + 0.021041398966943008 * z50;
    final z65 = 0.012314001688319899 * x50 - 0.020507696433477912 * y50 + 1.3303659366080753 * z50;

    // XYZ D65 -> linear sRGB
    final lr = 3.2409699419045226 * x65 - 1.537383177570094 * y65 - 0.4986107602930034 * z65;
    final lg = -0.9692436362808796 * x65 + 1.8759675015077202 * y65 + 0.04155505740717559 * z65;
    final lb = 0.05563007969699366 * x65 - 0.20397695888897652 * y65 + 1.0569715142428786 * z65;

    return _fromFloats(
      _linearToSrgb(lr),
      _linearToSrgb(lg),
      _linearToSrgb(lb),
      alpha,
    );
  }

  static double _srgbToLinear(double c) => c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static double _linearToSrgb(double c) {
    final clamped = c.clamp(0.0, 1.0);
    return clamped <= 0.0031308
        ? 12.92 * clamped
        : 1.055 * math.pow(clamped, 1.0 / 2.4).toDouble() - 0.055;
  }

  static double _cbrt(double x) =>
      x < 0 ? -math.pow(-x, 1.0 / 3.0).toDouble() : math.pow(x, 1.0 / 3.0).toDouble();

  static ui.Color _fromFloats(double r, double g, double b, double a) {
    return ui.Color.fromARGB(
      (a.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255),
      (r.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255),
      (g.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255),
      (b.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255),
    );
  }

  static List<String>? _extractArgs(String s) {
    final open = s.indexOf('(');
    final close = s.lastIndexOf(')');
    if (open == -1 || close <= open) return null;
    return s
        .substring(open + 1, close)
        .split(RegExp(r'[\s,/]+'))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static double? _parsePercentOrNumber(String raw, {required double percentScale}) {
    final t = raw.trim();
    if (t == 'none') return 0.0;
    if (t.endsWith('%')) {
      final v = double.tryParse(t.substring(0, t.length - 1).trim());
      return v != null ? (v / 100.0) * percentScale : null;
    }
    return double.tryParse(t);
  }

  static double? _parseHueDegrees(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'none') return 0.0;
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
    return double.tryParse(s);
  }

  static List<String> _splitTopLevelComma(String s) {
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

  static List<String> _splitTopLevelSpaces(String s) {
    final result = <String>[];
    int start = 0;
    int depth = 0;
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x28) {
        depth++;
      } else if (c == 0x29) {
        if (depth > 0) depth--;
      } else if ((c == 0x20 || c == 0x09) && depth == 0) {
        if (i > start) result.add(s.substring(start, i).trim());
        start = i + 1;
      }
    }
    if (start < s.length) result.add(s.substring(start).trim());
    return result;
  }
}
