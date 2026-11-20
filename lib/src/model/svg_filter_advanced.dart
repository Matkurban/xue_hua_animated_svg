part of 'svg_filter_node.dart';

/// Precompiled `<feImage href="..." preserveAspectRatio="..." />` primitive.
///
/// 预编译的 `<feImage>` 图像/元素引用滤镜图元。
final class SvgFeImage extends SvgFilterPrimitive {
  /// Optional fragment (`#id`) or image URI reference (`href` / `xlink:href`).
  ///
  /// 可选的元素片段引用（`#id`）或图像 URI（`href` / `xlink:href`）。
  final String? href;

  /// Aspect ratio alignment and scaling mode (`preserveAspectRatio`).
  ///
  /// 宽高比对齐与缩放模式（`preserveAspectRatio`）。
  final SvgPreserveAspectRatio preserveAspectRatio;

  /// Creates an [SvgFeImage] with optional [href] and [preserveAspectRatio].
  ///
  /// 创建 [SvgFeImage]，配置可选的引用 [href] 与宽高比规则 [preserveAspectRatio]。
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

/// Precompiled `<feTile in="..." />` primitive that repeats its input across
/// the filter region.
///
/// 预编译的 `<feTile>` 纹理平铺滤镜图元，将输入内容平铺到整个滤镜区域。
final class SvgFeTile extends SvgFilterPrimitive {
  /// Creates an [SvgFeTile] with optional input source and subregion bounds.
  ///
  /// 创建 [SvgFeTile]，配置可选输入源与子区域边界。
  const SvgFeTile({
    super.inSource,
    super.result,
    super.x,
    super.y,
    super.width,
    super.height,
  });
}

/// Precompiled `<feConvolveMatrix order="..." kernelMatrix="..." divisor="..." bias="..." />` primitive.
///
/// 预编译的 `<feConvolveMatrix>` 二维卷积矩阵滤镜图元。
final class SvgFeConvolveMatrix extends SvgFilterPrimitive {
  /// Kernel column count (`order` X, defaults to `3`).
  ///
  /// 卷积核列数（`order` X，默认 `3`）。
  final int orderX;

  /// Kernel row count (`order` Y, defaults to `3`).
  ///
  /// 卷积核行数（`order` Y，默认 `3`）。
  final int orderY;

  /// Row-major convolution kernel weights (`kernelMatrix`, length `orderX * orderY`).
  ///
  /// 行优先存储的卷积核权重矩阵（`kernelMatrix`，长度为 `orderX * orderY`）。
  final Float64List kernelMatrix;

  /// Optional explicit normalization divisor (`divisor`); defaults to kernel sum.
  ///
  /// 可选显式归一化除数（`divisor`）；缺省时取卷积核元素之和。
  final double? divisor;

  /// Constant offset added after convolution (`bias`, defaults to `0.0`).
  ///
  /// 卷积完成后叠加的常量偏置（`bias`，默认 `0.0`）。
  final double bias;

  /// Optional kernel anchor column index (`targetX`).
  ///
  /// 可选卷积核锚点列索引（`targetX`）。
  final int? targetX;

  /// Optional kernel anchor row index (`targetY`).
  ///
  /// 可选卷积核锚点行索引（`targetY`）。
  final int? targetY;

  /// Edge handling strategy mapped from `edgeMode`.
  ///
  /// 由 `edgeMode` 映射的边缘处理策略。
  final ui.TileMode edgeMode;

  /// Whether the original alpha channel is preserved instead of convolved (`preserveAlpha`).
  ///
  /// 是否保留原始 Alpha 通道而不参与卷积计算（`preserveAlpha`）。
  final bool preserveAlpha;

  /// Creates an [SvgFeConvolveMatrix] with kernel dimensions ([orderX], [orderY]),
  /// [kernelMatrix], and optional [divisor], [bias], [targetX], [targetY],
  /// [edgeMode], and [preserveAlpha].
  ///
  /// 创建 [SvgFeConvolveMatrix]，配置卷积核尺寸（[orderX]、[orderY]）、权重 [kernelMatrix] 及可选参数（[divisor]、[bias]、[targetX]、[targetY]、[edgeMode]、[preserveAlpha]）。
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

  /// Effective non-zero divisor: explicit [divisor], sum of [kernelMatrix], or `1.0`.
  ///
  /// 实际生效的非零除数：优先使用显式 [divisor]，否则取 [kernelMatrix] 之和，若接近零则回退为 `1.0`。
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
///
/// W3C Filter Effects Level 1 光源节点的密封基类。
sealed class SvgLightSource {
  /// Creates an [SvgLightSource].
  ///
  /// 创建 [SvgLightSource]。
  const SvgLightSource();
}

/// Precompiled `<feDistantLight azimuth="..." elevation="..." />` directional light source.
///
/// 预编译的 `<feDistantLight>` 平行方向光源。
final class SvgFeDistantLight extends SvgLightSource {
  /// Light azimuth angle in degrees (`azimuth`).
  ///
  /// 光源方位角（单位：度，`azimuth`）。
  final double azimuthDeg;

