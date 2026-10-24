import 'dart:math' as math;
import 'dart:typed_data';

/// Precompiled SVG transform operation type.
enum SvgTransformType {
  translate,
  scale,
  rotate,
  skewX,
  skewY,
  matrix,
  rotateX,
  rotateY,
  rotateZ,
  perspective,
}

/// Immutable precompiled transform instruction parsed during AST build phase.
class SvgTransformOp {
  final SvgTransformType type;
  final Float64List values;

  const SvgTransformOp(this.type, this.values);

  factory SvgTransformOp.translate(double tx, [double ty = 0.0]) {
    final list = Float64List(2);
    list[0] = tx;
    list[1] = ty;
    return SvgTransformOp(SvgTransformType.translate, list);
  }

  factory SvgTransformOp.scale(double sx, [double? sy]) {
    final list = Float64List(2);
    list[0] = sx;
    list[1] = sy ?? sx;
    return SvgTransformOp(SvgTransformType.scale, list);
  }

  factory SvgTransformOp.rotate(
    double angleDeg, [
    double cx = 0.0,
    double cy = 0.0,
  ]) {
    final list = Float64List(3);
    list[0] = angleDeg;
    list[1] = cx;
    list[2] = cy;
    return SvgTransformOp(SvgTransformType.rotate, list);
  }

  factory SvgTransformOp.skewX(double angleDeg) {
    final list = Float64List(1);
    list[0] = angleDeg;
    return SvgTransformOp(SvgTransformType.skewX, list);
  }

  factory SvgTransformOp.skewY(double angleDeg) {
    final list = Float64List(1);
    list[0] = angleDeg;
    return SvgTransformOp(SvgTransformType.skewY, list);
  }

  factory SvgTransformOp.matrix(
    double a,
    double b,
    double c,
    double d,
    double e,
    double f,
  ) {
    final list = Float64List(6);
    list[0] = a;
    list[1] = b;
    list[2] = c;
    list[3] = d;
    list[4] = e;
    list[5] = f;
    return SvgTransformOp(SvgTransformType.matrix, list);
  }

  factory SvgTransformOp.rotateX(double angleDeg) {
    final list = Float64List(1);
    list[0] = angleDeg;
    return SvgTransformOp(SvgTransformType.rotateX, list);
  }

  factory SvgTransformOp.rotateY(double angleDeg) {
    final list = Float64List(1);
    list[0] = angleDeg;
    return SvgTransformOp(SvgTransformType.rotateY, list);
  }

  factory SvgTransformOp.rotateZ(double angleDeg) {
    final list = Float64List(1);
    list[0] = angleDeg;
    return SvgTransformOp(SvgTransformType.rotateZ, list);
  }

  factory SvgTransformOp.perspective(double distance) {
    final list = Float64List(1);
    list[0] = distance;
    return SvgTransformOp(SvgTransformType.perspective, list);
  }
}

/// Zero-allocation 4x4 column-major matrix math utilities operating directly on
/// [Float64List] of length 16 (compatible with `Canvas.transform` and `Matrix4`).
///
/// Layout of 4x4 column-major matrix `m`:
/// ```
/// [ m[0]  m[4]  m[8]   m[12] ]
/// [ m[1]  m[5]  m[9]   m[13] ]
/// [ m[2]  m[6]  m[10]  m[14] ]
/// [ m[3]  m[7]  m[11]  m[15] ]
/// ```
/// For 2D affine transforms `[a, b, c, d, tx, ty]`:
/// `m[0] = a`, `m[1] = b`, `m[4] = c`, `m[5] = d`, `m[12] = tx`, `m[13] = ty`.
abstract final class SvgMatrixMath {
  static const double degToRad = math.pi / 180.0;

  /// Creates a new 16-element identity matrix buffer.
  static Float64List createIdentity() {
    final m = Float64List(16);
    resetToIdentity(m);
    return m;
  }

  /// Resets [m] to the 4x4 identity matrix in-place without allocating memory.
  static void resetToIdentity(Float64List m) {
    m[0] = 1.0;
    m[1] = 0.0;
    m[2] = 0.0;
    m[3] = 0.0;
    m[4] = 0.0;
    m[5] = 1.0;
    m[6] = 0.0;
    m[7] = 0.0;
    m[8] = 0.0;
    m[9] = 0.0;
    m[10] = 1.0;
    m[11] = 0.0;
    m[12] = 0.0;
    m[13] = 0.0;
    m[14] = 0.0;
    m[15] = 1.0;
  }

  /// Copies 16 values from [source] into [target] in-place.
  static void copyInto(Float64List source, Float64List target) {
    for (int i = 0; i < 16; i++) {
      target[i] = source[i];
    }
  }

