import 'dart:math' as math;
import 'dart:ui' as ui;

import '../parser/svg_css_value_parser.dart';
import '../parser/svg_path_parser.dart';
import 'svg_precompiled_path.dart';

/// Base sealed class for W3C CSS Masking Level 1 `clip-path` basic shapes
/// (`inset()`, `circle()`, `ellipse()`, `polygon()`, `path()`).
/// W3C CSS Masking Level 1 `clip-path` 基础裁剪形状密封基类。
sealed class SvgCssClipShape {
  /// Creates an [SvgCssClipShape]. 创建一个 [SvgCssClipShape] 裁剪形状基类实例。
  const SvgCssClipShape();

  /// Builds a [ui.Path] clipped against the element's reference [bounds].
  /// 根据元素参考包围盒 [bounds] 构建对应的 [ui.Path] 裁剪路径。
  ///
  /// - [bounds]: Element reference bounding box. 元素参考包围盒。
  ui.Path resolvePath(ui.Rect bounds);
}

/// A length or percentage value evaluated against a reference axis extent.
/// 相对参考轴尺寸求值的长度或百分比值。
class SvgClipLength {
  /// Numeric value (pixels when [isPercent] is `false`, or `0.0..1.0` ratio when `true`).
  /// 数值（非百分比时为像素，百分比时为 `0.0..1.0` 比例）。
  final double value;

  /// Whether [value] represents a percentage ratio. 是否为百分比比例值。
  final bool isPercent;

  /// Creates an [SvgClipLength]. 创建一个 [SvgClipLength] 长度对象。
  ///
  /// - [value]: Pixel value or normalized percentage ratio. 像素值或归一化百分比。
  /// - [isPercent]: Whether [value] is a percentage. 是否为百分比。
  const SvgClipLength(this.value, {this.isPercent = false});

  /// Resolves this length against [extent]. 按参考尺寸 [extent] 解析最终像素值。
  ///
  /// - [extent]: Reference axis length. 参考轴长度。
  double resolve(double extent) => isPercent ? value * extent : value;

  /// Parses a length or percentage string [raw] into an [SvgClipLength].
  /// 将长度或百分比字符串 [raw] 解析为 [SvgClipLength]。
  ///
  /// - [raw]: Raw CSS length or percentage token. 原始长度或百分比标记。
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

/// Rectangular inset clip shape (`clip-path: inset(top right bottom left [round radius])`).
/// 内缩矩形裁剪形状（支持可选圆角 `round radius`）。
final class SvgCssClipInset extends SvgCssClipShape {
  /// Top inset offset. 顶部内缩距离。
  final SvgClipLength top;

  /// Right inset offset. 右侧内缩距离。
  final SvgClipLength right;

  /// Bottom inset offset. 底部内缩距离。
  final SvgClipLength bottom;

  /// Left inset offset. 左侧内缩距离。
  final SvgClipLength left;

  /// Optional uniform corner radius (`round <radius>`). 可选圆角半径。
  final SvgClipLength? borderRadius;

  /// Creates an [SvgCssClipInset]. 创建一个 [SvgCssClipInset] 内缩矩形裁剪形状。
  ///
  /// - [top]: Top inset. 顶部内缩。
  /// - [right]: Right inset. 右侧内缩。
  /// - [bottom]: Bottom inset. 底部内缩。
  /// - [left]: Left inset. 左侧内缩。
  /// - [borderRadius]: Optional uniform corner radius. 可选统一圆角半径。
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

/// Circular clip shape (`clip-path: circle([radius] [at cx cy])`).
/// 圆形裁剪形状（`circle([radius] [at cx cy])`）。
final class SvgCssClipCircle extends SvgCssClipShape {
  /// Optional circle radius (defaults to closest-side when `null`). 可选圆半径。
  final SvgClipLength? radius;

  /// Center X coordinate (defaults to `50%`). 圆心横坐标（默认 `50%`）。
  final SvgClipLength cx;

  /// Center Y coordinate (defaults to `50%`). 圆心纵坐标（默认 `50%`）。
  final SvgClipLength cy;

