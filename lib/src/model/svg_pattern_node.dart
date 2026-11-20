import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_container_nodes.dart';
import 'svg_document.dart';
import 'svg_gradient.dart';
import 'svg_preserve_aspect_ratio.dart';
import 'svg_transform.dart';

/// `<pattern>` paint server node (W3C SVG 1.1 §13.3 / SVG 2).
/// `<pattern>` 图案画刷节点：离屏光栅化单个平铺瓦片并缓存为重复 `ui.ImageShader`。
class SvgPatternNode extends SvgGroupNode {
  /// Optional template pattern `id` referenced via `href` / `xlink:href`. 模板继承引用 ID。
  final String? hrefId;

  /// Coordinate units for tile rect (`patternUnits`). 瓦片区域坐标单位。
  final SvgGradientUnits patternUnits;

  /// Coordinate units for tile content (`patternContentUnits`). 瓦片内容坐标单位。
  final SvgGradientUnits patternContentUnits;

  /// Tile origin X coordinate. 瓦片原点 X。
  final double x;

  /// Tile origin Y coordinate. 瓦片原点 Y。
  final double y;

  /// Tile width. 瓦片宽度。
  final double width;

  /// Tile height. 瓦片高度。
  final double height;

  /// Optional tile `viewBox`. 可选瓦片 `viewBox`。
  final ui.Rect? innerViewBox;

  /// Aspect ratio rule for [innerViewBox]. 瓦片 `viewBox` 长宽比规则。
  final SvgPreserveAspectRatio preserveAspectRatio;

  /// Static `patternTransform` operations. 静态 `patternTransform` 变换操作列表。
  final List<SvgTransformOp> basePatternTransformOps;

  final Float64List _patternTransformMatrix = SvgMatrixMath.createIdentity();
  final Float64List _shaderMatrix = SvgMatrixMath.createIdentity();
  final Float64List _viewBoxMatrix = SvgMatrixMath.createIdentity();

  ui.Image? _cachedTileImage;
  int _cachedPxWidth = 0;
  int _cachedPxHeight = 0;

  /// Creates an [SvgPatternNode]. 创建一个 [SvgPatternNode] 图案填充节点。
  SvgPatternNode({
    super.id,
    super.classes,
    required super.style,
    super.children,
    this.hrefId,
    this.patternUnits = SvgGradientUnits.objectBoundingBox,
    this.patternContentUnits = SvgGradientUnits.userSpaceOnUse,
    this.x = 0.0,
    this.y = 0.0,
    this.width = 0.0,
    this.height = 0.0,
    this.innerViewBox,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
    this.basePatternTransformOps = const [],
  }) : super(tagName: 'pattern') {
    for (int i = 0; i < basePatternTransformOps.length; i++) {
      SvgMatrixMath.applyOpInPlace(
        _patternTransformMatrix,
        basePatternTransformOps[i],
      );
    }
  }

  @override
  bool get shouldCacheStaticPicture => false;

  /// Resolves inherited children from an `href`/`xlink:href` template `<pattern>` in [patternsById].
  /// 从 [patternsById] 解析并继承模板 `<pattern>` 的子节点。
  ///
  /// - [patternsById]: Document patterns registry. 文档图案注册表。
  void resolveTemplate(Map<String, SvgPatternNode> patternsById) {
    if (children.isEmpty && hrefId != null) {
      final template = patternsById[hrefId!];
      if (template != null && !identical(template, this)) {
        children.addAll(template.children);
      }
    }
  }

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <pattern> is a paint server and never painted directly.
  }

  /// Creates a repeating [ui.ImageShader] for [targetBounds] using [document].
  /// 为目标包围盒 [targetBounds] 构建循环平铺的 [ui.ImageShader]。
  ///
  /// - [targetBounds]: Target geometry local bounding box. 目标几何局部包围盒。
  /// - [document]: Owning [SvgDocument]. 所属 SVG 文档。
  ui.Shader? createShader(ui.Rect targetBounds, SvgDocument document) {
    final double tileX;
    final double tileY;
    final double tileW;
    final double tileH;

    if (patternUnits == SvgGradientUnits.objectBoundingBox) {
      tileX = targetBounds.left + x * targetBounds.width;
      tileY = targetBounds.top + y * targetBounds.height;
      tileW = width * targetBounds.width;
      tileH = height * targetBounds.height;
    } else {
      tileX = x;
      tileY = y;
      tileW = width;
      tileH = height;
    }

    if (tileW <= 1e-4 || tileH <= 1e-4) return null;

    // Supersample small tiles up to 2x for crisp edges, capped at 512px per side
    final double dpr = (tileW < 64.0 || tileH < 64.0) ? 2.0 : 1.0;
    final int pxW = (tileW * dpr).ceil().clamp(1, 512);
    final int pxH = (tileH * dpr).ceil().clamp(1, 512);

    final needsRebuild =
        isAnimated ||
        _cachedTileImage == null ||
        _cachedPxWidth != pxW ||
        _cachedPxHeight != pxH;

    if (needsRebuild) {
      _cachedTileImage?.dispose();
      _cachedTileImage = null;

      final recorder = ui.PictureRecorder();
      final recCanvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0.0, 0.0, pxW.toDouble(), pxH.toDouble()),
      );

      final scaleToPxX = pxW / tileW;
      final scaleToPxY = pxH / tileH;
      recCanvas.scale(scaleToPxX, scaleToPxY);

      if (innerViewBox != null) {
        preserveAspectRatio.computeMatrixInPlace(
          innerViewBox!,
          ui.Size(tileW, tileH),
          _viewBoxMatrix,
        );
        recCanvas.transform(_viewBoxMatrix);
      } else if (patternContentUnits == SvgGradientUnits.objectBoundingBox &&
          targetBounds.width > 0.0 &&
          targetBounds.height > 0.0) {
        recCanvas.scale(targetBounds.width, targetBounds.height);
      }

      super.paintContent(recCanvas, document, 1.0);
      final picture = recorder.endRecording();
      _cachedTileImage = picture.toImageSync(pxW, pxH);
      picture.dispose();
      _cachedPxWidth = pxW;
      _cachedPxHeight = pxH;
    }

    final tileImage = _cachedTileImage;
    if (tileImage == null) return null;

    SvgMatrixMath.resetToIdentity(_shaderMatrix);
    SvgMatrixMath.multiply4x4InPlace(_shaderMatrix, _patternTransformMatrix);
    SvgMatrixMath.translateInPlace(_shaderMatrix, tileX, tileY);
    SvgMatrixMath.scaleInPlace(_shaderMatrix, tileW / pxW, tileH / pxH);

    return ui.ImageShader(
      tileImage,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      _shaderMatrix,
    );
  }

  @override
  void dispose() {
    _cachedTileImage?.dispose();
    _cachedTileImage = null;
    super.dispose();
  }
}
