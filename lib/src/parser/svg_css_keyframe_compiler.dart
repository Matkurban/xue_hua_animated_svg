import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Cubic;

import '../animation/svg_motion_morph.dart';
import '../animation/svg_timeline.dart';
import '../model/svg_node.dart';
import '../model/svg_transform.dart';
import 'svg_css_models.dart';
import 'svg_css_value_parser.dart';
import 'svg_path_parser.dart';

/// Compiles CSS `@keyframes` rules and `animation` configs into [SvgAnimationTrack]s.
abstract final class SvgCssKeyframeCompiler {
  /// Compiles a matched [SvgCssAnimationConfig] and `@keyframes` stop list into
  /// internal [SvgAnimationTrack] instances on [target].
  static List<SvgAnimationTrack> compileKeyframesForElement({
    required SvgElement target,
    required SvgCssAnimationConfig config,
    required List<SvgCssKeyframeStop> stops,
    required ui.Rect documentViewBox,
  }) {
    final tracks = <SvgAnimationTrack>[];
    if (stops.isEmpty || config.durationUs <= 0) return tracks;

    // Collect all animated property names across keyframe stops
    final animatedProps = <String>{};
    for (final stop in stops) {
      animatedProps.addAll(stop.declarations.keys);
    }

    // Ensure 0.0 and 1.0 stops exist by synthesizing from element's base state if omitted
    final normalizedStops = List<SvgCssKeyframeStop>.from(stops);
    if (normalizedStops.first.offset > 0.0) {
      normalizedStops.insert(
        0,
        const SvgCssKeyframeStop(offset: 0.0, declarations: {}),
      );
    }
    if (normalizedStops.last.offset < 1.0) {
      normalizedStops.add(
        const SvgCssKeyframeStop(offset: 1.0, declarations: {}),
      );
    }

    for (final prop in animatedProps) {
      final track = _compilePropertyKeyframeTrack(
        target: target,
        property: prop,
        config: config,
        stops: normalizedStops,
        documentViewBox: documentViewBox,
      );
      if (track != null) {
        tracks.add(track);
      }
    }

    return tracks;
  }

