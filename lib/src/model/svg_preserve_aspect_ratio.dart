import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_transform.dart';

/// Alignment mode for SVG `preserveAspectRatio`.
/// SVG `preserveAspectRatio` 的对齐模式枚举。
enum SvgAspectRatioAlign {
  /// Non-uniform scaling stretching `viewBox` to fill the viewport (`none`). 非等比拉伸填满。
  none,

  /// Aligns min-X and min-Y (`xMinYMin`). 左上角对齐。
  xMinYMin,

  /// Aligns mid-X and min-Y (`xMidYMin`). 顶部居中对齐。
  xMidYMin,

  /// Aligns max-X and min-Y (`xMaxYMin`). 右上角对齐。
  xMaxYMin,

  /// Aligns min-X and mid-Y (`xMinYMid`). 左侧居中对齐。
  xMinYMid,

  /// Aligns mid-X and mid-Y (`xMidYMid`, SVG default). 水平垂直居中对齐（默认）。
  xMidYMid,

  /// Aligns max-X and mid-Y (`xMaxYMid`). 右侧居中对齐。
  xMaxYMid,

  /// Aligns min-X and max-Y (`xMinYMax`). 左下角对齐。
  xMinYMax,

  /// Aligns mid-X and max-Y (`xMidYMax`). 底部居中对齐。
  xMidYMax,

  /// Aligns max-X and max-Y (`xMaxYMax`). 右下角对齐。
  xMaxYMax,
}

/// Meet or slice scaling mode for SVG `preserveAspectRatio`.
/// SVG `preserveAspectRatio` 的等比缩放模式（包含或裁剪）。
enum SvgMeetOrSlice {
  /// Uniformly scales so the entire `viewBox` fits inside the viewport (`meet`). 完整包含（类似 contain）。
  meet,

  /// Uniformly scales so the viewport is completely covered (`slice`). 覆盖填满（类似 cover）。
  slice,
}

/// Precompiled `preserveAspectRatio` configuration.
/// 预编译的 SVG `preserveAspectRatio` 长宽比与对齐配置。
class SvgPreserveAspectRatio {
  /// Alignment rule within the viewport. 视口内的对齐规则。
  final SvgAspectRatioAlign align;

  /// Scaling strategy (`meet` or `slice`). 缩放策略（`meet` 或 `slice`）。
  final SvgMeetOrSlice meetOrSlice;

  /// Creates an [SvgPreserveAspectRatio].
  /// 创建一个 [SvgPreserveAspectRatio] 配置对象。
  ///
  /// - [align]: Alignment mode (defaults to [SvgAspectRatioAlign.xMidYMid]). 对齐模式。
  /// - [meetOrSlice]: Scaling strategy (defaults to [SvgMeetOrSlice.meet]). 缩放策略。
  const SvgPreserveAspectRatio({
    this.align = SvgAspectRatioAlign.xMidYMid,
    this.meetOrSlice = SvgMeetOrSlice.meet,
  });

  /// Default SVG `preserveAspectRatio` (`xMidYMid meet`).
  /// SVG 默认长宽比配置（`xMidYMid meet`）。
  static const SvgPreserveAspectRatio defaultValue = SvgPreserveAspectRatio();

  /// Computes the 4×4 transformation matrix mapping [viewBox] into [viewportSize]
  /// in-place into [outMatrix] without allocating memory.
  /// 原地计算将 [viewBox] 映射到 [viewportSize] 的 4×4 变换矩阵并写入 [outMatrix]（零分配）。
  ///
  /// - [viewBox]: Source SVG `viewBox` rect. 源 `viewBox` 矩形。
  /// - [viewportSize]: Destination viewport size. 目标视口尺寸。
  /// - [outMatrix]: Pre-allocated 16-element column-major matrix buffer. 预分配 16 元素矩阵缓冲。
  void computeMatrixInPlace(
    ui.Rect viewBox,
    ui.Size viewportSize,
    Float64List outMatrix,
  ) {
    SvgMatrixMath.resetToIdentity(outMatrix);
    if (viewBox.width <= 0.0 ||
        viewBox.height <= 0.0 ||
        viewportSize.width <= 0.0 ||
        viewportSize.height <= 0.0) {
      return;
    }

    final scaleX = viewportSize.width / viewBox.width;
    final scaleY = viewportSize.height / viewBox.height;

    if (align == SvgAspectRatioAlign.none) {
      SvgMatrixMath.scaleInPlace(outMatrix, scaleX, scaleY);
      SvgMatrixMath.translateInPlace(outMatrix, -viewBox.left, -viewBox.top);
      return;
    }

    final uniformScale = meetOrSlice == SvgMeetOrSlice.meet
        ? math.min(scaleX, scaleY)
        : math.max(scaleX, scaleY);

    final scaledWidth = viewBox.width * uniformScale;
    final scaledHeight = viewBox.height * uniformScale;
    final spareX = viewportSize.width - scaledWidth;
    final spareY = viewportSize.height - scaledHeight;

    double offsetX = 0.0;
    double offsetY = 0.0;

    switch (align) {
      case SvgAspectRatioAlign.xMinYMin:
      case SvgAspectRatioAlign.xMinYMid:
      case SvgAspectRatioAlign.xMinYMax:
        offsetX = 0.0;
      case SvgAspectRatioAlign.xMidYMin:
      case SvgAspectRatioAlign.xMidYMid:
      case SvgAspectRatioAlign.xMidYMax:
        offsetX = spareX * 0.5;
      case SvgAspectRatioAlign.xMaxYMin:
      case SvgAspectRatioAlign.xMaxYMid:
      case SvgAspectRatioAlign.xMaxYMax:
        offsetX = spareX;
      case SvgAspectRatioAlign.none:
        break;
    }

    switch (align) {
      case SvgAspectRatioAlign.xMinYMin:
      case SvgAspectRatioAlign.xMidYMin:
      case SvgAspectRatioAlign.xMaxYMin:
        offsetY = 0.0;
      case SvgAspectRatioAlign.xMinYMid:
      case SvgAspectRatioAlign.xMidYMid:
      case SvgAspectRatioAlign.xMaxYMid:
        offsetY = spareY * 0.5;
      case SvgAspectRatioAlign.xMinYMax:
      case SvgAspectRatioAlign.xMidYMax:
      case SvgAspectRatioAlign.xMaxYMax:
        offsetY = spareY;
      case SvgAspectRatioAlign.none:
        break;
    }

    SvgMatrixMath.translateInPlace(outMatrix, offsetX, offsetY);
    SvgMatrixMath.scaleInPlace(outMatrix, uniformScale, uniformScale);
    SvgMatrixMath.translateInPlace(outMatrix, -viewBox.left, -viewBox.top);
  }
}
