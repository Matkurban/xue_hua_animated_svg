import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/svg_gradient.dart';
import '../model/svg_node.dart';
import '../model/svg_transform.dart';
import 'svg_animation_timing.dart';

/// Precompiled `<animateTransform>` or CSS `@keyframes transform` track.
///
/// Mutates `target.transformMatrix` (or `gradient.currentGradientMatrix`) in-place
/// without allocating temporary `Matrix4` objects.
class SvgTransformAnimationTrack extends SvgAnimationTrack {
  final SvgElement? targetElement;
  final SvgGradientNode? targetGradient;
  final SvgTransformType transformType;
  final ui.Rect documentViewBox;

  /// Flattened keyframe parameter array (`stride = 3` per keyframe: `[v0, v1, v2]`).
  /// - `translate`: `[tx, ty, 0]`
  /// - `scale`: `[sx, sy, 0]`
  /// - `rotate`: `[angleDeg, cx, cy]`
  /// - `skewX` / `skewY` / `rotateX` / `rotateY` / `rotateZ` / `perspective`: `[val, 0, 0]`
  final Float64List keyframeValues;

  /// Whether `(cx, cy)` in `rotate(angle, cx, cy)` was explicitly provided.
  final bool hasExplicitRotateAnchor;

  SvgTransformAnimationTrack({
    required super.timing,
    this.targetElement,
    this.targetGradient,
    required this.transformType,
    required this.keyframeValues,
    required this.documentViewBox,
    this.hasExplicitRotateAnchor = false,
  });

  @override
  void applyAt(int elapsedUs) {
    final keyframeCount = keyframeValues.length ~/ 3;
    if (keyframeCount == 0) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    double v0, v1, v2;
    if (keyframeCount == 1) {
      v0 = keyframeValues[0];
      v1 = keyframeValues[1];
      v2 = keyframeValues[2];
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      final i0 = seg * 3;
      final i1 = (seg + 1) * 3;
      v0 =
          keyframeValues[i0] +
          (keyframeValues[i1] - keyframeValues[i0]) * localT;
      v1 =
          keyframeValues[i0 + 1] +
          (keyframeValues[i1 + 1] - keyframeValues[i0 + 1]) * localT;
      v2 =
          keyframeValues[i0 + 2] +
          (keyframeValues[i1 + 2] - keyframeValues[i0 + 2]) * localT;
    }

    final Float64List matrix;
    double originX = 0.0;
    double originY = 0.0;

    if (targetElement != null) {
      final elem = targetElement!;
      matrix = elem.transformMatrix;
      if (timing.additiveMode == SvgAdditiveMode.replace) {
        SvgMatrixMath.resetToIdentity(matrix);
      }
      final origin = elem.style.currentTransformOrigin;
      originX = origin.resolveX(elem.cachedBounds, documentViewBox);
      originY = origin.resolveY(elem.cachedBounds, documentViewBox);
    } else if (targetGradient != null) {
      final grad = targetGradient!;
      matrix = grad.currentGradientMatrix;
      if (timing.additiveMode == SvgAdditiveMode.replace) {
        SvgMatrixMath.resetToIdentity(matrix);
      }
    } else {
      return;
    }

    final useOrigin =
        (originX != 0.0 || originY != 0.0) &&
        !(transformType == SvgTransformType.rotate && hasExplicitRotateAnchor);

    if (useOrigin) {
      SvgMatrixMath.translateInPlace(matrix, originX, originY);
    }

    switch (transformType) {
      case SvgTransformType.translate:
        SvgMatrixMath.translateInPlace(matrix, v0, v1);
      case SvgTransformType.scale:
        SvgMatrixMath.scaleInPlace(matrix, v0, v1);
      case SvgTransformType.rotate:
        SvgMatrixMath.rotateAroundAnchorInPlace(matrix, v0, v1, v2);
      case SvgTransformType.skewX:
        SvgMatrixMath.skewXInPlace(matrix, v0);
      case SvgTransformType.skewY:
        SvgMatrixMath.skewYInPlace(matrix, v0);
      case SvgTransformType.rotateX:
        SvgMatrixMath.rotateXInPlace(matrix, v0);
      case SvgTransformType.rotateY:
        SvgMatrixMath.rotateYInPlace(matrix, v0);
      case SvgTransformType.rotateZ:
        SvgMatrixMath.rotateAroundAnchorInPlace(matrix, v0, 0.0, 0.0);
      case SvgTransformType.perspective:
        SvgMatrixMath.perspectiveInPlace(matrix, v0);
      case SvgTransformType.matrix:
        break;
    }

    if (useOrigin) {
      SvgMatrixMath.translateInPlace(matrix, -originX, -originY);
    }
  }
}

/// Precompiled multi-operation CSS `@keyframes` transform track where each keyframe
/// contains a sequence of [SvgTransformOp] instructions (e.g., `perspective(400px) rotateY(180deg) scale(1.1)`).
class SvgCssMultiTransformTrack extends SvgAnimationTrack {
  final SvgElement target;
  final List<List<SvgTransformOp>> keyframeOps;
  final ui.Rect documentViewBox;

