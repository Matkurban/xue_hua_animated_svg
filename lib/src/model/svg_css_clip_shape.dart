import 'dart:math' as math;
import 'dart:ui' as ui;

import '../parser/svg_css_value_parser.dart';
import '../parser/svg_path_parser.dart';
import 'svg_precompiled_path.dart';

/// Base sealed class for W3C CSS Masking Level 1 `clip-path` basic shapes
/// (`inset()`, `circle()`, `ellipse()`, `polygon()`, `path()`).
sealed class SvgCssClipShape {
  const SvgCssClipShape();

  /// Builds a [ui.Path] clipped against the element's reference [bounds].
  ui.Path resolvePath(ui.Rect bounds);
}

/// A length or percentage value evaluated against a reference axis extent.
class SvgClipLength {
  final double value;
  final bool isPercent;

  const SvgClipLength(this.value, {this.isPercent = false});

  double resolve(double extent) => isPercent ? value * extent : value;

  static SvgClipLength? parse(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.endsWith('%')) {
      final v = double.tryParse(s.substring(0, s.length - 1).trim());
      return v != null ? SvgClipLength(v / 100.0, isPercent: true) : null;
    }
    final px = SvgCssValueParser.parseLength(s);
    return px != null ? SvgClipLength(px) : null;
  }
}

/// `clip-path: inset(top right bottom left [round radius])`
final class SvgCssClipInset extends SvgCssClipShape {
  final SvgClipLength top;
  final SvgClipLength right;
  final SvgClipLength bottom;
  final SvgClipLength left;
  final SvgClipLength? borderRadius;

  const SvgCssClipInset({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
    this.borderRadius,
  });

  @override
  ui.Path resolvePath(ui.Rect bounds) {
    final l = bounds.left + left.resolve(bounds.width);
    final t = bounds.top + top.resolve(bounds.height);
    final r = bounds.right - right.resolve(bounds.width);
    final b = bounds.bottom - bottom.resolve(bounds.height);
    final rect = ui.Rect.fromLTRB(
      math.min(l, r),
      math.min(t, b),
      math.max(l, r),
      math.max(t, b),
    );
    final path = ui.Path();
    if (borderRadius != null) {
      final rad = borderRadius!.resolve(math.min(bounds.width, bounds.height));
      path.addRRect(ui.RRect.fromRectXY(rect, rad, rad));
    } else {
      path.addRect(rect);
    }
    return path;
  }
}

/// `clip-path: circle([radius] [at cx cy])`
final class SvgCssClipCircle extends SvgCssClipShape {
  final SvgClipLength? radius;
  final SvgClipLength cx;
  final SvgClipLength cy;

  const SvgCssClipCircle({
    this.radius,
    this.cx = const SvgClipLength(0.5, isPercent: true),
    this.cy = const SvgClipLength(0.5, isPercent: true),
  });

  @override
  ui.Path resolvePath(ui.Rect bounds) {
    final x = bounds.left + cx.resolve(bounds.width);
    final y = bounds.top + cy.resolve(bounds.height);
    final diag = math.sqrt(
      (bounds.width * bounds.width + bounds.height * bounds.height) * 0.5,
    );
    final r = radius != null
        ? radius!.resolve(diag)
        : math.min(
            math.min((x - bounds.left).abs(), (bounds.right - x).abs()),
            math.min((y - bounds.top).abs(), (bounds.bottom - y).abs()),
          );
    return ui.Path()
      ..addOval(ui.Rect.fromCircle(center: ui.Offset(x, y), radius: math.max(0.0, r)));
  }
}

/// `clip-path: ellipse([rx ry] [at cx cy])`
final class SvgCssClipEllipse extends SvgCssClipShape {
  final SvgClipLength? rx;
  final SvgClipLength? ry;
  final SvgClipLength cx;
  final SvgClipLength cy;

