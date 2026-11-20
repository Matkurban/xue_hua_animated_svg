import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Channel selector for `<feDisplacementMap>`.
enum SvgChannelSelector { r, g, b, a }

/// Rasterized RGBA field in Dart memory for synchronous `<feTurbulence>` and
/// `<feDisplacementMap>` GPU mesh rendering.
class SvgFilterPixelField {
  final int width;
  final int height;
  final ui.Rect region;
  final Uint8List rgba;

  const SvgFilterPixelField({
    required this.width,
    required this.height,
    required this.region,
    required this.rgba,
  });

  /// Samples normalized channel value `[0.0 .. 1.0]` at grid cell `(gx, gy)`.
  double sampleChannel(int gx, int gy, SvgChannelSelector channel) {
    final cx = gx.clamp(0, width - 1);
    final cy = gy.clamp(0, height - 1);
    final offset = (cy * width + cx) * 4 + channel.index;
    return rgba[offset] / 255.0;
  }

  /// Returns a separable box-blurred copy of this field (used when
  /// `<feGaussianBlur>` sits between `<feTurbulence>` and `<feDisplacementMap>`).
  SvgFilterPixelField blurred(double sigmaX, double sigmaY) {
    if (sigmaX <= 0.1 && sigmaY <= 0.1) return this;
    final scaleX = region.width > 0 ? width / region.width : 1.0;
    final scaleY = region.height > 0 ? height / region.height : 1.0;
    final rx = (sigmaX * scaleX * 1.5).round().clamp(0, 12);
    final ry = (sigmaY * scaleY * 1.5).round().clamp(0, 12);
    if (rx == 0 && ry == 0) return this;

    final tmp = Uint8List(rgba.length);
    final out = Uint8List(rgba.length);

    // Horizontal pass
    if (rx > 0) {
      final diam = rx * 2 + 1;
      for (int y = 0; y < height; y++) {
        final rowBase = y * width * 4;
        for (int x = 0; x < width; x++) {
          int sr = 0, sg = 0, sb = 0, sa = 0;
          for (int k = -rx; k <= rx; k++) {
            final sx = (x + k).clamp(0, width - 1);
            final idx = rowBase + sx * 4;
            sr += rgba[idx];
            sg += rgba[idx + 1];
            sb += rgba[idx + 2];
            sa += rgba[idx + 3];
          }
          final dst = rowBase + x * 4;
          tmp[dst] = sr ~/ diam;
          tmp[dst + 1] = sg ~/ diam;
          tmp[dst + 2] = sb ~/ diam;
          tmp[dst + 3] = sa ~/ diam;
        }
      }
    } else {
      tmp.setAll(0, rgba);
    }

    // Vertical pass
    if (ry > 0) {
      final diam = ry * 2 + 1;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          int sr = 0, sg = 0, sb = 0, sa = 0;
          for (int k = -ry; k <= ry; k++) {
            final sy = (y + k).clamp(0, height - 1);
            final idx = (sy * width + x) * 4;
            sr += tmp[idx];
            sg += tmp[idx + 1];
            sb += tmp[idx + 2];
            sa += tmp[idx + 3];
          }
          final dst = (y * width + x) * 4;
          out[dst] = sr ~/ diam;
          out[dst + 1] = sg ~/ diam;
          out[dst + 2] = sb ~/ diam;
          out[dst + 3] = sa ~/ diam;
        }
      }
    } else {
      out.setAll(0, tmp);
    }

    return SvgFilterPixelField(
      width: width,
      height: height,
      region: region,
      rgba: out,
    );
  }
}

/// Pure-Dart W3C Filter Effects Level 1 §9.22 Perlin gradient noise generator
/// and synchronous GPU `ui.Vertices` builder for `<feTurbulence>` and
/// `<feDisplacementMap>`.
abstract final class SvgFilterNoiseEngine {
  static const int _bSize = 0x100;
  static const int _bm = 0xff;
  static const int _randM = 2147483647;
  static const int _randA = 16807;
  static const int _randQ = 127773;
  static const int _randR = 2836;

