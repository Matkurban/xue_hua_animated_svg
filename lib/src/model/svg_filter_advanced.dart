part of 'svg_filter_node.dart';

/// `<feImage href="..." preserveAspectRatio="..." />`
final class SvgFeImage extends SvgFilterPrimitive {
  final String? href;
  final SvgPreserveAspectRatio preserveAspectRatio;

  const SvgFeImage({
    super.inSource,
    super.result,
    super.x,
    super.y,
    super.width,
    super.height,
    this.href,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
  });
}

/// `<feTile in="..." />`
final class SvgFeTile extends SvgFilterPrimitive {
  const SvgFeTile({
    super.inSource,
    super.result,
    super.x,
    super.y,
    super.width,
    super.height,
  });
}

/// `<feConvolveMatrix order="..." kernelMatrix="..." divisor="..." bias="..." />`
final class SvgFeConvolveMatrix extends SvgFilterPrimitive {
  final int orderX;
  final int orderY;
  final Float64List kernelMatrix;
  final double? divisor;
  final double bias;
  final int? targetX;
  final int? targetY;
  final ui.TileMode edgeMode;
  final bool preserveAlpha;

  const SvgFeConvolveMatrix({
    super.inSource,
    super.result,
    super.x,
    super.y,
    super.width,
    super.height,
    this.orderX = 3,
    this.orderY = 3,
    required this.kernelMatrix,
    this.divisor,
    this.bias = 0.0,
    this.targetX,
    this.targetY,
    this.edgeMode = ui.TileMode.clamp,
    this.preserveAlpha = false,
  });

  double get effectiveDivisor {
    if (divisor != null && divisor!.abs() > 1e-9) return divisor!;
    double sum = 0.0;
    for (int i = 0; i < kernelMatrix.length; i++) {
      sum += kernelMatrix[i];
    }
    return sum.abs() > 1e-9 ? sum : 1.0;
  }
}

/// Base sealed class for W3C Filter Effects Level 1 light sources.
sealed class SvgLightSource {
  const SvgLightSource();
}

/// `<feDistantLight azimuth="..." elevation="..." />`
final class SvgFeDistantLight extends SvgLightSource {
  final double azimuthDeg;
  final double elevationDeg;

  const SvgFeDistantLight({this.azimuthDeg = 0.0, this.elevationDeg = 0.0});
}

/// `<fePointLight x="..." y="..." z="..." />`
final class SvgFePointLight extends SvgLightSource {
  final double x;
  final double y;
  final double z;

  const SvgFePointLight({this.x = 0.0, this.y = 0.0, this.z = 0.0});
}

/// `<feSpotLight x="..." y="..." z="..." pointsAtX="..." pointsAtY="..." pointsAtZ="..." />`
final class SvgFeSpotLight extends SvgLightSource {
  final double x;
  final double y;
  final double z;
  final double pointsAtX;
  final double pointsAtY;
  final double pointsAtZ;
  final double specularExponent;
  final double? limitingConeAngleDeg;

  const SvgFeSpotLight({
    this.x = 0.0,
    this.y = 0.0,
    this.z = 0.0,
    this.pointsAtX = 0.0,
    this.pointsAtY = 0.0,
    this.pointsAtZ = 0.0,
    this.specularExponent = 1.0,
    this.limitingConeAngleDeg,
  });
}

/// `<feDiffuseLighting surfaceScale="..." diffuseConstant="..." lighting-color="..." />`
final class SvgFeDiffuseLighting extends SvgFilterPrimitive {
  final double surfaceScale;
  final double diffuseConstant;
  final ui.Color lightingColor;
  final SvgLightSource? lightSource;

  const SvgFeDiffuseLighting({
    super.inSource,
    super.result,
    super.x,
    super.y,
    super.width,
    super.height,
    this.surfaceScale = 1.0,
    this.diffuseConstant = 1.0,
    this.lightingColor = const ui.Color(0xFFFFFFFF),
    this.lightSource,
  });
}

