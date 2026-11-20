import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../parser/svg_xml_parser.dart';
import 'svg_document.dart';
import 'svg_element.dart';
import 'svg_preserve_aspect_ratio.dart';
import 'svg_transform.dart';

/// `<image>` graphics element supporting embedded raster Data URIs
/// (`data:image/png;base64,...`, `jpeg`, `webp`, `gif`) and embedded SVG Data
/// URIs (`data:image/svg+xml,...`), positioned with `x`/`y`/`width`/`height`
/// and `preserveAspectRatio` (W3C SVG 1.1 §5.7 / SVG 2).
/// `<image>` 图像元素节点，支持内嵌光栅位图与 SVG Data URI 的解码、缩放与渲染。
class SvgImageNode extends SvgElement {
  /// Raw `href` / `xlink:href` Data URI. 原始图像 Data URI。
  final String? href;

  /// Base X coordinate. 基础 X 坐标。
  final double baseX;

  /// Base Y coordinate. 基础 Y 坐标。
  final double baseY;

  /// Base width. 基础宽度。
  final double baseWidth;

  /// Base height. 基础高度。
  final double baseHeight;

  /// Aspect ratio scaling and alignment rule. 长宽比缩放与对齐规则。
  final SvgPreserveAspectRatio preserveAspectRatio;

  /// Active runtime X coordinate. 运行时 X 坐标。
  double currentX;

  /// Active runtime Y coordinate. 运行时 Y 坐标。
  double currentY;

  /// Active runtime width. 运行时宽度。
  double currentWidth;

  /// Active runtime height. 运行时高度。
  double currentHeight;

  ui.Image? _decodedImage;
  CompiledSvgScene? _nestedSvgScene;
  Future<void>? _decodeFuture;
  bool _decodeAttempted = false;

  final Float64List _aspectMatrix = SvgMatrixMath.createIdentity();

  /// Creates an [SvgImageNode]. 创建一个 [SvgImageNode] 内嵌图像节点。
  SvgImageNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.href,
    this.baseX = 0.0,
    this.baseY = 0.0,
    this.baseWidth = 0.0,
    this.baseHeight = 0.0,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
  }) : currentX = baseX,
       currentY = baseY,
       currentWidth = baseWidth,
       currentHeight = baseHeight,
       super(tagName: 'image');

  @override
  bool get shouldCacheStaticPicture => false;

  /// Whether a raster image or embedded SVG scene is ready to paint.
  /// 位图或内嵌 SVG 场景是否已解码就绪。
  bool get isLoaded => _decodedImage != null || _nestedSvgScene != null;

  @override
  void initializeGeometry(SvgDocument document) {
    cachedBounds = ui.Rect.fromLTWH(baseX, baseY, baseWidth, baseHeight);
    finalizeBaseTransforms(document.viewBox);
    _startDecodeIfNeeded(document);
  }

  /// Ensures any embedded raster Data URI has finished decoding within [document].
  /// 确保内嵌光栅 Data URI 在 [document] 中完成异步解码。
  ///
  /// - [document]: Owning [SvgDocument] notified upon decode completion. 所属 SVG 文档。
  Future<void> ensureDecoded(SvgDocument document) {
    _startDecodeIfNeeded(document);
    return _decodeFuture ?? Future<void>.value();
  }

  void _startDecodeIfNeeded(SvgDocument document) {
    if (_decodeAttempted) return;
    _decodeAttempted = true;
    final raw = href?.trim();
    if (raw == null || raw.isEmpty || !raw.startsWith('data:')) return;

    final commaIdx = raw.indexOf(',');
    if (commaIdx <= 5) return;

    final meta = raw.substring(5, commaIdx).toLowerCase();
    final payload = raw.substring(commaIdx + 1);
    final isBase64 = meta.contains(';base64');

    if (meta.startsWith('image/svg+xml')) {
      try {
        final xmlStr = isBase64
            ? utf8.decode(base64Decode(payload.replaceAll(RegExp(r'\s+'), '')))
            : Uri.decodeComponent(payload);
        _nestedSvgScene = SvgParser.compile(xmlStr);
      } catch (_) {
        // Malformed embedded SVG data URI -> omit gracefully
      }
      return;
    }

    if (isBase64) {
      try {
        final bytes = base64Decode(payload.replaceAll(RegExp(r'\s+'), ''));
        _decodeFuture = _decodeRasterBytes(bytes, document);
      } catch (_) {
        // Malformed base64 payload -> omit gracefully
      }
    }
  }

  Future<void> _decodeRasterBytes(Uint8List bytes, SvgDocument document) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _decodedImage?.dispose();
      _decodedImage = frame.image;
      codec.dispose();
      document.notifyAsyncAssetLoaded();
    } catch (_) {
      // Unsupported or corrupt image bytes -> omit gracefully
    }
  }

  @override
  void resetFrameState() {
    super.resetFrameState();
    currentX = baseX;
    currentY = baseY;
    currentWidth = baseWidth;
    currentHeight = baseHeight;
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    if (style.visibilityHidden) return;
    if (currentWidth <= 0.0 || currentHeight <= 0.0) return;

    final nested = _nestedSvgScene;
    if (nested != null) {
      final intrinsic = nested.document.intrinsicSize;
      if (intrinsic.isEmpty) return;
      canvas.save();
      canvas.translate(currentX, currentY);
      canvas.clipRect(ui.Rect.fromLTWH(0.0, 0.0, currentWidth, currentHeight));
      preserveAspectRatio.computeMatrixInPlace(
        ui.Rect.fromLTWH(0.0, 0.0, intrinsic.width, intrinsic.height),
        ui.Size(currentWidth, currentHeight),
        _aspectMatrix,
      );
      canvas.transform(_aspectMatrix);
      nested.document.paint(canvas, intrinsic);
      canvas.restore();
      return;
    }

    final img = _decodedImage;
    if (img == null) return;

    final srcRect = ui.Rect.fromLTWH(
      0.0,
      0.0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    preserveAspectRatio.computeMatrixInPlace(
      srcRect,
      ui.Size(currentWidth, currentHeight),
      _aspectMatrix,
    );

    canvas.save();
    canvas.translate(currentX, currentY);
    canvas.clipRect(ui.Rect.fromLTWH(0.0, 0.0, currentWidth, currentHeight));
    canvas.transform(_aspectMatrix);

    final paint = cachedFillPaint
      ..shader = null
      ..maskFilter = resolveMaskFilter()
      ..filterQuality = ui.FilterQuality.medium
      ..color = ui.Color.fromARGB(
        (effectiveOpacity.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255),
        255,
        255,
        255,
      );
    canvas.drawImage(img, ui.Offset.zero, paint);
    canvas.restore();
  }

  @override
  void dispose() {
    _decodedImage?.dispose();
    _decodedImage = null;
    _nestedSvgScene?.dispose();
    _nestedSvgScene = null;
    super.dispose();
  }
}