  /// Light elevation angle in degrees (`elevation`).
  ///
  /// 光源仰角（单位：度，`elevation`）。
  final double elevationDeg;

  /// Creates an [SvgFeDistantLight] with [azimuthDeg] and [elevationDeg].
  ///
  /// 创建 [SvgFeDistantLight]，指定方位角 [azimuthDeg] 与仰角 [elevationDeg]。
  const SvgFeDistantLight({this.azimuthDeg = 0.0, this.elevationDeg = 0.0});
}

/// Precompiled `<fePointLight x="..." y="..." z="..." />` point light source.
///
/// 预编译的 `<fePointLight>` 点光源。
final class SvgFePointLight extends SvgLightSource {
  /// Point light X coordinate (`x`).
  ///
  /// 点光源 X 坐标（`x`）。
  final double x;

  /// Point light Y coordinate (`y`).
  ///
  /// 点光源 Y 坐标（`y`）。
  final double y;

  /// Point light Z coordinate (`z`).
  ///
  /// 点光源 Z 坐标（`z`）。
  final double z;

  /// Creates an [SvgFePointLight] at ([x], [y], [z]).
  ///
  /// 在三维坐标（[x]、[y]、[z]）处创建 [SvgFePointLight]。
  const SvgFePointLight({this.x = 0.0, this.y = 0.0, this.z = 0.0});
}

/// Precompiled `<feSpotLight x="..." y="..." z="..." pointsAtX="..." pointsAtY="..." pointsAtZ="..." />` spotlight source.
///
/// 预编译的 `<feSpotLight>` 聚光灯光源。
final class SvgFeSpotLight extends SvgLightSource {
  /// Spotlight origin X coordinate (`x`).
  ///
  /// 聚光灯起点 X 坐标（`x`）。
  final double x;

  /// Spotlight origin Y coordinate (`y`).
  ///
  /// 聚光灯起点 Y 坐标（`y`）。
  final double y;

  /// Spotlight origin Z coordinate (`z`).
  ///
  /// 聚光灯起点 Z 坐标（`z`）。
  final double z;

  /// Spotlight target X coordinate (`pointsAtX`).
  ///
  /// 聚光灯照射目标点 X 坐标（`pointsAtX`）。
  final double pointsAtX;

  /// Spotlight target Y coordinate (`pointsAtY`).
  ///
  /// 聚光灯照射目标点 Y 坐标（`pointsAtY`）。
  final double pointsAtY;

  /// Spotlight target Z coordinate (`pointsAtZ`).
  ///
  /// 聚光灯照射目标点 Z 坐标（`pointsAtZ`）。
  final double pointsAtZ;

  /// Spotlight beam focus exponent (`specularExponent`).
  ///
  /// 聚光灯光束聚焦指数（`specularExponent`）。
  final double specularExponent;

  /// Optional cone cutoff angle in degrees (`limitingConeAngle`).
  ///
  /// 可选光锥截止角度（单位：度，`limitingConeAngle`）。
  final double? limitingConeAngleDeg;

  /// Creates an [SvgFeSpotLight] positioned at ([x], [y], [z]) aimed toward
  /// ([pointsAtX], [pointsAtY], [pointsAtZ]) with [specularExponent] and
  /// optional [limitingConeAngleDeg].
  ///
  /// 创建位于（[x]、[y]、[z]）并指向（[pointsAtX]、[pointsAtY]、[pointsAtZ]）的 [SvgFeSpotLight]，配置聚焦指数 [specularExponent] 与可选光锥角 [limitingConeAngleDeg]。
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

/// Precompiled `<feDiffuseLighting surfaceScale="..." diffuseConstant="..." lighting-color="..." />` primitive.
///
/// 预编译的 `<feDiffuseLighting>` 漫反射光照滤镜图元。
final class SvgFeDiffuseLighting extends SvgFilterPrimitive {
  /// Height map scale multiplier (`surfaceScale`).
  ///
  /// 表面高度图缩放系数（`surfaceScale`）。
  final double surfaceScale;

  /// Phong diffuse reflection constant `kd` (`diffuseConstant`).
  ///
  /// Phong 漫反射系数 `kd`（`diffuseConstant`）。
  final double diffuseConstant;

  /// Light color (`lighting-color`).
  ///
  /// 光源颜色（`lighting-color`）。
  final ui.Color lightingColor;

  /// Child light source (`<feDistantLight>`, `<fePointLight>`, or `<feSpotLight>`).
  ///
  /// 子光源定义（`<feDistantLight>`、`<fePointLight>` 或 `<feSpotLight>`）。
  final SvgLightSource? lightSource;

