import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../controller/animated_svg_controller.dart';
import '../parser/svg_xml_parser.dart';

/// Zero-allocation [CustomPainter] that advances the precompiled `SvgTimelineEngine`
/// and paints the `SvgDocument` scene graph directly onto the [ui.Canvas].
///
/// 零堆分配 [CustomPainter]，负责推进预编译的 `SvgTimelineEngine`
/// 并将 `SvgDocument` 场景图直接绘制到 [ui.Canvas] 上。
class AnimatedSvgPainter extends CustomPainter {
  /// Precompiled SVG document and timeline scene.
  /// 预编译后的 SVG 文档与时间轴场景。
  final CompiledSvgScene scene;

  /// Playback controller supplying the current virtual timeline timestamp.
  /// 提供当前虚拟时间轴时间戳的播放控制器。
  final AnimatedSvgController controller;

  /// Clipping behavior applied to the widget paint bounds.
  /// 应用于组件绘制边界的裁剪方式。
  final Clip clipBehavior;

  /// How the SVG intrinsic size is fitted into the painter's layout size.
  /// SVG 固有尺寸拟合到绘制区域尺寸的缩放策略。
  final BoxFit fit;

  /// Resolved alignment placing the fitted rect inside leftover or cropped space.
  /// 将拟合矩形安放在剩余或裁剪空间中的已解析对齐方式。
  final Alignment alignment;

  /// Optional named `<view id="...">` identifier overriding the active `viewBox`.
  /// 可选的命名 `<view id="...">` 标识，用于覆盖当前生效的 `viewBox`。
  final String? viewId;

  /// Creates an [AnimatedSvgPainter].
  /// 创建一个 [AnimatedSvgPainter] 实例。
  ///
  /// - [scene]: Compiled SVG scene to paint. 待绘制的已编译 SVG 场景。
  /// - [controller]: Controller providing playback time and repaint notifications.
  ///   提供播放时间与重绘通知的控制器。
  /// - [clipBehavior]: Canvas clip behavior (defaults to [Clip.hardEdge]).
  ///   画布裁剪行为（默认 [Clip.hardEdge]）。
  /// - [fit]: BoxFit mapping intrinsic SVG bounds to paint size (defaults to [BoxFit.contain]).
  ///   将 SVG 固有尺寸映射到绘制区域的填充方式（默认 [BoxFit.contain]）。
  /// - [alignment]: Alignment within layout bounds (defaults to [Alignment.center]).
  ///   在布局边界内的对齐方式（默认 [Alignment.center]）。
  /// - [viewId]: Optional `<view>` ID to activate. 可选要激活的 `<view>` ID。
  /// - [repaint]: Optional merged [Listenable] overriding [controller] as the repaint trigger.
  ///   可选的重绘触发 [Listenable]，默认使用 [controller]。
  AnimatedSvgPainter({
    required this.scene,
    required this.controller,
    this.clipBehavior = Clip.hardEdge,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.viewId,
    Listenable? repaint,
  }) : super(repaint: repaint ?? controller);

  /// Evaluates the timeline at the controller's current timestamp and paints [scene]
  /// into [canvas] within [size].
  /// 按控制器当前时间戳求值时间轴，并将 [scene] 绘制到 [size] 范围内的 [canvas] 上。
  ///
  /// - [canvas]: Target Flutter canvas. 目标 Flutter 画布。
  /// - [size]: Available paint area size. 可用绘制区域尺寸。
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (size.isEmpty) return;

    // 1. Evaluate all precompiled SMIL & CSS animation tracks in-place
    scene.timeline.seekMicroseconds(controller.elapsedMicroseconds);

    final intrinsic = scene.document.intrinsicSize;
    if (intrinsic.width <= 0.0 || intrinsic.height <= 0.0) {
      return;
    }

    // 2. Fit the SVG intrinsic box into the widget layout size.
    //    [alignment] places the fitted rect inside leftover / cropped space.
    final fitted = applyBoxFit(fit, intrinsic, size);
    if (fitted.source.isEmpty || fitted.destination.isEmpty) {
      return;
    }
    final inputSubrect = alignment.inscribe(
      fitted.source,
      ui.Offset.zero & intrinsic,
    );
    final outputSubrect = alignment.inscribe(
      fitted.destination,
      ui.Offset.zero & size,
    );

    canvas.save();
    if (clipBehavior != Clip.none) {
      canvas.clipRect(ui.Offset.zero & size);
    }

    final scaleX = outputSubrect.width / inputSubrect.width;
    final scaleY = outputSubrect.height / inputSubrect.height;
    canvas.translate(outputSubrect.left, outputSubrect.top);
    canvas.scale(scaleX, scaleY);
    canvas.translate(-inputSubrect.left, -inputSubrect.top);

    // Paint into the intrinsic viewport; SVG preserveAspectRatio still applies
    // for viewBox → intrinsic. Widget [fit] then maps intrinsic → [size].
    scene.document.paint(canvas, intrinsic, viewId: viewId);
    canvas.restore();
  }

  /// Returns `true` when any scene, controller, layout, or view parameter changed.
  /// 当场景、控制器、布局或视图参数发生变化时返回 `true`。
  ///
  /// - [oldDelegate]: Previous painter instance for comparison. 用于比较的旧绘制器实例。
  @override
  bool shouldRepaint(covariant AnimatedSvgPainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.controller != controller ||
        oldDelegate.clipBehavior != clipBehavior ||
        oldDelegate.fit != fit ||
        oldDelegate.alignment != alignment ||
        oldDelegate.viewId != viewId;
  }
}