  /// Checks whether [m] is the exact 4x4 identity matrix.
  static bool isIdentity(Float64List m) {
    return m[0] == 1.0 &&
        m[1] == 0.0 &&
        m[2] == 0.0 &&
        m[3] == 0.0 &&
        m[4] == 0.0 &&
        m[5] == 1.0 &&
        m[6] == 0.0 &&
        m[7] == 0.0 &&
        m[8] == 0.0 &&
        m[9] == 0.0 &&
        m[10] == 1.0 &&
        m[11] == 0.0 &&
        m[12] == 0.0 &&
        m[13] == 0.0 &&
        m[14] == 0.0 &&
        m[15] == 1.0;
  }

  /// Post-multiplies [m] by a 2D affine matrix `[a, b, c, d, tx, ty]` in-place:
  /// `m = m * Affine(a, b, c, d, tx, ty)`.
  static void multiplyAffine2DInPlace(
    Float64List m,
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty,
  ) {
    final m0 = m[0], m1 = m[1], m2 = m[2], m3 = m[3];
    final m4 = m[4], m5 = m[5], m6 = m[6], m7 = m[7];
    final m12 = m[12], m13 = m[13], m14 = m[14], m15 = m[15];

    m[0] = m0 * a + m4 * b;
    m[1] = m1 * a + m5 * b;
    m[2] = m2 * a + m6 * b;
    m[3] = m3 * a + m7 * b;

    m[4] = m0 * c + m4 * d;
    m[5] = m1 * c + m5 * d;
    m[6] = m2 * c + m6 * d;
    m[7] = m3 * c + m7 * d;

    m[12] = m0 * tx + m4 * ty + m12;
    m[13] = m1 * tx + m5 * ty + m13;
    m[14] = m2 * tx + m6 * ty + m14;
    m[15] = m3 * tx + m7 * ty + m15;
  }

  /// Post-multiplies [m] by translation `(tx, ty)` in-place.
  static void translateInPlace(Float64List m, double tx, double ty) {
    if (tx == 0.0 && ty == 0.0) return;
    m[12] += m[0] * tx + m[4] * ty;
    m[13] += m[1] * tx + m[5] * ty;
    m[14] += m[2] * tx + m[6] * ty;
    m[15] += m[3] * tx + m[7] * ty;
  }

  /// Post-multiplies [m] by scaling `(sx, sy)` in-place.
  static void scaleInPlace(Float64List m, double sx, double sy) {
    if (sx == 1.0 && sy == 1.0) return;
    m[0] *= sx;
    m[1] *= sx;
    m[2] *= sx;
    m[3] *= sx;
    m[4] *= sy;
    m[5] *= sy;
    m[6] *= sy;
    m[7] *= sy;
  }

  /// Post-multiplies [m] by a 2D rotation of [angleDeg] degrees around `(cx, cy)` in-place.
  /// Equivalent to `T(cx, cy) * R(angleDeg) * T(-cx, -cy)`.
  static void rotateAroundAnchorInPlace(
    Float64List m,
    double angleDeg, [
    double cx = 0.0,
    double cy = 0.0,
  ]) {
    if (angleDeg == 0.0) return;
    final rad = angleDeg * degToRad;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    if (cx == 0.0 && cy == 0.0) {
      multiplyAffine2DInPlace(m, cosA, sinA, -sinA, cosA, 0.0, 0.0);
    } else {
      final tx = cx - cosA * cx + sinA * cy;
      final ty = cy - sinA * cx - cosA * cy;
      multiplyAffine2DInPlace(m, cosA, sinA, -sinA, cosA, tx, ty);
    }
  }

  /// Post-multiplies [m] by a horizontal skew of [angleDeg] degrees in-place.
  static void skewXInPlace(Float64List m, double angleDeg) {
    if (angleDeg == 0.0) return;
    final tanA = math.tan(angleDeg * degToRad);
    multiplyAffine2DInPlace(m, 1.0, 0.0, tanA, 1.0, 0.0, 0.0);
  }

  /// Post-multiplies [m] by a vertical skew of [angleDeg] degrees in-place.
  static void skewYInPlace(Float64List m, double angleDeg) {
    if (angleDeg == 0.0) return;
    final tanA = math.tan(angleDeg * degToRad);
    multiplyAffine2DInPlace(m, 1.0, tanA, 0.0, 1.0, 0.0, 0.0);
  }

  /// Post-multiplies [m] by a 3D X-axis rotation of [angleDeg] degrees in-place.
  static void rotateXInPlace(Float64List m, double angleDeg) {
    if (angleDeg == 0.0) return;
    final rad = angleDeg * degToRad;
    final c = math.cos(rad);
    final s = math.sin(rad);
    final m4 = m[4], m5 = m[5], m6 = m[6], m7 = m[7];
    final m8 = m[8], m9 = m[9], m10 = m[10], m11 = m[11];

    m[4] = m4 * c + m8 * s;
    m[5] = m5 * c + m9 * s;
    m[6] = m6 * c + m10 * s;
    m[7] = m7 * c + m11 * s;

    m[8] = m8 * c - m4 * s;
    m[9] = m9 * c - m5 * s;
    m[10] = m10 * c - m6 * s;
    m[11] = m11 * c - m7 * s;
  }