/// `<feSpecularLighting surfaceScale="..." specularConstant="..." specularExponent="..." />`
final class SvgFeSpecularLighting extends SvgFilterPrimitive {
  final double surfaceScale;
  final double specularConstant;
  final double specularExponent;
  final ui.Color lightingColor;
  final SvgLightSource? lightSource;

  const SvgFeSpecularLighting({
    super.inSource,
    super.result,
    super.x,
    super.y,
    super.width,
    super.height,
    this.surfaceScale = 1.0,
    this.specularConstant = 1.0,
    this.specularExponent = 1.0,
    this.lightingColor = const ui.Color(0xFFFFFFFF),
    this.lightSource,
  });
}

/// Pure-Dart synchronous GPU/pixel processors for `<feTile>`,
/// `<feComposite operator="arithmetic">`, `<feConvolveMatrix>`,
/// `<feDiffuseLighting>`, and `<feSpecularLighting>`.
abstract final class SvgFilterAdvancedEngine {
  /// Tiles [inputPicture] across [targetRegion] using `ui.ImageShader`.
  static void paintTile({
    required ui.Canvas canvas,
    required ui.Picture inputPicture,
    required ui.Rect tileBounds,
    required ui.Rect targetRegion,
  }) {
    if (tileBounds.width <= 1e-3 ||
        tileBounds.height <= 1e-3 ||
        targetRegion.isEmpty) {
      return;
    }
    final maxDim = math.max(tileBounds.width, tileBounds.height);
    final downscale = maxDim > 256.0 ? 256.0 / maxDim : 1.0;
    final pxW = (tileBounds.width * downscale).ceil().clamp(1, 256);
    final pxH = (tileBounds.height * downscale).ceil().clamp(1, 256);

    final rec = ui.PictureRecorder();
    final c = ui.Canvas(
      rec,
      ui.Rect.fromLTWH(0.0, 0.0, pxW.toDouble(), pxH.toDouble()),
    );
    c.scale(pxW / tileBounds.width, pxH / tileBounds.height);
    c.translate(-tileBounds.left, -tileBounds.top);
    c.drawPicture(inputPicture);
    final pic = rec.endRecording();
    final tileImg = pic.toImageSync(pxW, pxH);
    pic.dispose();

    try {
      final sx = tileBounds.width / pxW;
      final sy = tileBounds.height / pxH;
      final matrix = Float64List.fromList(<double>[
        sx, 0, 0, 0,
        0, sy, 0, 0,
        0, 0, 1, 0,
        tileBounds.left, tileBounds.top, 0, 1,
      ]);
      final paint = ui.Paint()
        ..shader = ui.ImageShader(
          tileImg,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          matrix,
        );
      canvas.drawRect(targetRegion, paint);
    } finally {
      tileImg.dispose();
    }
  }

  /// Evaluates `<feComposite operator="arithmetic">` on two [SvgFilterPixelField]s:
  /// `result = k1 * i1 * i2 + k2 * i1 + k3 * i2 + k4`.
  static SvgFilterPixelField computeArithmeticField({
    required SvgFilterPixelField f1,
    required SvgFilterPixelField f2,
    required double k1,
    required double k2,
    required double k3,
    required double k4,
  }) {
    final w = f1.width;
    final h = f1.height;
    final out = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      final y2 = (y * f2.height ~/ h).clamp(0, f2.height - 1);
      for (int x = 0; x < w; x++) {
        final x2 = (x * f2.width ~/ w).clamp(0, f2.width - 1);
        final idx1 = (y * w + x) * 4;
        final idx2 = (y2 * f2.width + x2) * 4;
        for (int ch = 0; ch < 4; ch++) {
          final i1 = f1.rgba[idx1 + ch] / 255.0;
          final i2 = f2.rgba[idx2 + ch] / 255.0;
          final res = k1 * i1 * i2 + k2 * i1 + k3 * i2 + k4;
          out[idx1 + ch] = (res.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
        }
      }
    }
    return SvgFilterPixelField(
      width: w,
      height: h,
      region: f1.region,
      rgba: out,
    );
  }