  /// Generates a deterministic W3C `<feTurbulence>` RGBA pixel field over [region].
  static SvgFilterPixelField generateTurbulenceField({
    required ui.Rect region,
    required bool isFractalNoise,
    required double baseFreqX,
    required double baseFreqY,
    required int numOctaves,
    required int seed,
    required bool stitchTiles,
  }) {
    final safeW = region.width.abs().clamp(1.0, 4096.0);
    final safeH = region.height.abs().clamp(1.0, 4096.0);
    final maxFreq = math.max(baseFreqX.abs(), baseFreqY.abs());
    // Adaptive grid resolution: higher for fine film grain, compact for smooth clouds
    final targetMax = maxFreq >= 0.15 ? 160 : 96;
    final aspect = safeW / safeH;
    final int gridW;
    final int gridH;
    if (aspect >= 1.0) {
      gridW = math.min(safeW.ceil(), targetMax).clamp(8, targetMax);
      gridH = (gridW / aspect).round().clamp(8, targetMax);
    } else {
      gridH = math.min(safeH.ceil(), targetMax).clamp(8, targetMax);
      gridW = (gridH * aspect).round().clamp(8, targetMax);
    }

    final lattice = _W3cTurbulenceLattice(seed);
    final octaves = numOctaves.clamp(1, 8);
    final rgba = Uint8List(gridW * gridH * 4);

    double fx = baseFreqX.abs();
    double fy = baseFreqY.abs();
    if (stitchTiles && safeW > 0 && safeH > 0) {
      if (fx > 0.0) {
        final lo = (safeW * fx).floor() / safeW;
        final hi = (safeW * fx).ceil() / safeW;
        fx = (lo > 0 && (fx / lo) < (hi / fx)) ? lo : (hi > 0 ? hi : fx);
      }
      if (fy > 0.0) {
        final lo = (safeH * fy).floor() / safeH;
        final hi = (safeH * fy).ceil() / safeH;
        fy = (lo > 0 && (fy / lo) < (hi / fy)) ? lo : (hi > 0 ? hi : fy);
      }
    }

    final stepX = gridW > 1 ? safeW / (gridW - 1) : 0.0;
    final stepY = gridH > 1 ? safeH / (gridH - 1) : 0.0;

    for (int gy = 0; gy < gridH; gy++) {
      final py = region.top + gy * stepY;
      for (int gx = 0; gx < gridW; gx++) {
        final px = region.left + gx * stepX;
        final dst = (gy * gridW + gx) * 4;
        for (int ch = 0; ch < 4; ch++) {
          double sum = 0.0;
          double curFx = fx;
          double curFy = fy;
          double ratio = 1.0;
          for (int oct = 0; oct < octaves; oct++) {
            final n = lattice.noise2(ch, px * curFx, py * curFy);
            sum += isFractalNoise ? (n / ratio) : (n.abs() / ratio);
            curFx *= 2.0;
            curFy *= 2.0;
            ratio *= 2.0;
          }
          final val = isFractalNoise ? (sum * 0.5 + 0.5) : sum;
          rgba[dst + ch] = (val.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
        }
      }
    }

    return SvgFilterPixelField(
      width: gridW,
      height: gridH,
      region: region,
      rgba: rgba,
    );
  }

  /// Paints a [SvgFilterPixelField] synchronously onto [canvas] as a smooth
  /// GPU-interpolated triangle mesh (`ui.Vertices`).
  static void paintFieldMesh(ui.Canvas canvas, SvgFilterPixelField field) {
    final w = field.width;
    final h = field.height;
    if (w < 2 || h < 2) return;

    final vertexCount = w * h;
    final positions = Float32List(vertexCount * 2);
    final colors = Int32List(vertexCount);
    final dx = field.region.width / (w - 1);
    final dy = field.region.height / (h - 1);

    for (int y = 0; y < h; y++) {
      final py = field.region.top + y * dy;
      for (int x = 0; x < w; x++) {
        final vIdx = y * w + x;
        positions[vIdx * 2] = field.region.left + x * dx;
        positions[vIdx * 2 + 1] = py;
        final cIdx = vIdx * 4;
        final r = field.rgba[cIdx];
        final g = field.rgba[cIdx + 1];
        final b = field.rgba[cIdx + 2];
        final a = field.rgba[cIdx + 3];
        colors[vIdx] = (a << 24) | (r << 16) | (g << 8) | b;
      }
    }

    final indices = _buildGridIndices(w, h);
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: indices,
    );
    canvas.drawVertices(vertices, ui.BlendMode.src, ui.Paint());
  }