  /// Post-multiplies [m] by a 3D Y-axis rotation of [angleDeg] degrees in-place.
  static void rotateYInPlace(Float64List m, double angleDeg) {
    if (angleDeg == 0.0) return;
    final rad = angleDeg * degToRad;
    final c = math.cos(rad);
    final s = math.sin(rad);
    final m0 = m[0], m1 = m[1], m2 = m[2], m3 = m[3];
    final m8 = m[8], m9 = m[9], m10 = m[10], m11 = m[11];

    m[0] = m0 * c - m8 * s;
    m[1] = m1 * c - m9 * s;
    m[2] = m2 * c - m10 * s;
    m[3] = m3 * c - m11 * s;

    m[8] = m0 * s + m8 * c;
    m[9] = m1 * s + m9 * c;
    m[10] = m2 * s + m10 * c;
    m[11] = m3 * s + m11 * c;
  }

  /// Post-multiplies [m] by a 3D perspective depth [d] (`-1 / d` on Z-to-W) in-place.
  static void perspectiveInPlace(Float64List m, double d) {
    if (d <= 0.0) return;
    final inv = -1.0 / d;
    m[8] += m[12] * inv;
    m[9] += m[13] * inv;
    m[10] += m[14] * inv;
    m[11] += m[15] * inv;
  }

  /// Post-multiplies 4x4 matrix [target] by 4x4 matrix [other] in-place (`target = target * other`).
  static void multiply4x4InPlace(Float64List target, Float64List other) {
    final a00 = target[0], a10 = target[1], a20 = target[2], a30 = target[3];
    final a01 = target[4], a11 = target[5], a21 = target[6], a31 = target[7];
    final a02 = target[8], a12 = target[9], a22 = target[10], a32 = target[11];
    final a03 = target[12],
        a13 = target[13],
        a23 = target[14],
        a33 = target[15];

    for (int col = 0; col < 4; col++) {
      final idx = col * 4;
      final b0 = other[idx];
      final b1 = other[idx + 1];
      final b2 = other[idx + 2];
      final b3 = other[idx + 3];
      target[idx] = a00 * b0 + a01 * b1 + a02 * b2 + a03 * b3;
      target[idx + 1] = a10 * b0 + a11 * b1 + a12 * b2 + a13 * b3;
      target[idx + 2] = a20 * b0 + a21 * b1 + a22 * b2 + a23 * b3;
      target[idx + 3] = a30 * b0 + a31 * b1 + a32 * b2 + a33 * b3;
    }
  }

  /// Applies a single precompiled [SvgTransformOp] to [m] in-place.
  static void applyOpInPlace(Float64List m, SvgTransformOp op) {
    final v = op.values;
    switch (op.type) {
      case SvgTransformType.translate:
        translateInPlace(m, v[0], v.length > 1 ? v[1] : 0.0);
      case SvgTransformType.scale:
        scaleInPlace(m, v[0], v.length > 1 ? v[1] : v[0]);
      case SvgTransformType.rotate:
        rotateAroundAnchorInPlace(
          m,
          v[0],
          v.length > 1 ? v[1] : 0.0,
          v.length > 2 ? v[2] : 0.0,
        );
      case SvgTransformType.skewX:
        skewXInPlace(m, v[0]);
      case SvgTransformType.skewY:
        skewYInPlace(m, v[0]);
      case SvgTransformType.matrix:
        multiplyAffine2DInPlace(m, v[0], v[1], v[2], v[3], v[4], v[5]);
      case SvgTransformType.rotateX:
        rotateXInPlace(m, v[0]);
      case SvgTransformType.rotateY:
        rotateYInPlace(m, v[0]);
      case SvgTransformType.rotateZ:
        rotateAroundAnchorInPlace(m, v[0]);
      case SvgTransformType.perspective:
        perspectiveInPlace(m, v[0]);
    }
  }

  /// Applies a list of precompiled [ops] to [m] in-place, optionally anchored at `(originX, originY)`.
  static void applyOpsWithOriginInPlace(
    Float64List m,
    List<SvgTransformOp> ops, {
    double originX = 0.0,
    double originY = 0.0,
  }) {
    if (ops.isEmpty) return;
    final hasOrigin = originX != 0.0 || originY != 0.0;
    if (hasOrigin) {
      translateInPlace(m, originX, originY);
    }
    for (int i = 0; i < ops.length; i++) {
      applyOpInPlace(m, ops[i]);
    }
    if (hasOrigin) {
      translateInPlace(m, -originX, -originY);
    }
  }
}