  const SvgCssClipEllipse({
    this.rx,
    this.ry,
    this.cx = const SvgClipLength(0.5, isPercent: true),
    this.cy = const SvgClipLength(0.5, isPercent: true),
  });

  @override
  ui.Path resolvePath(ui.Rect bounds) {
    final x = bounds.left + cx.resolve(bounds.width);
    final y = bounds.top + cy.resolve(bounds.height);
    final radX = rx?.resolve(bounds.width) ??
        math.min((x - bounds.left).abs(), (bounds.right - x).abs());
    final radY = ry?.resolve(bounds.height) ??
        math.min((y - bounds.top).abs(), (bounds.bottom - y).abs());
    return ui.Path()
      ..addOval(
        ui.Rect.fromCenter(
          center: ui.Offset(x, y),
          width: math.max(0.0, radX * 2.0),
          height: math.max(0.0, radY * 2.0),
        ),
      );
  }
}

/// `clip-path: polygon([nonzero|evenodd,] x1 y1, x2 y2, ...)`
final class SvgCssClipPolygon extends SvgCssClipShape {
  final List<(SvgClipLength, SvgClipLength)> points;
  final ui.PathFillType fillType;

  const SvgCssClipPolygon({
    required this.points,
    this.fillType = ui.PathFillType.nonZero,
  });

