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
/// patterns, masks, markers, views, defs, clipPaths, and precompiled animation timeline.
class SvgDocument {
  final double? width;
  final double? height;
  final ui.Rect viewBox;
  final SvgPreserveAspectRatio preserveAspectRatio;
  final SvgGroupNode rootGroup;

  final Map<String, SvgElement> elementsById;
  final Map<String, SvgElement> defsById;
  final Map<String, SvgGradientNode> gradientsById;
  final Map<String, SvgClipPathNode> clipPathsById;
  final Map<String, SvgGeometryNode> geometryById;
  final Map<String, SvgMaskNode> masksById;
  final Map<String, SvgPatternNode> patternsById;
  final Map<String, SvgMarkerNode> markersById;
  final Map<String, SvgFilterNode> filtersById;
  final Map<String, SvgViewNode> viewsById;
  final List<SvgImageNode> imageNodes;

  /// Optional callback invoked when an asynchronous `<image>` finishes decoding.
  ui.VoidCallback? onAsyncAssetLoaded;

  /// Pre-allocated viewBox transformation matrix buffer.
  final Float64List viewBoxMatrix = SvgMatrixMath.createIdentity();

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
  ui.Size get intrinsicSize =>
      ui.Size(width ?? viewBox.width, height ?? viewBox.height);

  /// Resolves the active `viewBox`, honoring an optional named `<view id="...">`.
  ui.Rect resolveViewBox(String? viewId) {
    if (viewId != null && viewId.isNotEmpty) {
      final view = viewsById[viewId];
      if (view?.viewBox != null) return view!.viewBox!;
    }
    return viewBox;
  }

  /// Resolves the active `preserveAspectRatio`, honoring an optional `<view>`.
  SvgPreserveAspectRatio resolvePreserveAspectRatio(String? viewId) {
    if (viewId != null && viewId.isNotEmpty) {
      final view = viewsById[viewId];
      if (view?.preserveAspectRatio != null) return view!.preserveAspectRatio!;
    }
    return preserveAspectRatio;
  }

  /// Notifies listeners (e.g. `AnimatedSvgPicture`) that an async `<image>` is ready.
  ///
  /// Also invalidates any cached static `ui.Picture` layers recorded prior to
  /// image decode completion so non-animated SVGs repaint with the decoded image.
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
  Future<void> precacheImages() async {
    if (imageNodes.isEmpty) return;
    await Future.wait([for (final img in imageNodes) img.ensureDecoded(this)]);
  }

  /// Initializes all node geometries, resolves gradient/pattern templates, and
  /// propagates `isAnimated` flags bottom-up through the AST.
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
  ///
  /// Per W3C SVG 1.1 §14.3.3 / SVG 2, the root `<svg>` viewport clips to
  /// `[0, 0, canvasSize.width, canvasSize.height]` unless `overflow="visible"`
  /// is explicitly specified.
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
