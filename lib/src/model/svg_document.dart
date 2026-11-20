import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_container_nodes.dart';
import 'svg_element.dart';
import 'svg_filter_node.dart';
import 'svg_geometry_node.dart';
import 'svg_gradient.dart';
import 'svg_image_node.dart';
import 'svg_marker_node.dart';
import 'svg_mask_node.dart';
import 'svg_pattern_node.dart';
import 'svg_preserve_aspect_ratio.dart';
import 'svg_transform.dart';
import 'svg_viewport_nodes.dart';

/// Top-level precompiled `<svg>` document containing the scene graph, gradients,
/// patterns, masks, markers, filters, views, defs, clipPaths, and embedded images.
/// 顶层预编译 `<svg>` 文档对象，包含场景图及渐变、图案、遮罩、标记、滤镜、视图、裁剪路径与内嵌位图注册表。
class SvgDocument {
  /// Explicit root `<svg width>` in user-space pixels, if specified.
  /// 根 `<svg>` 显式声明的宽度（像素）；未声明时为 `null`。
  final double? width;

  /// Explicit root `<svg height>` in user-space pixels, if specified.
  /// 根 `<svg>` 显式声明的高度（像素）；未声明时为 `null`。
  final double? height;

  /// Root SVG `viewBox` rectangle.
  /// 根 SVG 的 `viewBox` 视口坐标矩形。
  final ui.Rect viewBox;

  /// Root `preserveAspectRatio` alignment and scaling rule.
  /// 根 `<svg>` 的 `preserveAspectRatio` 对齐与缩放规则。
  final SvgPreserveAspectRatio preserveAspectRatio;

  /// Root `<svg>` container group holding the rendered scene tree.
  /// 承载整棵渲染场景树的根容器分组节点。
  final SvgGroupNode rootGroup;

  /// All scene elements indexed by XML `id`. 按 XML `id` 索引的全部场景元素表。
  final Map<String, SvgElement> elementsById;

  /// `<defs>` and `<symbol>` elements indexed by `id`. 按 `id` 索引的 `<defs>` 与 `<symbol>` 表。
  final Map<String, SvgElement> defsById;

  /// `<linearGradient>` and `<radialGradient>` definitions indexed by `id`. 按 `id` 索引的渐变定义表。
  final Map<String, SvgGradientNode> gradientsById;

  /// `<clipPath>` definitions indexed by `id`. 按 `id` 索引的裁剪路径定义表。
  final Map<String, SvgClipPathNode> clipPathsById;

  /// Geometry nodes indexed by `id` (used by `<mpath>` and `<textPath>`). 按 `id` 索引的几何节点表。
  final Map<String, SvgGeometryNode> geometryById;

  /// `<mask>` definitions indexed by `id`. 按 `id` 索引的遮罩定义表。
  final Map<String, SvgMaskNode> masksById;

  /// `<pattern>` definitions indexed by `id`. 按 `id` 索引的图案填充定义表。
  final Map<String, SvgPatternNode> patternsById;

  /// `<marker>` definitions indexed by `id`. 按 `id` 索引的路径端点标记定义表。
  final Map<String, SvgMarkerNode> markersById;

  /// `<filter>` definitions indexed by `id`. 按 `id` 索引的滤镜管线定义表。
  final Map<String, SvgFilterNode> filtersById;

  /// Named `<view>` definitions indexed by `id`. 按 `id` 索引的命名 `<view>` 视口表。
  final Map<String, SvgViewNode> viewsById;

  /// All embedded `<image>` nodes requiring asynchronous decoding. 文档中所有内嵌 `<image>` 节点列表。
  final List<SvgImageNode> imageNodes;

  /// Optional callback invoked when an asynchronous `<image>` finishes decoding.
  /// 当异步 `<image>` 解码完成时触发的可选重绘回调。
  ui.VoidCallback? onAsyncAssetLoaded;