  /// Paints [sourceImage] displaced by [mapField] synchronously on the GPU
  /// using displaced `textureCoordinates` in `ui.Vertices.raw`.
  static void paintDisplacedMesh({
    required ui.Canvas canvas,
    required ui.Image sourceImage,
    required ui.Rect region,
    required SvgFilterPixelField mapField,
    required double scale,
    required SvgChannelSelector xChannel,
    required SvgChannelSelector yChannel,
  }) {
    final w = mapField.width;
    final h = mapField.height;
    if (w < 2 || h < 2 || region.width <= 0 || region.height <= 0) return;

    final vertexCount = w * h;
    final positions = Float32List(vertexCount * 2);
    final texCoords = Float32List(vertexCount * 2);
    final dx = region.width / (w - 1);
    final dy = region.height / (h - 1);
    final imgScaleX = sourceImage.width / region.width;
    final imgScaleY = sourceImage.height / region.height;

    for (int y = 0; y < h; y++) {
      final localY = y * dy;
      final py = region.top + localY;
      for (int x = 0; x < w; x++) {
        final localX = x * dx;
        final px = region.left + localX;
        final vIdx = y * w + x;
        positions[vIdx * 2] = px;
        positions[vIdx * 2 + 1] = py;

        final xc = mapField.sampleChannel(x, y, xChannel);
        final yc = mapField.sampleChannel(x, y, yChannel);
        final srcX = (localX + scale * (xc - 0.5)) * imgScaleX;
        final srcY = (localY + scale * (yc - 0.5)) * imgScaleY;
        texCoords[vIdx * 2] = srcX.clamp(0.0, sourceImage.width.toDouble());
        texCoords[vIdx * 2 + 1] = srcY.clamp(
          0.0,
          sourceImage.height.toDouble(),
        );
      }
    }

    final indices = _buildGridIndices(w, h);
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      indices: indices,
    );
    final identity = Float64List.fromList(<double>[
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
    ]);
    final paint = ui.Paint()
      ..shader = ui.ImageShader(
        sourceImage,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        identity,
      )
      ..filterQuality = ui.FilterQuality.medium;
    canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);
  }

  static Uint16List _buildGridIndices(int w, int h) {
    final quadCount = (w - 1) * (h - 1);
    final indices = Uint16List(quadCount * 6);
    int p = 0;
    for (int y = 0; y < h - 1; y++) {
      for (int x = 0; x < w - 1; x++) {
        final tl = y * w + x;
        final tr = tl + 1;
        final bl = tl + w;
        final br = bl + 1;
        indices[p++] = tl;
        indices[p++] = tr;
        indices[p++] = bl;
        indices[p++] = tr;
        indices[p++] = br;
        indices[p++] = bl;
      }
    }
    return indices;
  }
}

/// W3C SVG 1.1 / Filter Effects Level 1 §9.22 deterministic Perlin lattice.
class _W3cTurbulenceLattice {
  final Int32List _perm = Int32List(SvgFilterNoiseEngine._bSize);
  final Float64List _gradX = Float64List(4 * SvgFilterNoiseEngine._bSize);
  final Float64List _gradY = Float64List(4 * SvgFilterNoiseEngine._bSize);

  _W3cTurbulenceLattice(int rawSeed) {
    int seed = rawSeed;
    if (seed <= 0) {
      seed = -(seed % (SvgFilterNoiseEngine._randM - 1)) + 1;
    }
    if (seed > SvgFilterNoiseEngine._randM - 1) {
      seed = SvgFilterNoiseEngine._randM - 1;
    }

    int nextRand() {
      seed =
          SvgFilterNoiseEngine._randA * (seed % SvgFilterNoiseEngine._randQ) -
          SvgFilterNoiseEngine._randR * (seed ~/ SvgFilterNoiseEngine._randQ);
      if (seed <= 0) seed += SvgFilterNoiseEngine._randM;
      return seed;
    }

    const n = SvgFilterNoiseEngine._bSize;
    for (int ch = 0; ch < 4; ch++) {
      final base = ch * n;
      for (int i = 0; i < n; i++) {
        final gx = ((nextRand() % (n + n)) - n) / n;
        final gy = ((nextRand() % (n + n)) - n) / n;
        final len = math.sqrt(gx * gx + gy * gy);
        if (len > 1e-6) {
          _gradX[base + i] = gx / len;
          _gradY[base + i] = gy / len;
        } else {
          _gradX[base + i] = 1.0;
          _gradY[base + i] = 0.0;
        }
      }
    }

    for (int i = 0; i < n; i++) {
      _perm[i] = i;
    }
    for (int i = n - 1; i > 0; i--) {
      final j = nextRand() % n;
      final tmp = _perm[i];
      _perm[i] = _perm[j];
      _perm[j] = tmp;
    }
  }

  double noise2(int ch, double x, double y) {
    const bm = SvgFilterNoiseEngine._bm;
    final tx = x + 4096.0;
    final ty = y + 4096.0;
    final bx0 = tx.floor() & bm;
    final bx1 = (bx0 + 1) & bm;
    final by0 = ty.floor() & bm;
    final by1 = (by0 + 1) & bm;

    final rx0 = tx - tx.floor();
    final rx1 = rx0 - 1.0;
    final ry0 = ty - ty.floor();
    final ry1 = ry0 - 1.0;

    final sx = rx0 * rx0 * (3.0 - 2.0 * rx0);
    final sy = ry0 * ry0 * (3.0 - 2.0 * ry0);

    final i = _perm[bx0];
    final j = _perm[bx1];
    final b00 = _perm[(i + by0) & bm];
    final b10 = _perm[(j + by0) & bm];
    final b01 = _perm[(i + by1) & bm];
    final b11 = _perm[(j + by1) & bm];

    final base = ch * SvgFilterNoiseEngine._bSize;
    final u0 = rx0 * _gradX[base + b00] + ry0 * _gradY[base + b00];
    final v0 = rx1 * _gradX[base + b10] + ry0 * _gradY[base + b10];
    final a = u0 + sx * (v0 - u0);

    final u1 = rx0 * _gradX[base + b01] + ry1 * _gradY[base + b01];
    final v1 = rx1 * _gradX[base + b11] + ry1 * _gradY[base + b11];
    final b = u1 + sx * (v1 - u1);

    return a + sy * (b - a);
  }
}