  /// Applies a 2D `<feConvolveMatrix>` kernel to [src].
  static SvgFilterPixelField convolveField(
    SvgFilterPixelField src,
    SvgFeConvolveMatrix prim,
  ) {
    final ox = prim.orderX.clamp(1, 9);
    final oy = prim.orderY.clamp(1, 9);
    if (prim.kernelMatrix.length < ox * oy) return src;

    final tx = (prim.targetX ?? (ox ~/ 2)).clamp(0, ox - 1);
    final ty = (prim.targetY ?? (oy ~/ 2)).clamp(0, oy - 1);
    final div = prim.effectiveDivisor;
    final bias255 = prim.bias * 255.0;
    final w = src.width;
    final h = src.height;
    final out = Uint8List(w * h * 4);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double sr = 0, sg = 0, sb = 0, sa = 0;
        for (int ky = 0; ky < oy; ky++) {
          for (int kx = 0; kx < ox; kx++) {
            final kVal = prim.kernelMatrix[ky * ox + kx];
            int sx = x + kx - tx;
            int sy = y + ky - ty;
            if (prim.edgeMode == ui.TileMode.repeated) {
              sx = ((sx % w) + w) % w;
              sy = ((sy % h) + h) % h;
            } else if (prim.edgeMode == ui.TileMode.clamp) {
              sx = sx.clamp(0, w - 1);
              sy = sy.clamp(0, h - 1);
            } else if (sx < 0 || sx >= w || sy < 0 || sy >= h) {
              continue;
            }
            final idx = (sy * w + sx) * 4;
            sr += src.rgba[idx] * kVal;
            sg += src.rgba[idx + 1] * kVal;
            sb += src.rgba[idx + 2] * kVal;
            sa += src.rgba[idx + 3] * kVal;
          }
        }
        final dst = (y * w + x) * 4;
        out[dst] = (sr / div + bias255).round().clamp(0, 255);
        out[dst + 1] = (sg / div + bias255).round().clamp(0, 255);
        out[dst + 2] = (sb / div + bias255).round().clamp(0, 255);
        out[dst + 3] = prim.preserveAlpha
            ? src.rgba[dst + 3]
            : (sa / div + bias255).round().clamp(0, 255);
      }
    }
    return SvgFilterPixelField(
      width: w,
      height: h,
      region: src.region,
      rgba: out,
    );
  }

  /// Generates a lit RGBA field for `<feDiffuseLighting>` or `<feSpecularLighting>`
  /// using either [heightField]'s alpha channel or a smooth dome height map.
  static SvgFilterPixelField computeLightingField({
    required ui.Rect region,
    SvgFilterPixelField? heightField,
    required bool isSpecular,
    required double surfaceScale,
    required double constant,
    required double specularExponent,
    required ui.Color lightingColor,
    required SvgLightSource? lightSource,
  }) {
    final w = heightField?.width ?? 48;
    final h = heightField?.height ?? 48;
    final out = Uint8List(w * h * 4);
    final lr = lightingColor.r;
    final lg = lightingColor.g;
    final lb = lightingColor.b;
    final stepX = w > 1 ? region.width / (w - 1) : 1.0;
    final stepY = h > 1 ? region.height / (h - 1) : 1.0;

    double sampleHeight(int gx, int gy) {
      if (heightField != null) {
        return heightField.sampleChannel(gx, gy, SvgChannelSelector.a) *
            surfaceScale;
      }
      // Smooth normalized height dome when lighting is applied to a plain shape
      final nx = (gx / math.max(1, w - 1)) * 2.0 - 1.0;
      final ny = (gy / math.max(1, h - 1)) * 2.0 - 1.0;
      final d2 = math.max(0.0, 1.0 - (nx * nx + ny * ny) * 0.5);
      return d2 * surfaceScale;
    }

    for (int gy = 0; gy < h; gy++) {
      final py = region.top + gy * stepY;
      for (int gx = 0; gx < w; gx++) {
        final px = region.left + gx * stepX;
        final surfaceZ = sampleHeight(gx, gy);
        final dzdx = (sampleHeight(gx + 1, gy) - sampleHeight(gx - 1, gy)) * 0.5;
        final dzdy = (sampleHeight(gx, gy + 1) - sampleHeight(gx, gy - 1)) * 0.5;

        double nx = -dzdx;
        double ny = -dzdy;
        double nz = 1.0;
        final nLen = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (nLen > 1e-6) {
          nx /= nLen;
          ny /= nLen;
          nz /= nLen;
        }

        // Light vector L and spot attenuation
        double lx = 0.0, ly = 0.0, lz = 1.0;
        double atten = 1.0;
        switch (lightSource) {
          case SvgFeDistantLight(:final azimuthDeg, :final elevationDeg):
            final az = azimuthDeg * (math.pi / 180.0);
            final el = elevationDeg * (math.pi / 180.0);
            lx = math.cos(az) * math.cos(el);
            ly = math.sin(az) * math.cos(el);
            lz = math.sin(el);
          case SvgFePointLight(:final x, :final y, :final z):
            lx = x - px;
            ly = y - py;
            lz = z - surfaceZ;
            final lLen = math.sqrt(lx * lx + ly * ly + lz * lz);
            if (lLen > 1e-6) {
              lx /= lLen;
              ly /= lLen;
              lz /= lLen;
            }
          case SvgFeSpotLight(
            :final x,
            :final y,
            :final z,
            :final pointsAtX,
            :final pointsAtY,
            :final pointsAtZ,
            specularExponent: final spotExp,
            :final limitingConeAngleDeg,
          ):
            lx = x - px;
            ly = y - py;
            lz = z - surfaceZ;
            final lLen = math.sqrt(lx * lx + ly * ly + lz * lz);
            if (lLen > 1e-6) {
              lx /= lLen;
              ly /= lLen;
              lz /= lLen;
            }
            var sx = pointsAtX - x;
            var sy = pointsAtY - y;
            var sz = pointsAtZ - z;
            final sLen = math.sqrt(sx * sx + sy * sy + sz * sz);
            if (sLen > 1e-6) {
              sx /= sLen;
              sy /= sLen;
              sz /= sLen;
            }
            final cosAngle = -(lx * sx + ly * sy + lz * sz);
            if (cosAngle <= 0.0) {
              atten = 0.0;
            } else if (limitingConeAngleDeg != null &&
                cosAngle < math.cos(limitingConeAngleDeg * (math.pi / 180.0))) {
              atten = 0.0;
            } else {
              atten = math.pow(cosAngle, spotExp).toDouble();
            }
          case null:
            break;
        }

        final double intensity;
        if (isSpecular) {
          // Halfway vector H = normalize(L + E) where E = (0, 0, 1)
          var hx = lx;
          var hy = ly;
          var hz = lz + 1.0;
          final hLen = math.sqrt(hx * hx + hy * hy + hz * hz);
          if (hLen > 1e-6) {
            hx /= hLen;
            hy /= hLen;
            hz /= hLen;
          }
          final ndoth = math.max(0.0, nx * hx + ny * hy + nz * hz);
          intensity =
              (constant * math.pow(ndoth, specularExponent.clamp(1.0, 128.0)) * atten)
                  .clamp(0.0, 1.0);
        } else {
          final ndotl = math.max(0.0, nx * lx + ny * ly + nz * lz);
          intensity = (constant * ndotl * atten).clamp(0.0, 1.0);
        }

        final dst = (gy * w + gx) * 4;
        final r = (intensity * lr).clamp(0.0, 1.0);
        final g = (intensity * lg).clamp(0.0, 1.0);
        final b = (intensity * lb).clamp(0.0, 1.0);
        final a = isSpecular ? math.max(r, math.max(g, b)) : 1.0;
        out[dst] = (r * 255.0).round().clamp(0, 255);
        out[dst + 1] = (g * 255.0).round().clamp(0, 255);
        out[dst + 2] = (b * 255.0).round().clamp(0, 255);
        out[dst + 3] = (a * 255.0).round().clamp(0, 255);
      }
    }

    return SvgFilterPixelField(
      width: w,
      height: h,
      region: region,
      rgba: out,
    );
  }
}