  /// Pre-allocated viewBox transformation matrix buffer.
  /// 预分配的 `viewBox` 4×4 变换矩阵缓冲区。
  final Float64List viewBoxMatrix = SvgMatrixMath.createIdentity();

  /// Creates an [SvgDocument]. 创建一个 [SvgDocument] 预编译文档对象。
  ///
  /// - [width]: Optional explicit root width. 可选显式根宽度。
  /// - [height]: Optional explicit root height. 可选显式根高度。
  /// - [viewBox]: Root `viewBox` rectangle. 根 `viewBox` 矩形。
  /// - [preserveAspectRatio]: Root aspect ratio rule. 根长宽比缩放规则。
  /// - [rootGroup]: Root scene container group. 根场景容器节点。
  /// - [elementsById]: Global elements map by `id`. 全局元素映射表。
  /// - [defsById]: Definitions map by `id`. `<defs>` 映射表。
  /// - [gradientsById]: Gradients map by `id`. 渐变映射表。
  /// - [clipPathsById]: Clip paths map by `id`. 裁剪路径映射表。
  /// - [geometryById]: Geometry nodes map by `id`. 几何节点映射表。
  /// - [masksById]: Masks map by `id`. 遮罩映射表。
  /// - [patternsById]: Patterns map by `id`. 图案映射表。
  /// - [markersById]: Markers map by `id`. 标记映射表。
  /// - [filtersById]: Filters map by `id`. 滤镜映射表。
  /// - [viewsById]: Named views map by `id`. 命名视图映射表。
  /// - [imageNodes]: Embedded image nodes list. 内嵌图像节点列表。
  SvgDocument({
    this.width,
    this.height,
    required this.viewBox,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
    required this.rootGroup,
    required this.elementsById,
    required this.defsById,
    required this.gradientsById,
    required this.clipPathsById,
    required this.geometryById,
    this.masksById = const {},
    this.patternsById = const {},
    this.markersById = const {},
    this.filtersById = const {},
    this.viewsById = const {},
    this.imageNodes = const [],
  });

  /// Intrinsic size of the SVG document.
  /// SVG 文档的固有尺寸（优先使用显式 `width`/`height`，否则回退到 `viewBox` 尺寸）。
  ui.Size get intrinsicSize =>
      ui.Size(width ?? viewBox.width, height ?? viewBox.height);

  /// Resolves the active `viewBox`, honoring an optional named `<view id="...">`.
  /// 解析当前生效的 `viewBox`，若指定了有效的 [viewId] 则采用对应 `<view>` 的 `viewBox`。
  ///
  /// - [viewId]: Optional `<view>` ID. 可选命名视图 ID。
  ui.Rect resolveViewBox(String? viewId) {
    if (viewId != null && viewId.isNotEmpty) {
      final view = viewsById[viewId];
      if (view?.viewBox != null) return view!.viewBox!;
    }
    return viewBox;
  }

  /// Resolves the active `preserveAspectRatio`, honoring an optional `<view>`.
  /// 解析当前生效的 `preserveAspectRatio`，若指定了有效的 [viewId] 则采用对应 `<view>` 的设置。
  ///
  /// - [viewId]: Optional `<view>` ID. 可选命名视图 ID。
  SvgPreserveAspectRatio resolvePreserveAspectRatio(String? viewId) {
    if (viewId != null && viewId.isNotEmpty) {
      final view = viewsById[viewId];
      if (view?.preserveAspectRatio != null) return view!.preserveAspectRatio!;
    }
    return preserveAspectRatio;
  }

  /// Notifies listeners (e.g. `AnimatedSvgPicture`) that an async `<image>` is ready.
  /// 通知监听者（如 `AnimatedSvgPicture`）异步 `<image>` 已解码就绪，并失效旧的静态 `ui.Picture` 缓存。
  void notifyAsyncAssetLoaded() {
    rootGroup.invalidatePictureCache();
    for (final def in defsById.values) {
      def.invalidatePictureCache();
    }
    for (final mask in masksById.values) {
      mask.invalidatePictureCache();
    }
    for (final pattern in patternsById.values) {
      pattern.invalidatePictureCache();
    }
    for (final marker in markersById.values) {
      marker.invalidatePictureCache();
    }
    onAsyncAssetLoaded?.call();
  }

