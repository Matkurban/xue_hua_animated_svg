import 'dart:math' as math;
import 'dart:ui' as ui;

import 'svg_filter_node.dart';
import 'svg_transform.dart';

/// GPU-accelerated executor for [SvgFilterNode] filter graphs using Flutter's
/// native `ui.ImageFilter`, `ui.ColorFilter`, `ui.BlendMode`, `ui.Vertices`,
/// and `ui.Picture`.
abstract final class SvgFilterExecutor {
  static const ui.ColorFilter _sourceAlphaFilter = ui.ColorFilter.matrix(
    <double>[
      0.0, 0.0, 0.0, 0.0, 0.0, // R = 0
      0.0, 0.0, 0.0, 0.0, 0.0, // G = 0
      0.0, 0.0, 0.0, 0.0, 0.0, // B = 0
      0.0, 0.0, 0.0, 1.0, 0.0, // A = A
    ],
  );

  /// Paints [paintSource] through [filter] onto [canvas].
  ///
  /// Uses a zero-buffer `saveLayer` fast path for single-primitive filters and
  /// executes a full named-buffer `ui.Picture` graph for multi-step pipelines.
  static void paintWithFilter({
    required ui.Canvas canvas,
    required SvgFilterNode filter,
    required ui.Rect targetBounds,
    required void Function(ui.Canvas) paintSource,
  }) {
    if (filter.primitives.isEmpty) {
      paintSource(canvas);
      return;
    }

    final region = filter.resolveFilterRegion(targetBounds);

    // Fast path for common single-primitive filters on SourceGraphic
    if (filter.primitives.length == 1) {
      final prim = filter.primitives.first;
      final src = prim.inSource;
      final isDefaultSource =
          src == null || src.isEmpty || src == 'SourceGraphic';
      if (isDefaultSource &&
          _tryPaintSingleFastPath(canvas, prim, region, paintSource)) {
        return;
      }
    }

    // Full multi-step filter graph execution
    final buffers = <String, ui.Picture>{};
    final fieldBuffers = <String, SvgFilterPixelField>{};
    final ownedPictures = <ui.Picture>[];

    ui.Picture recordPicture(void Function(ui.Canvas) draw) {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec, region);
      draw(c);
      final pic = rec.endRecording();
      ownedPictures.add(pic);
      return pic;
    }