  static SvgAnimationTrack? _compilePropertyKeyframeTrack({
    required SvgElement target,
    required String property,
    required SvgCssAnimationConfig config,
    required List<SvgCssKeyframeStop> stops,
    required ui.Rect documentViewBox,
  }) {
    // Filter stops that define this property, or include endpoints 0.0 and 1.0
    final keyTimesList = <double>[];
    final rawValues = <String>[];
    final splines = <Cubic>[];
    bool hasCustomSpline = config.timingCurve != null;

    for (int i = 0; i < stops.length; i++) {
      final stop = stops[i];
      final val =
          stop.declarations[property] ??
          ((i == 0 || i == stops.length - 1)
              ? _defaultPropertyStringForElement(target, property)
              : null);
      if (val != null) {
        keyTimesList.add(stop.offset);
        rawValues.add(val);
        if (stop.easingToNext != null) {
          hasCustomSpline = true;
          splines.add(stop.easingToNext!);
        } else {
          splines.add(config.timingCurve ?? const Cubic(0.0, 0.0, 1.0, 1.0));
        }
      }
    }

    if (rawValues.length < 2) return null;
    if (splines.length >= rawValues.length) {
      splines.removeLast();
    }

    final beginOffsets = List<int>.unmodifiable([config.delayUs]);
    final timing = SvgAnimationTiming(
      beginOffsetsUs: beginOffsets,
      durationUs: config.durationUs,
      repeatCount: config.iterationCount,
      fillMode: config.fillMode,
      direction: config.direction,
      calcMode: config.isDiscreteSteps
          ? SvgCalcMode.discrete
          : (hasCustomSpline ? SvgCalcMode.spline : SvgCalcMode.linear),
      keyTimes: Float64List.fromList(keyTimesList),
      keySplines: hasCustomSpline ? splines : null,
    );

    switch (property) {
      case 'transform':
        final opsPerKeyframe = <List<SvgTransformOp>>[];
        for (final raw in rawValues) {
          opsPerKeyframe.add(
            raw == 'none'
                ? const <SvgTransformOp>[]
                : SvgCssValueParser.parseTransformOps(raw),
          );
        }
        return SvgCssMultiTransformTrack(
          timing: timing,
          target: target,
          keyframeOps: opsPerKeyframe,
          documentViewBox: documentViewBox,
        );

      case 'opacity':
      case 'fill-opacity':
      case 'stroke-opacity':
      case 'stroke-width':
      case 'stroke-dashoffset':
      case 'rx':
      case 'ry':
      case 'r':
      case 'cx':
      case 'cy':
      case 'x':
      case 'y':
      case 'width':
      case 'height':
        final scalarTarget = _mapScalarProperty(property);
        if (scalarTarget == null) return null;
        final values = Float64List(rawValues.length);
        for (int i = 0; i < rawValues.length; i++) {
          values[i] =
              (property.contains('opacity')
                  ? SvgCssValueParser.parseNumberOrPercent(rawValues[i])
                  : SvgCssValueParser.parseLength(rawValues[i])) ??
              0.0;
        }
        if (property == 'stroke-dashoffset' && target is SvgGeometryNode) {
          target.needsPathMetrics = true;
        }
        return SvgScalarAnimationTrack(
          timing: timing,
          target: target,
          property: scalarTarget,
          keyframes: values,
        );

      case 'filter':
        final values = Float64List(rawValues.length);
        for (int i = 0; i < rawValues.length; i++) {
          values[i] = SvgCssValueParser.parseBlurFilter(rawValues[i]) ?? 0.0;
        }
        return SvgScalarAnimationTrack(
          timing: timing,
          target: target,
          property: SvgScalarTarget.blurSigma,
          keyframes: values,
        );

      case 'fill':
      case 'stroke':
        final colors = <ui.Color>[];
        for (final raw in rawValues) {
          colors.add(
            SvgCssValueParser.parseColor(raw) ?? const ui.Color(0xFF000000),
          );
        }
        return SvgColorAnimationTrack(
          timing: timing,
          target: target,
          property: property == 'fill'
              ? SvgColorTarget.fill
              : SvgColorTarget.stroke,
          keyframes: colors,
        );

      case 'stroke-dasharray':
        final rawArrays = <Float64List>[];
        for (final raw in rawValues) {
          rawArrays.add(SvgCssValueParser.parseNumberList(raw));
        }
        final normalized = SvgCssValueParser.normalizeDashArrayKeyframes(
          rawArrays,
        );
        if (normalized.isEmpty) return null;
        if (target is SvgGeometryNode) {
          target.needsPathMetrics = true;
        }
        return SvgDashArrayAnimationTrack(
          timing: timing,
          target: target,
          keyframes: normalized,
        );

      case 'd':
        if (target is SvgPathNode) {
          final coordsList = <Float64List>[];
          for (final raw in rawValues) {
            final cleaned = raw
                .replaceAll(RegExp(r'^path\s*\(\s*["\x27]?'), '')
                .replaceAll(RegExp(r'["\x27]?\s*\)$'), '');
            final parsed = SvgPathParser.parse(cleaned);
            if (parsed.isIsomorphicWith(target.precompiledPath)) {
              coordsList.add(parsed.coords);
            }
          }
          if (coordsList.length == rawValues.length) {
            return SvgPathMorphAnimationTrack(
              timing: timing,
              target: target,
              keyframeCoords: coordsList,
            );
          }
        }
        return null;

      default:
        return null;
    }
  }

  static String? _defaultPropertyStringForElement(
    SvgElement target,
    String property,
  ) {
    final s = target.style;
    switch (property) {
      case 'transform':
        return 'none';
      case 'opacity':
        return '${s.baseOpacity ?? 1.0}';
      case 'fill-opacity':
        return '${s.baseFillOpacity ?? 1.0}';
      case 'stroke-opacity':
        return '${s.baseStrokeOpacity ?? 1.0}';
      case 'stroke-width':
        return '${s.baseStrokeWidth ?? 1.0}';
      case 'stroke-dashoffset':
        return '${s.baseStrokeDashoffset ?? 0.0}';
      case 'filter':
        return 'blur(${s.baseBlurSigma ?? 0.0}px)';
      case 'fill':
        final c = s.baseFill?.color ?? const ui.Color(0xFF000000);
        return '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      case 'stroke':
        final c = s.baseStroke?.color ?? const ui.Color(0xFF000000);
        return '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      default:
        return null;
    }
  }

  static SvgScalarTarget? _mapScalarProperty(String prop) {
    switch (prop) {
      case 'opacity':
        return SvgScalarTarget.opacity;
      case 'fill-opacity':
        return SvgScalarTarget.fillOpacity;
      case 'stroke-opacity':
        return SvgScalarTarget.strokeOpacity;
      case 'stroke-width':
        return SvgScalarTarget.strokeWidth;
      case 'stroke-dashoffset':
        return SvgScalarTarget.strokeDashoffset;
      case 'x':
        return SvgScalarTarget.x;
      case 'y':
        return SvgScalarTarget.y;
      case 'width':
        return SvgScalarTarget.width;
      case 'height':
        return SvgScalarTarget.height;
      case 'rx':
        return SvgScalarTarget.rx;
      case 'ry':
        return SvgScalarTarget.ry;
      case 'cx':
        return SvgScalarTarget.cx;
      case 'cy':
        return SvgScalarTarget.cy;
      case 'r':
        return SvgScalarTarget.r;
      default:
        return null;
    }
  }
}
