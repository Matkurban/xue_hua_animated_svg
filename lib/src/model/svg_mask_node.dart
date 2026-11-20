import 'dart:ui' as ui;

import 'svg_container_nodes.dart';
import 'svg_document.dart';
import 'svg_gradient.dart';

/// How `<mask>` pixel values map to transparency (SVG 2 `mask-type`).
/// `<mask>` 像素值映射为透明度的计算模式枚举（SVG 2 `mask-type`）。
enum SvgMaskType {
  /// Standard SVG luminance mask: `alpha = 0.2126*R + 0.7152*G + 0.0722*B`.
  /// 标准 SVG 亮度遮罩（Rec.709 亮度转 Alpha）。
  luminance,

  /// Direct alpha channel mask (`mask-type: alpha`).
  /// 直接使用 Alpha 通道作为遮罩（`mask-type: alpha`）。
  alpha,
}

/// `<mask>` compositing container node (W3C SVG 1.1 §14.4 / SVG 2).
/// `<mask>` 遮罩合成容器节点。
class SvgMaskNode extends SvgGroupNode {
  /// Coordinate units for the mask region (`maskUnits`). 遮罩区域坐标单位。
  final SvgGradientUnits maskUnits;

  /// Coordinate units for mask child geometry (`maskContentUnits`). 遮罩内容坐标单位。
  final SvgGradientUnits maskContentUnits;

  /// Mask compositing mode (`luminance` or `alpha`). 遮罩计算模式（亮度或 Alpha）。
  final SvgMaskType maskType;

  /// Mask region X coordinate. 遮罩区域 X 坐标。
  final double x;

  /// Mask region Y coordinate. 遮罩区域 Y 坐标。
  final double y;

  /// Mask region width. 遮罩区域宽度。
  final double width;

  /// Mask region height. 遮罩区域高度。
  final double height;

  /// Rec.709 luminance-to-alpha color filter matrix per W3C SVG masking spec.
  /// 遵循 W3C SVG 遮罩规范的 Rec.709 亮度转 Alpha 色彩矩阵滤镜。
  static const ui.ColorFilter luminanceToAlphaFilter = ui.ColorFilter.matrix(
    <double>[
      0.0, 0.0, 0.0, 0.0, 0.0, // R
      0.0, 0.0, 0.0, 0.0, 0.0, // G
      0.0, 0.0, 0.0, 0.0, 0.0, // B
      0.2126, 0.7152, 0.0722, 0.0, 0.0, // A = luminance
    ],
  );

  /// Creates an [SvgMaskNode]. 创建一个 [SvgMaskNode] 遮罩节点。
  SvgMaskNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    super.children,
    this.maskUnits = SvgGradientUnits.objectBoundingBox,
    this.maskContentUnits = SvgGradientUnits.userSpaceOnUse,
    this.maskType = SvgMaskType.luminance,
    this.x = -0.1,
    this.y = -0.1,
    this.width = 1.2,
    this.height = 1.2,
  }) : super(tagName: 'mask');

  @override
  bool get shouldCacheStaticPicture => false;

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <mask> is never painted directly; it is applied via applyMask().
  }

  /// Resolves the mask clipping/layer bounds in target user space for [targetBounds].
  /// 根据目标元素包围盒 [targetBounds] 解析遮罩图层作用区域。
  ///
  /// - [targetBounds]: Target element local bounding box. 目标元素局部包围盒。
  ui.Rect resolveMaskRegion(ui.Rect targetBounds) {
    if (maskUnits == SvgGradientUnits.objectBoundingBox) {
      return ui.Rect.fromLTWH(
        targetBounds.left + x * targetBounds.width,
        targetBounds.top + y * targetBounds.height,
        width * targetBounds.width,
        height * targetBounds.height,
      );
    }
    return ui.Rect.fromLTWH(x, y, width, height);
  }

  /// Renders the mask's children into the active `dstIn` mask layer on [canvas].
  /// 将遮罩子节点绘制到当前处于 `dstIn` 混合模式的遮罩图层 [canvas] 上。
  ///
  /// - [canvas]: Active mask layer canvas. 当前遮罩图层画布。
  /// - [document]: Owning [SvgDocument]. 所属 SVG 文档。
  /// - [targetBounds]: Target element local bounding box. 目标元素局部包围盒。
  void paintMaskContent(
    ui.Canvas canvas,
    SvgDocument document,
    ui.Rect targetBounds,
  ) {
    final isBBoxContent =
        maskContentUnits == SvgGradientUnits.objectBoundingBox;
    if (isBBoxContent) {
      if (targetBounds.width <= 0.0 || targetBounds.height <= 0.0) return;
      canvas.save();
      canvas.translate(targetBounds.left, targetBounds.top);
      canvas.scale(targetBounds.width, targetBounds.height);
    }

    super.paintContent(canvas, document, 1.0);

    if (isBBoxContent) {
      canvas.restore();
    }
  }
}