  /// Creates an [SvgCssClipCircle]. 创建一个 [SvgCssClipCircle] 圆形裁剪形状。
  ///
  /// - [radius]: Optional radius. 可选半径。
  /// - [cx]: Center X position. 圆心 X。
  /// - [cy]: Center Y position. 圆心 Y。
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
    return ui.Path()..addOval(
      ui.Rect.fromCircle(center: ui.Offset(x, y), radius: math.max(0.0, r)),
    );
  }
}

/// Elliptical clip shape (`clip-path: ellipse([rx ry] [at cx cy])`).
/// 椭圆形裁剪形状（`ellipse([rx ry] [at cx cy])`）。
final class SvgCssClipEllipse extends SvgCssClipShape {
  /// Optional horizontal radius. 可选水平半径。
  final SvgClipLength? rx;

  /// Optional vertical radius. 可选垂直半径。
  final SvgClipLength? ry;

  /// Center X coordinate (defaults to `50%`). 中心 X 坐标（默认 `50%`）。
  final SvgClipLength cx;

  /// Center Y coordinate (defaults to `50%`). 中心 Y 坐标（默认 `50%`）。
  final SvgClipLength cy;

  /// Creates an [SvgCssClipEllipse]. 创建一个 [SvgCssClipEllipse] 椭圆形裁剪形状。
  ///
  /// - [rx]: Optional horizontal radius. 可选水平半径。
  /// - [ry]: Optional vertical radius. 可选垂直半径。
  /// - [cx]: Center X position. 中心 X。
  /// - [cy]: Center Y position. 中心 Y。
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
    final radX =
        rx?.resolve(bounds.width) ??
        math.min((x - bounds.left).abs(), (bounds.right - x).abs());
    final radY =
        ry?.resolve(bounds.height) ??
        math.min((y - bounds.top).abs(), (bounds.bottom - y).abs());
    return ui.Path()..addOval(
      ui.Rect.fromCenter(
        center: ui.Offset(x, y),
        width: math.max(0.0, radX * 2.0),
        height: math.max(0.0, radY * 2.0),
      ),
    );
  }
}

/// Polygon clip shape (`clip-path: polygon([nonzero|evenodd,] x1 y1, x2 y2, ...)`).
/// 多边形裁剪形状（`polygon(...)`）。
final class SvgCssClipPolygon extends SvgCssClipShape {
  /// Ordered polygon vertex `(x, y)` pairs. 有序多边形顶点 `(x, y)` 列表。
  final List<(SvgClipLength, SvgClipLength)> points;

  /// Fill rule (`nonZero` or `evenOdd`). 填充规则（`nonZero` 或 `evenOdd`）。
  final ui.PathFillType fillType;

  /// Creates an [SvgCssClipPolygon]. 创建一个 [SvgCssClipPolygon] 多边形裁剪形状。
  ///
  /// - [points]: Vertex list. 顶点坐标列表。
  /// - [fillType]: Path fill rule. 路径填充规则。
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

/// SVG path clip shape (`clip-path: path([nonzero|evenodd,] "M...")`).
/// 任意路径裁剪形状（`path(...)`）。
final class SvgCssClipPathShape extends SvgCssClipShape {
  /// Precompiled path commands and coordinates. 预编译路径指令与坐标数据。
  final PrecompiledSvgPath precompiled;

  /// Fill rule (`nonZero` or `evenOdd`). 填充规则（`nonZero` 或 `evenOdd`）。
  final ui.PathFillType fillType;

  /// Creates an [SvgCssClipPathShape]. 创建一个 [SvgCssClipPathShape] 路径裁剪形状。
  ///
  /// - [precompiled]: Precompiled path geometry. 预编译路径几何。
  /// - [fillType]: Path fill rule. 路径填充规则。
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
/// CSS `clip-path` 基础几何裁剪形状函数解析器。
abstract final class SvgCssClipShapeParser {
  /// Parses a CSS `clip-path` shape function [raw] into an [SvgCssClipShape],
  /// or returns `null` if unrecognized.
  /// 将 CSS `clip-path` 形状函数字符串 [raw] 解析为 [SvgCssClipShape]；无法识别时返回 `null`。
  ///
  /// - [raw]: Raw CSS `clip-path` shape string. 原始 CSS `clip-path` 形状字符串。
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
    final parts = inner
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
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
      final pair = parts[i]
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toList();
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
