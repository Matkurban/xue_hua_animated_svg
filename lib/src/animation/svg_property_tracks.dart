import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/svg_gradient.dart';
import '../model/svg_node.dart';
import '../model/svg_style.dart';
import 'svg_animation_timing.dart';

/// Target scalar numeric attribute for SMIL `<animate>` or CSS `@keyframes`.
/// SMIL `<animate>` 或 CSS `@keyframes` 驱动的目标标量数值属性枚举。
enum SvgScalarTarget {
  /// Element overall `opacity`. 元素整体不透明度 `opacity`。
  opacity,

  /// Element `fill-opacity`. 填充不透明度 `fill-opacity`。
  fillOpacity,

  /// Element `stroke-opacity`. 描边不透明度 `stroke-opacity`。
  strokeOpacity,

  /// Element `stroke-width`. 描边线宽 `stroke-width`。
  strokeWidth,

  /// Element `stroke-dashoffset`. 虚线偏移量 `stroke-dashoffset`。
  strokeDashoffset,

  /// CSS `filter: blur(...)` Gaussian sigma. CSS 模糊滤镜标准差 `blurSigma`。
  blurSigma,

  /// Text `font-size`. 文本字号 `font-size`。
  fontSize,

  /// Text `letter-spacing`. 文本字间距 `letter-spacing`。
  letterSpacing,

  /// Element horizontal coordinate `x`. 元素横坐标 `x`。
  x,

  /// Element vertical coordinate `y`. 元素纵坐标 `y`。
  y,

  /// Text relative horizontal shift `dx`. 文本相对水平偏移 `dx`。
  dx,

  /// Text relative vertical shift `dy`. 文本相对垂直偏移 `dy`。
  dy,

  /// Element `width`. 元素宽度 `width`。
  width,

  /// Element `height`. 元素高度 `height`。
  height,

  /// Corner or ellipse X radius `rx`. 圆角或椭圆水平半径 `rx`。
  rx,

  /// Corner or ellipse Y radius `ry`. 圆角或椭圆垂直半径 `ry`。
  ry,

  /// Circle, ellipse, or radial gradient center X `cx`. 中心横坐标 `cx`。
  cx,

  /// Circle, ellipse, or radial gradient center Y `cy`. 中心纵坐标 `cy`。
  cy,

  /// Circle or radial gradient radius `r`. 半径 `r`。
  r,

  /// Line or linear gradient start X `x1`. 起点横坐标 `x1`。
  x1,

  /// Line or linear gradient start Y `y1`. 起点纵坐标 `y1`。
  y1,

  /// Line or linear gradient end X `x2`. 终点横坐标 `x2`。
  x2,

  /// Line or linear gradient end Y `y2`. 终点纵坐标 `y2`。
  y2,

  /// Radial gradient focal point X `fx`. 径向渐变焦点横坐标 `fx`。
  fx,

  /// Radial gradient focal point Y `fy`. 径向渐变焦点纵坐标 `fy`。
  fy,

  /// SVG 2 radial gradient focal radius `fr`. SVG 2 径向渐变焦点半径 `fr`。
  fr,

  /// Gradient `<stop>` `offset`. 渐变色标位置 `offset`。
  stopOffset,

  /// Gradient `<stop>` `stop-opacity`. 渐变色标不透明度 `stop-opacity`。
  stopOpacity,
}

/// Precompiled scalar (`double`) animation track (`<animate>` on numeric attributes).
/// 预编译的标量数值（`double`）动画轨道，驱动元素、渐变或色标的数值属性。
class SvgScalarAnimationTrack extends SvgAnimationTrack {
  /// Animated target (`SvgElement`, `SvgGradientNode`, or `SvgGradientStop`).
  /// 动画目标对象（可为 `SvgElement`、`SvgGradientNode` 或 `SvgGradientStop`）。
  final Object target;

  /// Target numeric property updated by this track.
  /// 本轨道更新的目标数值属性枚举。
  final SvgScalarTarget property;