    try {
      final sourceGraphic = recordPicture(paintSource);
      buffers['SourceGraphic'] = sourceGraphic;

      ui.Picture? cachedSourceAlpha;
      ui.Picture getSourceAlpha() {
        cachedSourceAlpha ??= recordPicture((c) {
          c.saveLayer(region, ui.Paint()..colorFilter = _sourceAlphaFilter);
          c.drawPicture(sourceGraphic);
          c.restore();
        });
        return cachedSourceAlpha!;
      }

      ui.Picture lastResult = sourceGraphic;
      SvgFilterPixelField? lastField;

      ui.Picture resolveInput(String? name) {
        if (name == null || name.isEmpty) return lastResult;
        if (name == 'SourceGraphic') return sourceGraphic;
        if (name == 'SourceAlpha') return getSourceAlpha();
        return buffers[name] ?? lastResult;
      }

      SvgFilterPixelField? resolveField(String? name) {
        if (name == null || name.isEmpty) return lastField;
        return fieldBuffers[name];
      }

      for (final prim in filter.primitives) {
        SvgFilterPixelField? outField;
        final ui.Picture out = switch (prim) {
          SvgFeGaussianBlur() => () {
            final srcField = resolveField(prim.inSource);
            if (srcField != null) {
              outField = srcField.blurred(prim.sigmaX, prim.sigmaY);
            }
            return recordPicture((c) {
              final inp = resolveInput(prim.inSource);
              if (prim.sigmaX > 0.0 || prim.sigmaY > 0.0) {
                c.saveLayer(
                  region,
                  ui.Paint()
                    ..imageFilter = ui.ImageFilter.blur(
                      sigmaX: prim.sigmaX,
                      sigmaY: prim.sigmaY,
                      tileMode: prim.tileMode,
                    ),
                );
                c.drawPicture(inp);
                c.restore();
              } else {
                c.drawPicture(inp);
              }
            });
          }(),
          SvgFeOffset() => recordPicture((c) {
            final inp = resolveInput(prim.inSource);
            c.save();
            c.translate(prim.dx, prim.dy);
            c.drawPicture(inp);
            c.restore();
          }),
          SvgFeColorMatrix() => recordPicture((c) {
            final inp = resolveInput(prim.inSource);
            final cf = buildColorMatrixFilter(prim);
            if (cf != null) {
              c.saveLayer(region, ui.Paint()..colorFilter = cf);
              c.drawPicture(inp);
              c.restore();
            } else {
              c.drawPicture(inp);
            }
          }),
          SvgFeFlood() => recordPicture((c) {
            final col = prim.floodColor.withValues(
              alpha: (prim.floodColor.a * prim.floodOpacity).clamp(0.0, 1.0),
            );
            c.drawRect(region, ui.Paint()..color = col);
          }),
          SvgFeDropShadow() => recordPicture((c) {
            final inp = resolveInput(prim.inSource);
            _drawDropShadowPass(c, region, prim, (sc) => sc.drawPicture(inp));
            c.drawPicture(inp);
          }),
          SvgFeBlend() => recordPicture((c) {
            final in1 = resolveInput(prim.inSource);
            final in2 = resolveInput(prim.in2);
            // Isolate blend inside its own layer so blendMode never leaks onto
            // previously painted sibling elements on the main canvas.
            c.saveLayer(region, ui.Paint());
            c.drawPicture(in2);
            c.saveLayer(region, ui.Paint()..blendMode = prim.mode);
            c.drawPicture(in1);
            c.restore();
            c.restore();
          }),
          SvgFeComposite() => recordPicture((c) {
            final in1 = resolveInput(prim.inSource);
            final in2 = resolveInput(prim.in2);
            // Isolate composite inside its own layer so Porter-Duff operators
            // (e.g. srcIn) only clip against in2, never against main canvas siblings.
            c.saveLayer(region, ui.Paint());
            c.drawPicture(in2);
            c.saveLayer(region, ui.Paint()..blendMode = prim.operatorMode);
            c.drawPicture(in1);
            c.restore();
            c.restore();
          }),
          SvgFeMerge() => recordPicture((c) {
            for (final nodeIn in prim.inputs) {
              c.drawPicture(resolveInput(nodeIn));
            }
          }),
          SvgFeMorphology() => recordPicture((c) {
            final inp = resolveInput(prim.inSource);
            if (prim.radiusX > 0.0 || prim.radiusY > 0.0) {
              final filterImg = prim.isDilate
                  ? ui.ImageFilter.dilate(
                      radiusX: prim.radiusX,
                      radiusY: prim.radiusY,
                    )
                  : ui.ImageFilter.erode(
                      radiusX: prim.radiusX,
                      radiusY: prim.radiusY,
                    );
              c.saveLayer(region, ui.Paint()..imageFilter = filterImg);
              c.drawPicture(inp);
              c.restore();
            } else {
              c.drawPicture(inp);
            }
          }),
          SvgFeComponentTransfer() => recordPicture((c) {
            final inp = resolveInput(prim.inSource);
            final cf = buildComponentTransferFilter(prim);
            c.saveLayer(region, ui.Paint()..colorFilter = cf);
            c.drawPicture(inp);
            c.restore();
          }),
          SvgFeTurbulence() => () {
            outField = prim.resolveField(region);
            return prim.resolvePicture(region);
          }(),
          SvgFeDisplacementMap() => recordPicture((c) {
            final in1 = resolveInput(prim.inSource);
            final mapField = resolveField(prim.in2);
            if (mapField == null ||
                prim.scale.abs() < 1e-4 ||
                region.width <= 0.0 ||
                region.height <= 0.0) {
              c.drawPicture(in1);
              return;
            }
            // Rasterize in1 synchronously into an offscreen ui.Image capped at 512px
            final maxDim = math.max(region.width, region.height);
            final downscale = maxDim > 512.0 ? 512.0 / maxDim : 1.0;
            final pxW = (region.width * downscale).ceil().clamp(1, 512);
            final pxH = (region.height * downscale).ceil().clamp(1, 512);
            final imgRec = ui.PictureRecorder();
            final imgCanvas = ui.Canvas(
              imgRec,
              ui.Rect.fromLTWH(0.0, 0.0, pxW.toDouble(), pxH.toDouble()),
            );
            imgCanvas.scale(pxW / region.width, pxH / region.height);
            imgCanvas.translate(-region.left, -region.top);
            imgCanvas.drawPicture(in1);
            final imgPic = imgRec.endRecording();
            final srcImg = imgPic.toImageSync(pxW, pxH);
            imgPic.dispose();
            try {
              SvgFilterNoiseEngine.paintDisplacedMesh(
                canvas: c,
                sourceImage: srcImg,
                region: region,
                mapField: mapField,
                scale: prim.scale,
                xChannel: prim.xChannel,
                yChannel: prim.yChannel,
              );
            } finally {
              srcImg.dispose();
            }
          }),
        };

        lastResult = out;
        lastField = outField;
        if (prim.result != null && prim.result!.isNotEmpty) {
          buffers[prim.result!] = out;
          if (outField != null) {
            fieldBuffers[prim.result!] = outField!;
          }
        }
      }

      canvas.drawPicture(lastResult);
    } finally {
      for (final pic in ownedPictures) {
        pic.dispose();
      }
    }
  }

  static bool _tryPaintSingleFastPath(
    ui.Canvas canvas,
    SvgFilterPrimitive prim,
    ui.Rect region,
    void Function(ui.Canvas) paintSource,
  ) {
    switch (prim) {
      case SvgFeGaussianBlur():
        if (prim.sigmaX <= 0.0 && prim.sigmaY <= 0.0) {
          paintSource(canvas);
          return true;
        }
        canvas.saveLayer(
          region,
          ui.Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: prim.sigmaX,
              sigmaY: prim.sigmaY,
              tileMode: prim.tileMode,
            ),
        );
        paintSource(canvas);
        canvas.restore();
        return true;

      case SvgFeOffset():
        canvas.save();
        canvas.translate(prim.dx, prim.dy);
        paintSource(canvas);
        canvas.restore();
        return true;

      case SvgFeColorMatrix():
        final cf = buildColorMatrixFilter(prim);
        if (cf == null) {
          paintSource(canvas);
          return true;
        }
        canvas.saveLayer(region, ui.Paint()..colorFilter = cf);
        paintSource(canvas);
        canvas.restore();
        return true;

      case SvgFeDropShadow():
        _drawDropShadowPass(canvas, region, prim, paintSource);
        paintSource(canvas);
        return true;

      case SvgFeMorphology():
        if (prim.radiusX <= 0.0 && prim.radiusY <= 0.0) {
          paintSource(canvas);
          return true;
        }
        final filterImg = prim.isDilate
            ? ui.ImageFilter.dilate(
                radiusX: prim.radiusX,
                radiusY: prim.radiusY,
              )
            : ui.ImageFilter.erode(
                radiusX: prim.radiusX,
                radiusY: prim.radiusY,
              );
        canvas.saveLayer(region, ui.Paint()..imageFilter = filterImg);
        paintSource(canvas);
        canvas.restore();
        return true;

      case SvgFeComponentTransfer():
        final cf = buildComponentTransferFilter(prim);
        canvas.saveLayer(region, ui.Paint()..colorFilter = cf);
        paintSource(canvas);
        canvas.restore();
        return true;

      case SvgFeTurbulence():
        canvas.drawPicture(prim.resolvePicture(region));
        return true;

      default:
        return false;
    }
  }

  static void _drawDropShadowPass(
    ui.Canvas canvas,
    ui.Rect region,
    SvgFeDropShadow prim,
    void Function(ui.Canvas) paintSource,
  ) {
    final shadowColor = prim.floodColor.withValues(
      alpha: (prim.floodColor.a * prim.floodOpacity).clamp(0.0, 1.0),
    );
    final shadowPaint = ui.Paint()
      ..colorFilter = ui.ColorFilter.mode(shadowColor, ui.BlendMode.srcIn);
    if (prim.sigmaX > 0.0 || prim.sigmaY > 0.0) {
      shadowPaint.imageFilter = ui.ImageFilter.blur(
        sigmaX: prim.sigmaX,
        sigmaY: prim.sigmaY,
        tileMode: ui.TileMode.decal,
      );
    }
    canvas.saveLayer(region, shadowPaint);
    canvas.translate(prim.dx, prim.dy);
    paintSource(canvas);
    canvas.restore();
  }

  /// Builds a Flutter [ui.ColorFilter] for `<feColorMatrix>`.
  static ui.ColorFilter? buildColorMatrixFilter(SvgFeColorMatrix prim) {
    switch (prim.type) {
      case SvgFeColorMatrixType.luminanceToAlpha:
        return const ui.ColorFilter.matrix(<double>[
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.2126,
          0.7152,
          0.0722,
          0.0,
          0.0,
        ]);

      case SvgFeColorMatrixType.saturate:
        final s = prim.values.isNotEmpty ? prim.values[0] : 1.0;
        return ui.ColorFilter.matrix(<double>[
          0.213 + 0.787 * s,
          0.715 - 0.715 * s,
          0.072 - 0.072 * s,
          0.0,
          0.0,
          0.213 - 0.213 * s,
          0.715 + 0.285 * s,
          0.072 - 0.072 * s,
          0.0,
          0.0,
          0.213 - 0.213 * s,
          0.715 - 0.715 * s,
          0.072 + 0.928 * s,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          1.0,
          0.0,
        ]);

      case SvgFeColorMatrixType.hueRotate:
        final deg = prim.values.isNotEmpty ? prim.values[0] : 0.0;
        final rad = deg * SvgMatrixMath.degToRad;
        final cosA = math.cos(rad);
        final sinA = math.sin(rad);
        return ui.ColorFilter.matrix(<double>[
          0.213 + cosA * 0.787 - sinA * 0.213,
          0.715 - cosA * 0.715 - sinA * 0.715,
          0.072 - cosA * 0.072 + sinA * 0.928,
          0.0,
          0.0,
          0.213 - cosA * 0.213 + sinA * 0.143,
          0.715 + cosA * 0.285 + sinA * 0.140,
          0.072 - cosA * 0.072 - sinA * 0.283,
          0.0,
          0.0,
          0.213 - cosA * 0.213 - sinA * 0.787,
          0.715 - cosA * 0.715 + sinA * 0.715,
          0.072 + cosA * 0.928 + sinA * 0.072,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          1.0,
          0.0,
        ]);

      case SvgFeColorMatrixType.matrix:
        if (prim.values.length < 20) return null;
        // SVG 5th column offsets are [0..1]; Flutter ColorFilter.matrix uses [0..255]
        final m = List<double>.filled(20, 0.0);
        for (int i = 0; i < 20; i++) {
          m[i] = (i % 5 == 4) ? prim.values[i] * 255.0 : prim.values[i];
        }
        return ui.ColorFilter.matrix(m);
    }
  }

  /// Builds a Flutter [ui.ColorFilter] for `<feComponentTransfer>`.
  static ui.ColorFilter buildComponentTransferFilter(
    SvgFeComponentTransfer prim,
  ) {
    final (sr, br) = prim.funcR?.toAffineRow() ?? (1.0, 0.0);
    final (sg, bg) = prim.funcG?.toAffineRow() ?? (1.0, 0.0);
    final (sb, bb) = prim.funcB?.toAffineRow() ?? (1.0, 0.0);
    final (sa, ba) = prim.funcA?.toAffineRow() ?? (1.0, 0.0);
    return ui.ColorFilter.matrix(<double>[
      sr,
      0.0,
      0.0,
      0.0,
      br,
      0.0,
      sg,
      0.0,
      0.0,
      bg,
      0.0,
      0.0,
      sb,
      0.0,
      bb,
      0.0,
      0.0,
      0.0,
      sa,
      ba,
    ]);
  }
}