  /// Creates an [SvgFeDiffuseLighting] with [surfaceScale], [diffuseConstant],
  /// [lightingColor], and [lightSource].
  ///
  /// 创建 [SvgFeDiffuseLighting]，配置高度缩放 [surfaceScale]、漫反射系数 [diffuseConstant]、光色 [lightingColor] 与光源 [lightSource]。
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

/// Precompiled `<feSpecularLighting surfaceScale="..." specularConstant="..." specularExponent="..." />` primitive.
///
/// 预编译的 `<feSpecularLighting>` 镜面高光光照滤镜图元。
final class SvgFeSpecularLighting extends SvgFilterPrimitive {
  /// Height map scale multiplier (`surfaceScale`).
  ///
  /// 表面高度图缩放系数（`surfaceScale`）。
  final double surfaceScale;

  /// Phong specular reflection constant `ks` (`specularConstant`).
  ///
  /// Phong 镜面反射系数 `ks`（`specularConstant`）。
  final double specularConstant;

  /// Specular highlight shininess exponent (`specularExponent`).
  ///
  /// 镜面高光锐度指数（`specularExponent`）。
  final double specularExponent;

  /// Light color (`lighting-color`).
  ///
  /// 光源颜色（`lighting-color`）。
  final ui.Color lightingColor;

  /// Child light source (`<feDistantLight>`, `<fePointLight>`, or `<feSpotLight>`).
  ///
  /// 子光源定义（`<feDistantLight>`、`<fePointLight>` 或 `<feSpotLight>`）。
  final SvgLightSource? lightSource;

  /// Creates an [SvgFeSpecularLighting] with [surfaceScale], [specularConstant],
  /// [specularExponent], [lightingColor], and [lightSource].
  ///
  /// 创建 [SvgFeSpecularLighting]，配置高度缩放 [surfaceScale]、镜面系数 [specularConstant]、高光指数 [specularExponent]、光色 [lightingColor] 与光源 [lightSource]。
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
///
/// 面向 `<feTile>`、算术 `<feComposite>`、`<feConvolveMatrix>`、`<feDiffuseLighting>`
/// 与 `<feSpecularLighting>` 的纯 Dart 同步 GPU/像素处理引擎。
abstract final class SvgFilterAdvancedEngine {
  /// Tiles [inputPicture] cropped to [tileBounds] across [targetRegion] on
  /// [canvas] using `ui.ImageShader`.
  ///
  /// 使用 `ui.ImageShader` 将裁剪自 [tileBounds] 的 [inputPicture] 平铺绘制到
  /// [canvas] 的 [targetRegion] 区域内。
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
        sx,
        0,
        0,
        0,
        0,
        sy,
        0,
        0,
        0,
        0,
        1,
        0,
        tileBounds.left,
        tileBounds.top,
        0,
        1,
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

  /// Evaluates `<feComposite operator="arithmetic">` on [f1] and [f2] using
  /// coefficients [k1], [k2], [k3], and [k4]:
  /// `result = k1 * i1 * i2 + k2 * i1 + k3 * i2 + k4`.
  ///
  /// 对像素场 [f1] 与 [f2] 执行算术合成 `k1 * i1 * i2 + k2 * i1 + k3 * i2 + k4`，
  /// 系数为 [k1]、[k2]、[k3]、[k4]。
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

  /// Applies the 2D `<feConvolveMatrix>` kernel defined by [prim] to [src].
  ///
  /// 将 [prim] 定义的二维 `<feConvolveMatrix>` 卷积核应用于源像素场 [src]。
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

  /// Generates a lit RGBA pixel field within [region] for `<feDiffuseLighting>`
  /// (`isSpecular == false`) or `<feSpecularLighting>` (`isSpecular == true`),
  /// sampling surface normals from [heightField] (or a smooth fallback dome)
  /// scaled by [surfaceScale] with reflection [constant], [specularExponent],
  /// [lightingColor], and [lightSource].
  ///
  /// 在 [region] 内生成 `<feDiffuseLighting>`（[isSpecular] 为 `false`）或
  /// `<feSpecularLighting>`（[isSpecular] 为 `true`）的光照 RGBA 像素场；使用
  /// [heightField]（或平滑半球默认高度图）按 [surfaceScale] 计算法线，并结合反射系数
  /// [constant]、高光指数 [specularExponent]、光色 [lightingColor] 与光源 [lightSource] 求解光照。
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
        final dzdx =
            (sampleHeight(gx + 1, gy) - sampleHeight(gx - 1, gy)) * 0.5;
        final dzdy =
            (sampleHeight(gx, gy + 1) - sampleHeight(gx, gy - 1)) * 0.5;

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
              (constant *
                      math.pow(ndoth, specularExponent.clamp(1.0, 128.0)) *
                      atten)
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

    return SvgFilterPixelField(width: w, height: h, region: region, rgba: out);
  }
}