  /// Precompiled numeric keyframe values.
  /// 预编译的数值关键帧数组。
  final Float64List keyframes;

  /// Creates an [SvgScalarAnimationTrack].
  /// 创建一个 [SvgScalarAnimationTrack] 标量动画轨道。
  ///
  /// - [timing]: Timing and easing evaluator. 时间轴与缓动求值器。
  /// - [target]: Target element, gradient, or stop. 目标元素、渐变或色标。
  /// - [property]: Target scalar property. 目标标量属性。
  /// - [keyframes]: Numeric keyframe array. 数值关键帧数组。
  SvgScalarAnimationTrack({
    required super.timing,
    required this.target,
    required this.property,
    required this.keyframes,
  });

  /// Evaluates the scalar value at [elapsedUs] (honoring `accumulate="sum"` and
  /// `additive="sum"`) and writes it in-place onto [target].
  /// 在微秒时间点 [elapsedUs] 处求值标量（支持 `accumulate="sum"` 与 `additive="sum"`）并原地写入 [target]。
  ///
  /// - [elapsedUs]: Virtual timeline timestamp in microseconds. 虚拟时间轴微秒时间戳。
  @override
  void applyAt(int elapsedUs) {
    if (keyframes.isEmpty) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    double value;
    if (keyframes.length == 1) {
      value = keyframes[0];
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      final v0 = keyframes[seg];
      final v1 = keyframes[seg + 1];
      value = v0 + (v1 - v0) * localT;
    }

    if (timing.accumulateSum && keyframes.length >= 2) {
      final cycle = timing.evaluateCycleIndex(elapsedUs);
      if (cycle > 0) {
        value += keyframes[keyframes.length - 1] * cycle;
      }
    }

    _writeScalarValue(value);
  }