  SvgCssMultiTransformTrack({
    required super.timing,
    required this.target,
    required this.keyframeOps,
    required this.documentViewBox,
  });

  @override
  void applyAt(int elapsedUs) {
    if (keyframeOps.isEmpty) return;
    final progress = timing.evaluateSimpleProgress(elapsedUs);
    if (progress < 0.0) return;

    final matrix = target.transformMatrix;
    if (timing.additiveMode == SvgAdditiveMode.replace) {
      SvgMatrixMath.resetToIdentity(matrix);
    }

    final origin = target.style.currentTransformOrigin;
    final ox = origin.resolveX(target.cachedBounds, documentViewBox);
    final oy = origin.resolveY(target.cachedBounds, documentViewBox);
    final hasOrigin = ox != 0.0 || oy != 0.0;

    if (hasOrigin) {
      SvgMatrixMath.translateInPlace(matrix, ox, oy);
    }

    if (keyframeOps.length == 1) {
      final ops = keyframeOps[0];
      for (int i = 0; i < ops.length; i++) {
        SvgMatrixMath.applyOpInPlace(matrix, ops[i]);
      }
    } else {
      final localT = timing.resolveSegment(progress, segBuffer);
      final seg = segBuffer[0];
      final opsA = keyframeOps[seg];
      final opsB = keyframeOps[seg + 1];
      final maxLen = math.max(opsA.length, opsB.length);

      for (int i = 0; i < maxLen; i++) {
        final opA = i < opsA.length ? opsA[i] : null;
        final opB = i < opsB.length ? opsB[i] : null;
        final type = (opA ?? opB)!.type;
        if (opA != null && opB != null && opA.type == opB.type) {
          _applyInterpolatedOp(matrix, type, opA.values, opB.values, localT);
        } else if (opA != null && opB == null) {
          final identityVals = _identityValuesFor(opA.type);
          _applyInterpolatedOp(
            matrix,
            opA.type,
            opA.values,
            identityVals,
            localT,
          );
        } else if (opA == null && opB != null) {
          final identityVals = _identityValuesFor(opB.type);
          _applyInterpolatedOp(
            matrix,
            opB.type,
            identityVals,
            opB.values,
            localT,
          );
        } else if (opA != null) {
          SvgMatrixMath.applyOpInPlace(matrix, localT < 0.5 ? opA : opB!);
        }
      }
    }

    if (hasOrigin) {
      SvgMatrixMath.translateInPlace(matrix, -ox, -oy);
    }
  }

  static final Float64List _zero3 = Float64List(3);
  static final Float64List _one2 = Float64List.fromList([1.0, 1.0]);
  static final Float64List _idMatrix6 = Float64List.fromList([
    1.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
  ]);

  static Float64List _identityValuesFor(SvgTransformType type) {
    switch (type) {
      case SvgTransformType.scale:
        return _one2;
      case SvgTransformType.matrix:
        return _idMatrix6;
      default:
        return _zero3;
    }
  }

  static void _applyInterpolatedOp(
    Float64List m,
    SvgTransformType type,
    Float64List a,
    Float64List b,
    double t,
  ) {
    double lerpAt(int idx, double fallback) {
      final va = idx < a.length ? a[idx] : fallback;
      final vb = idx < b.length ? b[idx] : fallback;
      return va + (vb - va) * t;
    }

    switch (type) {
      case SvgTransformType.translate:
        SvgMatrixMath.translateInPlace(m, lerpAt(0, 0.0), lerpAt(1, 0.0));
      case SvgTransformType.scale:
        SvgMatrixMath.scaleInPlace(m, lerpAt(0, 1.0), lerpAt(1, 1.0));
      case SvgTransformType.rotate:
        SvgMatrixMath.rotateAroundAnchorInPlace(
          m,
          lerpAt(0, 0.0),
          lerpAt(1, 0.0),
          lerpAt(2, 0.0),
        );
      case SvgTransformType.skewX:
        SvgMatrixMath.skewXInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.skewY:
        SvgMatrixMath.skewYInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.rotateX:
        SvgMatrixMath.rotateXInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.rotateY:
        SvgMatrixMath.rotateYInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.rotateZ:
        SvgMatrixMath.rotateAroundAnchorInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.perspective:
        SvgMatrixMath.perspectiveInPlace(m, lerpAt(0, 0.0));
      case SvgTransformType.matrix:
        SvgMatrixMath.multiplyAffine2DInPlace(
          m,
          lerpAt(0, 1.0),
          lerpAt(1, 0.0),
          lerpAt(2, 0.0),
          lerpAt(3, 1.0),
          lerpAt(4, 0.0),
          lerpAt(5, 0.0),
        );
    }
  }
}