  @override
  ui.Path resolvePath(ui.Rect bounds) {
    final path = ui.Path()..fillType = fillType;
    if (points.isEmpty) return path;
    for (int i = 0; i < points.length; i++) {
      final (lx, ly) = points[i];
      final x = bounds.left + lx.resolve(bounds.width);
      final y = bounds.top + ly.resolve(bounds.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }
}

/// `clip-path: path([nonzero|evenodd,] "M...")`
final class SvgCssClipPathShape extends SvgCssClipShape {
  final PrecompiledSvgPath precompiled;
  final ui.PathFillType fillType;

  const SvgCssClipPathShape({
    required this.precompiled,
    this.fillType = ui.PathFillType.nonZero,
  });

  @override
  ui.Path resolvePath(ui.Rect bounds) {
    final path = ui.Path()..fillType = fillType;
    precompiled.buildUiPath(path);
    return path;
  }
}

/// Parser for CSS `clip-path` basic shape functions.
abstract final class SvgCssClipShapeParser {
  static SvgCssClipShape? parse(String raw) {
    final s = raw.trim();
    final lower = s.toLowerCase();
    final open = s.indexOf('(');
    final close = s.lastIndexOf(')');
    if (open == -1 || close <= open) return null;
    final fn = lower.substring(0, open).trim();
    final inner = s.substring(open + 1, close).trim();

    switch (fn) {
      case 'inset':
        return _parseInset(inner);
      case 'circle':
        return _parseCircle(inner);
      case 'ellipse':
        return _parseEllipse(inner);
      case 'polygon':
        return _parsePolygon(inner);
      case 'path':
        return _parsePath(inner);
      default:
        return null;
    }
  }

  static SvgCssClipInset? _parseInset(String inner) {
    final roundSplit = inner.split(RegExp(r'\bround\b', caseSensitive: false));
    final edgeTokens = roundSplit[0]
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (edgeTokens.isEmpty) return null;
    final edges = <SvgClipLength>[
      for (final t in edgeTokens) ?SvgClipLength.parse(t),
    ];
    if (edges.isEmpty) return null;
    final top = edges[0];
    final right = edges.length > 1 ? edges[1] : top;
    final bottom = edges.length > 2 ? edges[2] : top;
    final left = edges.length > 3 ? edges[3] : right;
    SvgClipLength? radius;
    if (roundSplit.length > 1) {
      final radTok = roundSplit[1].trim().split(RegExp(r'\s+')).first;
      radius = SvgClipLength.parse(radTok);
    }
    return SvgCssClipInset(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      borderRadius: radius,
    );
  }

  static SvgCssClipCircle _parseCircle(String inner) {
    final atSplit = inner.split(RegExp(r'\bat\b', caseSensitive: false));
    final radStr = atSplit[0].trim();
    final radius = radStr.isNotEmpty ? SvgClipLength.parse(radStr) : null;
    final (cx, cy) = _parsePosition(atSplit.length > 1 ? atSplit[1] : null);
    return SvgCssClipCircle(radius: radius, cx: cx, cy: cy);
  }

  static SvgCssClipEllipse _parseEllipse(String inner) {
    final atSplit = inner.split(RegExp(r'\bat\b', caseSensitive: false));
    final radTokens = atSplit[0]
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final rx = radTokens.isNotEmpty ? SvgClipLength.parse(radTokens[0]) : null;
    final ry = radTokens.length > 1 ? SvgClipLength.parse(radTokens[1]) : rx;
    final (cx, cy) = _parsePosition(atSplit.length > 1 ? atSplit[1] : null);
    return SvgCssClipEllipse(rx: rx, ry: ry, cx: cx, cy: cy);
  }

  static SvgCssClipPolygon? _parsePolygon(String inner) {
    final parts = inner.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    ui.PathFillType fillType = ui.PathFillType.nonZero;
    int startIdx = 0;
    final firstLower = parts[0].toLowerCase();
    if (firstLower == 'evenodd') {
      fillType = ui.PathFillType.evenOdd;
      startIdx = 1;
    } else if (firstLower == 'nonzero') {
      startIdx = 1;
    }
    final points = <(SvgClipLength, SvgClipLength)>[];
    for (int i = startIdx; i < parts.length; i++) {
      final pair = parts[i].split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      if (pair.length >= 2) {
        final x = SvgClipLength.parse(pair[0]);
        final y = SvgClipLength.parse(pair[1]);
        if (x != null && y != null) points.add((x, y));
      }
    }
    if (points.length < 3) return null;
    return SvgCssClipPolygon(points: points, fillType: fillType);
  }

  static SvgCssClipPathShape? _parsePath(String inner) {
    ui.PathFillType fillType = ui.PathFillType.nonZero;
    var rest = inner.trim();
    if (rest.toLowerCase().startsWith('evenodd')) {
      fillType = ui.PathFillType.evenOdd;
      final comma = rest.indexOf(',');
      if (comma != -1) rest = rest.substring(comma + 1).trim();
    } else if (rest.toLowerCase().startsWith('nonzero')) {
      final comma = rest.indexOf(',');
      if (comma != -1) rest = rest.substring(comma + 1).trim();
    }
    if (rest.length >= 2 &&
        ((rest.startsWith('"') && rest.endsWith('"')) ||
            (rest.startsWith("'") && rest.endsWith("'")))) {
      rest = rest.substring(1, rest.length - 1);
    }
    if (rest.isEmpty) return null;
    return SvgCssClipPathShape(
      precompiled: SvgPathParser.parse(rest),
      fillType: fillType,
    );
  }

  static (SvgClipLength, SvgClipLength) _parsePosition(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return (
        const SvgClipLength(0.5, isPercent: true),
        const SvgClipLength(0.5, isPercent: true),
      );
    }
    final toks = raw.trim().toLowerCase().split(RegExp(r'\s+'));
    SvgClipLength parseAxis(String t) {
      switch (t) {
        case 'left':
        case 'top':
          return const SvgClipLength(0.0, isPercent: true);
        case 'center':
          return const SvgClipLength(0.5, isPercent: true);
        case 'right':
        case 'bottom':
          return const SvgClipLength(1.0, isPercent: true);
        default:
          return SvgClipLength.parse(t) ??
              const SvgClipLength(0.5, isPercent: true);
      }
    }

    final x = parseAxis(toks[0]);
    final y = toks.length > 1
        ? parseAxis(toks[1])
        : const SvgClipLength(0.5, isPercent: true);
    return (x, y);
  }
}