  void _writeScalarValue(double value) {
    final isSum = timing.additiveMode == SvgAdditiveMode.sum;
    final t = target;
    if (t is SvgElement) {
      switch (property) {
        case SvgScalarTarget.opacity:
          t.style.currentOpacity =
              (isSum ? t.style.currentOpacity + value : value).clamp(0.0, 1.0);
        case SvgScalarTarget.fillOpacity:
          t.style.currentFillOpacity =
              (isSum ? t.style.currentFillOpacity + value : value).clamp(
                0.0,
                1.0,
              );
        case SvgScalarTarget.strokeOpacity:
          t.style.currentStrokeOpacity =
              (isSum ? t.style.currentStrokeOpacity + value : value).clamp(
                0.0,
                1.0,
              );
        case SvgScalarTarget.strokeWidth:
          t.style.currentStrokeWidth = math.max(
            0.0,
            isSum ? t.style.currentStrokeWidth + value : value,
          );
        case SvgScalarTarget.strokeDashoffset:
          t.style.currentStrokeDashoffset = isSum
              ? t.style.currentStrokeDashoffset + value
              : value;
        case SvgScalarTarget.blurSigma:
          t.style.currentBlurSigma = math.max(
            0.0,
            isSum ? t.style.currentBlurSigma + value : value,
          );
        case SvgScalarTarget.fontSize:
          t.style.currentFontSize = math.max(
            0.0,
            isSum ? t.style.currentFontSize + value : value,
          );
        case SvgScalarTarget.letterSpacing:
          t.style.currentLetterSpacing = isSum
              ? (t.style.currentLetterSpacing ?? 0.0) + value
              : value;
        case SvgScalarTarget.x:
          if (t is SvgRectNode) {
            t.currentX = isSum ? t.currentX + value : value;
            t.markGeometryDirty();
          } else if (t is SvgUseNode) {
            t.currentX = isSum ? t.currentX + value : value;
          } else if (t is SvgNestedSvgNode) {
            t.currentX = isSum ? t.currentX + value : value;
          } else if (t is SvgImageNode) {
            t.currentX = isSum ? t.currentX + value : value;
          } else if (t is SvgTextNode) {
            t.animatedX = isSum ? (t.animatedX ?? 0.0) + value : value;
          } else if (t is SvgTextSpanNode) {
            t.animatedX = isSum ? (t.animatedX ?? 0.0) + value : value;
          }
        case SvgScalarTarget.y:
          if (t is SvgRectNode) {
            t.currentY = isSum ? t.currentY + value : value;
            t.markGeometryDirty();
          } else if (t is SvgUseNode) {
            t.currentY = isSum ? t.currentY + value : value;
          } else if (t is SvgNestedSvgNode) {
            t.currentY = isSum ? t.currentY + value : value;
          } else if (t is SvgImageNode) {
            t.currentY = isSum ? t.currentY + value : value;
          } else if (t is SvgTextNode) {
            t.animatedY = isSum ? (t.animatedY ?? 0.0) + value : value;
          } else if (t is SvgTextSpanNode) {
            t.animatedY = isSum ? (t.animatedY ?? 0.0) + value : value;
          }
        case SvgScalarTarget.dx:
          if (t is SvgTextNode) {
            t.animatedDx = isSum ? (t.animatedDx ?? 0.0) + value : value;
          } else if (t is SvgTextSpanNode) {
            t.animatedDx = isSum ? (t.animatedDx ?? 0.0) + value : value;
          }
        case SvgScalarTarget.dy:
          if (t is SvgTextNode) {
            t.animatedDy = isSum ? (t.animatedDy ?? 0.0) + value : value;
          } else if (t is SvgTextSpanNode) {
            t.animatedDy = isSum ? (t.animatedDy ?? 0.0) + value : value;
          }
        case SvgScalarTarget.width:
          if (t is SvgRectNode) {
            t.currentWidth = math.max(
              0.0,
              isSum ? t.currentWidth + value : value,
            );
            t.markGeometryDirty();
          } else if (t is SvgUseNode) {
            t.currentWidth = math.max(
              0.0,
              isSum ? (t.currentWidth ?? 0.0) + value : value,
            );
          } else if (t is SvgNestedSvgNode) {
            t.currentWidth = math.max(
              0.0,
              isSum ? (t.currentWidth ?? 0.0) + value : value,
            );
          } else if (t is SvgImageNode) {
            t.currentWidth = math.max(
              0.0,
              isSum ? t.currentWidth + value : value,
            );
          }
        case SvgScalarTarget.height:
          if (t is SvgRectNode) {
            t.currentHeight = math.max(
              0.0,
              isSum ? t.currentHeight + value : value,
            );
            t.markGeometryDirty();
          } else if (t is SvgUseNode) {
            t.currentHeight = math.max(
              0.0,
              isSum ? (t.currentHeight ?? 0.0) + value : value,
            );
          } else if (t is SvgNestedSvgNode) {
            t.currentHeight = math.max(
              0.0,
              isSum ? (t.currentHeight ?? 0.0) + value : value,
            );
          } else if (t is SvgImageNode) {
            t.currentHeight = math.max(
              0.0,
              isSum ? t.currentHeight + value : value,
            );
          }
        case SvgScalarTarget.rx:
          if (t is SvgRectNode) {
            t.currentRx = math.max(0.0, isSum ? t.currentRx + value : value);
            t.markGeometryDirty();
          } else if (t is SvgEllipseNode) {
            t.currentRx = math.max(0.0, isSum ? t.currentRx + value : value);
            t.markGeometryDirty();
          }
        case SvgScalarTarget.ry:
          if (t is SvgRectNode) {
            t.currentRy = math.max(0.0, isSum ? t.currentRy + value : value);
            t.markGeometryDirty();
          } else if (t is SvgEllipseNode) {
            t.currentRy = math.max(0.0, isSum ? t.currentRy + value : value);
            t.markGeometryDirty();
          }
        case SvgScalarTarget.cx:
          if (t is SvgCircleNode) {
            t.currentCx = isSum ? t.currentCx + value : value;
            t.markGeometryDirty();
          } else if (t is SvgEllipseNode) {
            t.currentCx = isSum ? t.currentCx + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.cy:
          if (t is SvgCircleNode) {
            t.currentCy = isSum ? t.currentCy + value : value;
            t.markGeometryDirty();
          } else if (t is SvgEllipseNode) {
            t.currentCy = isSum ? t.currentCy + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.r:
          if (t is SvgCircleNode) {
            t.currentR = math.max(0.0, isSum ? t.currentR + value : value);
            t.markGeometryDirty();
          }
        case SvgScalarTarget.x1:
          if (t is SvgLineNode) {
            t.currentX1 = isSum ? t.currentX1 + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.y1:
          if (t is SvgLineNode) {
            t.currentY1 = isSum ? t.currentY1 + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.x2:
          if (t is SvgLineNode) {
            t.currentX2 = isSum ? t.currentX2 + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.y2:
          if (t is SvgLineNode) {
            t.currentY2 = isSum ? t.currentY2 + value : value;
            t.markGeometryDirty();
          }
        case SvgScalarTarget.fx:
        case SvgScalarTarget.fy:
        case SvgScalarTarget.fr:
        case SvgScalarTarget.stopOffset:
        case SvgScalarTarget.stopOpacity:
          break;
      }
    } else if (t is SvgLinearGradientNode) {
      switch (property) {
        case SvgScalarTarget.x1:
          t.currentX1 = isSum ? t.currentX1 + value : value;
        case SvgScalarTarget.y1:
          t.currentY1 = isSum ? t.currentY1 + value : value;
        case SvgScalarTarget.x2:
          t.currentX2 = isSum ? t.currentX2 + value : value;
        case SvgScalarTarget.y2:
          t.currentY2 = isSum ? t.currentY2 + value : value;
        default:
          break;
      }
    } else if (t is SvgRadialGradientNode) {
      switch (property) {
        case SvgScalarTarget.cx:
          t.currentCx = isSum ? t.currentCx + value : value;
        case SvgScalarTarget.cy:
          t.currentCy = isSum ? t.currentCy + value : value;
        case SvgScalarTarget.r:
          t.currentR = math.max(0.0, isSum ? t.currentR + value : value);
        case SvgScalarTarget.fx:
          t.currentFx = isSum ? t.currentFx + value : value;
        case SvgScalarTarget.fy:
          t.currentFy = isSum ? t.currentFy + value : value;
        case SvgScalarTarget.fr:
          t.currentFr = math.max(0.0, isSum ? t.currentFr + value : value);
        default:
          break;
      }
    } else if (t is SvgGradientStop) {
      switch (property) {
        case SvgScalarTarget.stopOffset:
          t.currentOffset = (isSum ? t.currentOffset + value : value).clamp(
            0.0,
            1.0,
          );
        case SvgScalarTarget.stopOpacity:
          t.currentOpacity = (isSum ? t.currentOpacity + value : value).clamp(
            0.0,
            1.0,
          );
        default:
          break;
      }
    }
  }
}

/// Target color attribute for `<animate>` / `<animateColor>` / CSS `@keyframes`.
/// `<animate>`、`<animateColor>` 或 CSS `@keyframes` 驱动的目标颜色属性枚举。
enum SvgColorTarget {
  /// Element `fill` color. 元素填充颜色 `fill`。
  fill,

  /// Element `stroke` color. 元素描边颜色 `stroke`。
  stroke,

  /// Gradient `<stop>` `stop-color`. 渐变色标颜色 `stop-color`。
  stopColor,
}

/// Precompiled color animation track (`fill`, `stroke`, `stop-color`).
/// 预编译的颜色插值动画轨道（支持 `fill`、`stroke`、`stop-color`）。
class SvgColorAnimationTrack extends SvgAnimationTrack {
  /// Target `SvgElement` or `SvgGradientStop`.
  /// 目标 `SvgElement` 或 `SvgGradientStop`。
  final Object target;

  /// Target color property.
  /// 目标颜色属性枚举。
  final SvgColorTarget property;

  /// Precompiled keyframe colors.
  /// 预编译的颜色关键帧列表。
  final List<ui.Color> keyframes;

  /// Creates an [SvgColorAnimationTrack].
  /// 创建一个 [SvgColorAnimationTrack] 颜色动画轨道。
  ///
  /// - [timing]: Timing and easing evaluator. 时间轴与缓动求值器。
  /// - [target]: Target element or gradient stop. 目标元素或渐变色标。
  /// - [property]: Target color property. 目标颜色属性。
  /// - [keyframes]: List of keyframe colors. 关键帧颜色列表。
  SvgColorAnimationTrack({
    required super.timing,
    required this.target,
    required this.property,
    required this.keyframes,
  });

  /// Interpolates [keyframes] at [elapsedUs] and writes the color onto [target].
  /// 在微秒时间点 [elapsedUs] 处插值 [keyframes] 并将颜色写入 [target]。
  ///
  /// - [elapsedUs]: Virtual timeline timestamp in microseconds. 虚拟时间轴微秒时间戳。
  @override
  void applyAt(int elapsedUs) {
    if (keyframes.isEmpty) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    final ui.Color color;
    if (keyframes.length == 1) {
      color = keyframes[0];
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      color =
          ui.Color.lerp(keyframes[seg], keyframes[seg + 1], localT) ??
          keyframes[seg];
    }

    final t = target;
    if (t is SvgElement) {
      if (property == SvgColorTarget.fill) {
        t.style.resolvedFill = SvgPaintServer.fromColor(color);
        t.style.currentFillColor = color;
      } else if (property == SvgColorTarget.stroke) {
        t.style.resolvedStroke = SvgPaintServer.fromColor(color);
        t.style.currentStrokeColor = color;
      }
    } else if (t is SvgGradientStop && property == SvgColorTarget.stopColor) {
      t.currentColor = color;
    }
  }
}

/// Precompiled `stroke-dasharray` animation track with pre-normalized equal-length
/// `Float64List` keyframes for zero-allocation in-place interpolation.
/// 预编译的 `stroke-dasharray` 虚线数组动画轨道，预先归一化至等长缓冲实现零分配原地插值。
class SvgDashArrayAnimationTrack extends SvgAnimationTrack {
  /// Target element whose stroke dash pattern is animated.
  /// 被驱动虚线样式的目标元素。
  final SvgElement target;

  /// Pre-normalized equal-length dash array keyframes.
  /// 已归一化为等长 `Float64List` 的虚线关键帧列表。
  final List<Float64List> keyframes;

  late final Float64List _interpolatedBuffer;

  /// Creates an [SvgDashArrayAnimationTrack].
  /// 创建一个 [SvgDashArrayAnimationTrack] 虚线数组动画轨道。
  ///
  /// - [timing]: Timing and easing evaluator. 时间轴与缓动求值器。
  /// - [target]: Target element. 目标元素。
  /// - [keyframes]: Normalized equal-length dash array keyframes. 等长虚线关键帧列表。
  SvgDashArrayAnimationTrack({
    required super.timing,
    required this.target,
    required this.keyframes,
  }) : _interpolatedBuffer = Float64List(
         keyframes.isEmpty ? 0 : keyframes[0].length,
       );

  /// Interpolates [keyframes] in-place at [elapsedUs] and assigns them to [target].
  /// 在微秒时间点 [elapsedUs] 处原地插值虚线数组并更新至 [target]。
  ///
  /// - [elapsedUs]: Virtual timeline timestamp in microseconds. 虚拟时间轴微秒时间戳。
  @override
  void applyAt(int elapsedUs) {
    if (keyframes.isEmpty || _interpolatedBuffer.isEmpty) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    if (keyframes.length == 1) {
      final k0 = keyframes[0];
      for (int i = 0; i < _interpolatedBuffer.length; i++) {
        _interpolatedBuffer[i] = k0[i];
      }
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      final k0 = keyframes[seg];
      final k1 = keyframes[seg + 1];
      for (int i = 0; i < _interpolatedBuffer.length; i++) {
        _interpolatedBuffer[i] = k0[i] + (k1[i] - k0[i]) * localT;
      }
    }
    target.style.currentStrokeDasharray = _interpolatedBuffer;
  }
}

/// Target discrete property kind for SMIL `<set>`.
/// SMIL `<set>` 离散状态切换的目标属性类型枚举。
enum SvgSetTargetKind {
  /// Toggles `display: none`. 切换 `display: none` 显隐。
  displayNone,

  /// Toggles `visibility: hidden`. 切换 `visibility: hidden` 可见性。
  visibilityHidden,

  /// Replaces the `fill` paint server. 替换 `fill` 填充画刷。
  fillPaint,

  /// Replaces the `stroke` paint server. 替换 `stroke` 描边画刷。
  strokePaint,
}

/// Precompiled SMIL `<set>` discrete state-switching track (`display`,
/// `visibility`, `fill`, `stroke`).
/// 预编译的 SMIL `<set>` 离散状态切换轨道（支持 `display`、`visibility`、`fill`、`stroke`）。
class SvgSetAnimationTrack extends SvgAnimationTrack {
  /// Target element modified while this `<set>` track is active.
  /// 该 `<set>` 轨道激活期间修改的目标元素。
  final SvgElement target;

  /// Kind of discrete property switched by this track.
  /// 离散切换的属性类型。
  final SvgSetTargetKind kind;

  /// Boolean payload used for [SvgSetTargetKind.displayNone] and [SvgSetTargetKind.visibilityHidden].
  /// 用于 `displayNone` / `visibilityHidden` 的布尔值载荷。
  final bool boolValue;

  /// Paint server payload used for [SvgSetTargetKind.fillPaint] and [SvgSetTargetKind.strokePaint].
  /// 用于 `fillPaint` / `strokePaint` 的画刷载荷。
  final SvgPaintServer? paintValue;

  /// Creates a boolean `<set>` track for `display` or `visibility`.
  /// 创建一个用于 `display` 或 `visibility` 的布尔型 `<set>` 轨道。
  ///
  /// - [timing]: Timing evaluator. 时间轴求值器。
  /// - [target]: Target element. 目标元素。
  /// - [kind]: Boolean target kind. 布尔目标属性类型。
  /// - [boolValue]: Value applied while active. 激活期间应用的布尔值。
  SvgSetAnimationTrack.boolean({
    required super.timing,
    required this.target,
    required this.kind,
    required this.boolValue,
  }) : paintValue = null;

  /// Creates a paint `<set>` track for `fill` or `stroke`.
  /// 创建一个用于 `fill` 或 `stroke` 的画刷型 `<set>` 轨道。
  ///
  /// - [timing]: Timing evaluator. 时间轴求值器。
  /// - [target]: Target element. 目标元素。
  /// - [kind]: Paint target kind. 画刷目标属性类型。
  /// - [paintValue]: Paint server applied while active. 激活期间应用的画刷。
  SvgSetAnimationTrack.paint({
    required super.timing,
    required this.target,
    required this.kind,
    required SvgPaintServer this.paintValue,
  }) : boolValue = false;

  /// Applies the discrete target state when this track is active at [elapsedUs].
  /// 当轨道在微秒时间点 [elapsedUs] 处于活跃状态时应用目标离散值。
  ///
  /// - [elapsedUs]: Virtual timeline timestamp in microseconds. 虚拟时间轴微秒时间戳。
  @override
  void applyAt(int elapsedUs) {
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    switch (kind) {
      case SvgSetTargetKind.displayNone:
        target.style.displayNone = boolValue;
      case SvgSetTargetKind.visibilityHidden:
        target.style.visibilityHidden = boolValue;
      case SvgSetTargetKind.fillPaint:
        final p = paintValue;
        if (p != null) {
          target.style.resolvedFill = p;
          target.style.currentFillColor = p.color;
        }
      case SvgSetTargetKind.strokePaint:
        final p = paintValue;
        if (p != null) {
          target.style.resolvedStroke = p;
          target.style.currentStrokeColor = p.color;
        }
    }
  }
}