  /// Waits for all embedded `<image>` Data URIs in this document to decode.
  /// 等待文档中所有内嵌 `<image>` Data URI 异步解码完成。
  Future<void> precacheImages() async {
    if (imageNodes.isEmpty) return;
    await Future.wait([for (final img in imageNodes) img.ensureDecoded(this)]);
  }

  /// Initializes all node geometries, resolves gradient/pattern templates, and
  /// propagates `isAnimated` flags bottom-up through the AST.
  /// 初始化全部节点几何与包围盒、解析渐变/图案模板继承，并自底向上传播 `isAnimated` 标志。
  void initialize() {
    for (final gradient in gradientsById.values) {
      gradient.resolveTemplate(gradientsById);
    }
    for (final pattern in patternsById.values) {
      pattern.resolveTemplate(patternsById);
    }
    for (final def in defsById.values) {
      def.initializeGeometry(this);
    }
    for (final clip in clipPathsById.values) {
      clip.initializeGeometry(this);
      clip.propagateAnimationFlags(this);
    }
    for (final mask in masksById.values) {
      mask.initializeGeometry(this);
      mask.propagateAnimationFlags(this);
    }
    for (final pattern in patternsById.values) {
      pattern.initializeGeometry(this);
      pattern.propagateAnimationFlags(this);
    }
    for (final marker in markersById.values) {
      marker.initializeGeometry(this);
      marker.propagateAnimationFlags(this);
    }
    rootGroup.initializeGeometry(this);
    rootGroup.propagateAnimationFlags(this);
  }

  /// Paints the document at its current timeline state into [canvas] scaled to [canvasSize].
  /// 按当前时间轴状态将整份文档绘制到目标尺寸为 [canvasSize] 的 [canvas] 上。
  ///
  /// Per W3C SVG 1.1 §14.3.3 / SVG 2, the root `<svg>` viewport clips to
  /// `[0, 0, canvasSize.width, canvasSize.height]` unless `overflow="visible"`
  /// is explicitly specified.
  /// 依据 W3C SVG 规范，根 `<svg>` 默认启用视口裁剪，除非显式声明 `overflow="visible"`。
  ///
  /// - [canvas]: Target Flutter canvas. 目标 Flutter 画布。
  /// - [canvasSize]: Target viewport size. 目标视口尺寸。
  /// - [viewId]: Optional `<view id="...">` override. 可选命名视图 ID。
  void paint(ui.Canvas canvas, ui.Size canvasSize, {String? viewId}) {
    if (canvasSize.isEmpty) return;
    final activeViewBox = resolveViewBox(viewId);
    final activeAspect = resolvePreserveAspectRatio(viewId);
    activeAspect.computeMatrixInPlace(activeViewBox, canvasSize, viewBoxMatrix);
    canvas.save();
    if (rootGroup.style.baseOverflowVisible != true) {
      canvas.clipRect(
        ui.Rect.fromLTWH(0.0, 0.0, canvasSize.width, canvasSize.height),
      );
    }
    canvas.transform(viewBoxMatrix);
    rootGroup.paint(canvas, this);
    canvas.restore();
  }

  /// Releases any cached `ui.Picture` and `ui.Image` resources held by the document.
  /// 释放文档持有的全部 `ui.Picture` 与 `ui.Image` GPU 缓存资源。
  void dispose() {
    onAsyncAssetLoaded = null;
    rootGroup.dispose();
    for (final def in defsById.values) {
      def.dispose();
    }
    for (final mask in masksById.values) {
      mask.dispose();
    }
    for (final pattern in patternsById.values) {
      pattern.dispose();
    }
    for (final marker in markersById.values) {
      marker.dispose();
    }
    for (final filter in filtersById.values) {
      filter.dispose();
    }
  }
}
