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
class SvgImageNode extends SvgElement {
  final String? href;
  final double baseX;
  final double baseY;
  final double baseWidth;
  final double baseHeight;
  final SvgPreserveAspectRatio preserveAspectRatio;

  double currentX;
  double currentY;
  double currentWidth;
  double currentHeight;

  ui.Image? _decodedImage;
  CompiledSvgScene? _nestedSvgScene;
  Future<void>? _decodeFuture;
  bool _decodeAttempted = false;

  final Float64List _aspectMatrix = SvgMatrixMath.createIdentity();

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
  bool get isLoaded => _decodedImage != null || _nestedSvgScene != null;

  @override
  void initializeGeometry(SvgDocument document) {
    cachedBounds = ui.Rect.fromLTWH(baseX, baseY, baseWidth, baseHeight);
    finalizeBaseTransforms(document.viewBox);
    _startDecodeIfNeeded(document);
  }

  /// Ensures any embedded raster Data URI has finished decoding.
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
