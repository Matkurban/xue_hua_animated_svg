import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Cubic;

import '../animation/svg_motion_morph.dart';
import '../animation/svg_timeline.dart';
import '../model/svg_gradient.dart';
import '../model/svg_node.dart';
import '../model/svg_style.dart';
import '../model/svg_transform.dart';
import 'svg_css_parser.dart';
import 'svg_path_parser.dart';
import 'svg_xml_tokenizer.dart';

/// Deferred `<animateMotion>` descriptor resolved after all `<path>` elements
/// (including `<mpath>` targets) have been registered in `geometryById`.
class SvgPendingMotionTrack {
  final SvgElement target;
  final SvgXmlElement xmlNode;
  final SvgAnimationTiming timing;

  const SvgPendingMotionTrack({
    required this.target,
    required this.xmlNode,
    required this.timing,
  });
}

/// Compiles SMIL `<animate>`, `<animateTransform>`, and `<animateMotion>` XML
/// elements into precompiled [SvgAnimationTrack] instances.
class SvgSmilCompiler {
  final ui.Rect viewBox;
  final List<SvgAnimationTrack> tracks;
  final Set<SvgElement> animatedElementsSet;
  final Set<SvgGradientNode> animatedGradientsSet;
  final List<SvgPendingMotionTrack> pendingMotions = <SvgPendingMotionTrack>[];

  SvgSmilCompiler({
    required this.viewBox,
    required this.tracks,
    required this.animatedElementsSet,
    required this.animatedGradientsSet,
  });

  void compileStopAnimate(SvgGradientStop stop, SvgXmlElement animXml) {
    final attrName = animXml.attr('attributeName')?.trim() ?? '';
    final rawKeyframes = extractRawKeyframes(
      animXml,
      fallbackFrom: _defaultStopAttrValue(stop, attrName),
    );
    if (rawKeyframes.isEmpty) return;

    if (attrName == 'stop-color') {
      final colors = <ui.Color>[
        for (final r in rawKeyframes)
          SvgCssParser.parseColor(r) ?? stop.baseColor,
      ];
      final timing = parseSmilTiming(animXml, colors.length);
      if (timing == null) return;
      tracks.add(
        SvgColorAnimationTrack(
          timing: timing,
          target: stop,
          property: SvgColorTarget.stopColor,
          keyframes: colors,
        ),
      );
      stop.isAnimated = true;
    } else if (attrName == 'offset' || attrName == 'stop-opacity') {
      final nums = Float64List.fromList([
        for (final r in rawKeyframes)
          SvgCssParser.parseNumberOrPercent(r) ?? 0.0,
      ]);
      final timing = parseSmilTiming(animXml, nums.length, numericValues: nums);
      if (timing == null) return;
      tracks.add(
        SvgScalarAnimationTrack(
          timing: timing,
          target: stop,
          property: attrName == 'offset'
              ? SvgScalarTarget.stopOffset
              : SvgScalarTarget.stopOpacity,
          keyframes: nums,
        ),
      );
      stop.isAnimated = true;
    }
  }

  String? _defaultStopAttrValue(SvgGradientStop stop, String attrName) {
    switch (attrName) {
      case 'offset':
        return '${stop.baseOffset}';
      case 'stop-opacity':
        return '${stop.baseOpacity}';
      case 'stop-color':
        return '#${stop.baseColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      default:
        return null;
    }
  }

  void compileGradientAnimations(SvgGradientNode grad, SvgXmlElement gradXml) {
    for (final stop in grad.stops) {
      if (stop.isAnimated) {
        grad.isAnimated = true;
        animatedGradientsSet.add(grad);
      }
    }

    for (final child in gradXml.children) {
      if (child.name == 'animate') {
        final attr = child.attr('attributeName')?.trim() ?? '';
        final scalarTarget = _mapGradientScalarTarget(attr);
        if (scalarTarget != null) {
          final rawKf = extractRawKeyframes(child);
          if (rawKf.isNotEmpty) {
            final nums = Float64List.fromList([
              for (final r in rawKf)
                SvgCssParser.parseNumberOrPercent(r) ?? 0.0,
            ]);
            final timing = parseSmilTiming(
              child,
              nums.length,
              numericValues: nums,
            );
            if (timing != null) {
              tracks.add(
                SvgScalarAnimationTrack(
                  timing: timing,
                  target: grad,
                  property: scalarTarget,
                  keyframes: nums,
                ),
              );
              grad.isAnimated = true;
              animatedGradientsSet.add(grad);
            }
          }
        }
      } else if (child.name == 'animateTransform') {
        final track = buildSmilTransformTrack(
          animXml: child,
          targetGradient: grad,
        );
        if (track != null) {
          tracks.add(track);
          grad.isAnimated = true;
          animatedGradientsSet.add(grad);
        }
      }
    }
  }

  SvgScalarTarget? _mapGradientScalarTarget(String attr) {
    switch (attr) {
      case 'x1':
        return SvgScalarTarget.x1;
      case 'y1':
        return SvgScalarTarget.y1;
      case 'x2':
        return SvgScalarTarget.x2;
      case 'y2':
        return SvgScalarTarget.y2;
      case 'cx':
        return SvgScalarTarget.cx;
      case 'cy':
        return SvgScalarTarget.cy;
      case 'r':
        return SvgScalarTarget.r;
      case 'fx':
        return SvgScalarTarget.fx;
      case 'fy':
        return SvgScalarTarget.fy;
      default:
        return null;
    }
  }

  void compileSmilAnimateOnElement(SvgElement element, SvgXmlElement animXml) {
    final attrName = animXml.attr('attributeName')?.trim() ?? '';
    if (attrName.isEmpty) return;

    final rawKeyframes = extractRawKeyframes(
      animXml,
      fallbackFrom: _defaultElementAttrValue(element, attrName),
    );
    if (rawKeyframes.isEmpty) return;

    // 1. Path Morphing (`attributeName="d"`)
    if (attrName == 'd' && element is SvgPathNode) {
      final parsedPaths = <PrecompiledSvgPath>[];
      for (final raw in rawKeyframes) {
        parsedPaths.add(SvgPathParser.parse(raw));
      }
      final refPath = parsedPaths.first;
      bool allIsomorphic = refPath.isIsomorphicWith(element.precompiledPath);
      if (allIsomorphic) {
        for (int i = 1; i < parsedPaths.length; i++) {
          if (!parsedPaths[i].isIsomorphicWith(refPath)) {
            allIsomorphic = false;
            break;
          }
        }
      }
      if (!allIsomorphic) return;

      final timing = parseSmilTiming(animXml, parsedPaths.length);
      if (timing == null) return;

      tracks.add(
        SvgPathMorphAnimationTrack(
          timing: timing,
          target: element,
          keyframeCoords: [for (final p in parsedPaths) p.coords],
        ),
      );
      element.hasSelfAnimation = true;
      animatedElementsSet.add(element);
      return;
    }

    // 2. Color attributes (`fill`, `stroke`)
    if (attrName == 'fill' || attrName == 'stroke') {
      final colors = <ui.Color>[
        for (final raw in rawKeyframes)
          SvgCssParser.parseColor(raw) ?? const ui.Color(0xFF000000),
      ];
      final timing = parseSmilTiming(animXml, colors.length);
      if (timing == null) return;
      tracks.add(
        SvgColorAnimationTrack(
          timing: timing,
          target: element,
          property: attrName == 'fill'
              ? SvgColorTarget.fill
              : SvgColorTarget.stroke,
          keyframes: colors,
        ),
      );
      element.hasSelfAnimation = true;
      animatedElementsSet.add(element);
      return;
    }

    // 3. `stroke-dasharray`
    if (attrName == 'stroke-dasharray') {
      final rawLists = <Float64List>[
        for (final raw in rawKeyframes) SvgCssParser.parseNumberList(raw),
      ];
      final normalized = SvgCssParser.normalizeDashArrayKeyframes(rawLists);
      if (normalized.isEmpty) return;
      final timing = parseSmilTiming(animXml, normalized.length);
      if (timing == null) return;
      if (element is SvgGeometryNode) {
        element.needsPathMetrics = true;
      }
      tracks.add(
        SvgDashArrayAnimationTrack(
          timing: timing,
          target: element,
          keyframes: normalized,
        ),
      );
      element.hasSelfAnimation = true;
      animatedElementsSet.add(element);
      return;
    }

    // 4. Scalar numeric attributes
    final scalarTarget = _mapElementScalarTarget(attrName);
    if (scalarTarget != null) {
      final nums = Float64List.fromList([
        for (final raw in rawKeyframes)
          (attrName.contains('opacity')
                  ? SvgCssParser.parseNumberOrPercent(raw)
                  : SvgCssParser.parseLength(raw)) ??
              0.0,
      ]);
      final timing = parseSmilTiming(animXml, nums.length, numericValues: nums);
      if (timing == null) return;
      if (scalarTarget == SvgScalarTarget.strokeDashoffset &&
          element is SvgGeometryNode) {
        element.needsPathMetrics = true;
      }
      tracks.add(
        SvgScalarAnimationTrack(
          timing: timing,
          target: element,
          property: scalarTarget,
          keyframes: nums,
        ),
      );
      element.hasSelfAnimation = true;
      animatedElementsSet.add(element);
    }
  }

  SvgScalarTarget? _mapElementScalarTarget(String attr) {
    switch (attr) {
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
      case 'x1':
        return SvgScalarTarget.x1;
      case 'y1':
        return SvgScalarTarget.y1;
      case 'x2':
        return SvgScalarTarget.x2;
      case 'y2':
        return SvgScalarTarget.y2;
      default:
        return null;
    }
  }

  String? _defaultElementAttrValue(SvgElement element, String attr) {
    switch (attr) {
      case 'opacity':
        return '${element.style.currentOpacity}';
      case 'fill-opacity':
        return '${element.style.currentFillOpacity}';
      case 'stroke-opacity':
        return '${element.style.currentStrokeOpacity}';
      case 'stroke-width':
        return '${element.style.currentStrokeWidth}';
      case 'stroke-dashoffset':
        return '${element.style.currentStrokeDashoffset}';
      case 'x':
        if (element is SvgRectNode) return '${element.baseX}';
        if (element is SvgUseNode) return '${element.baseX}';
        return '0';
      case 'y':
        if (element is SvgRectNode) return '${element.baseY}';
        if (element is SvgUseNode) return '${element.baseY}';
        return '0';
      case 'width':
        if (element is SvgRectNode) return '${element.baseWidth}';
        return '0';
      case 'height':
        if (element is SvgRectNode) return '${element.baseHeight}';
        return '0';
      case 'rx':
        if (element is SvgRectNode) return '${element.baseRx}';
        if (element is SvgEllipseNode) return '${element.baseRx}';
        return '0';
      case 'ry':
        if (element is SvgRectNode) return '${element.baseRy}';
        if (element is SvgEllipseNode) return '${element.baseRy}';
        return '0';
      case 'cx':
        if (element is SvgCircleNode) return '${element.baseCx}';
        if (element is SvgEllipseNode) return '${element.baseCx}';
        return '0';
      case 'cy':
        if (element is SvgCircleNode) return '${element.baseCy}';
        if (element is SvgEllipseNode) return '${element.baseCy}';
        return '0';
      case 'r':
        if (element is SvgCircleNode) return '${element.baseR}';
        return '0';
      case 'x1':
        if (element is SvgLineNode) return '${element.baseX1}';
        return '0';
      case 'y1':
        if (element is SvgLineNode) return '${element.baseY1}';
        return '0';
      case 'x2':
        if (element is SvgLineNode) return '${element.baseX2}';
        return '0';
      case 'y2':
        if (element is SvgLineNode) return '${element.baseY2}';
        return '0';
      case 'fill':
        final c = element.style.currentFillColor;
        return '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      case 'stroke':
        final c = element.style.currentStrokeColor;
        return '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      case 'd':
        if (element is SvgPathNode) {
          return element.xmlBaseD;
        }
        return null;
      default:
        return null;
    }
  }

  void compileSmilAnimateTransformOnElement(
    SvgElement element,
    SvgXmlElement animXml,
  ) {
    final track = buildSmilTransformTrack(
      animXml: animXml,
      targetElement: element,
    );
    if (track != null) {
      tracks.add(track);
      element.hasSelfAnimation = true;
      animatedElementsSet.add(element);
    }
  }

  SvgTransformAnimationTrack? buildSmilTransformTrack({
    required SvgXmlElement animXml,
    SvgElement? targetElement,
    SvgGradientNode? targetGradient,
  }) {
    final typeStr = (animXml.attr('type') ?? 'translate').trim();
    SvgTransformType transformType;
    switch (typeStr) {
      case 'translate':
        transformType = SvgTransformType.translate;
      case 'scale':
        transformType = SvgTransformType.scale;
      case 'rotate':
        transformType = SvgTransformType.rotate;
      case 'skewX':
        transformType = SvgTransformType.skewX;
      case 'skewY':
        transformType = SvgTransformType.skewY;
      case 'rotateX':
        transformType = SvgTransformType.rotateX;
      case 'rotateY':
        transformType = SvgTransformType.rotateY;
      case 'rotateZ':
        transformType = SvgTransformType.rotateZ;
      default:
        return null;
    }

    final rawKeyframes = extractRawKeyframes(
      animXml,
      fallbackFrom: transformType == SvgTransformType.scale ? '1 1' : '0 0 0',
    );
    if (rawKeyframes.isEmpty) return null;

    final flatValues = Float64List(rawKeyframes.length * 3);
    bool hasExplicitRotateAnchor = false;
    final distances = Float64List(rawKeyframes.length);

    for (int i = 0; i < rawKeyframes.length; i++) {
      final nums = SvgCssParser.parseNumberList(rawKeyframes[i]);
      final baseIdx = i * 3;
      switch (transformType) {
        case SvgTransformType.translate:
          flatValues[baseIdx] = nums.isNotEmpty ? nums[0] : 0.0;
          flatValues[baseIdx + 1] = nums.length > 1 ? nums[1] : 0.0;
          flatValues[baseIdx + 2] = 0.0;
        case SvgTransformType.scale:
          final sx = nums.isNotEmpty ? nums[0] : 1.0;
          final sy = nums.length > 1 ? nums[1] : sx;
          flatValues[baseIdx] = sx;
          flatValues[baseIdx + 1] = sy;
          flatValues[baseIdx + 2] = 0.0;
        case SvgTransformType.rotate:
          flatValues[baseIdx] = nums.isNotEmpty ? nums[0] : 0.0;
          if (nums.length >= 3) {
            hasExplicitRotateAnchor = true;
            flatValues[baseIdx + 1] = nums[1];
            flatValues[baseIdx + 2] = nums[2];
          } else {
            flatValues[baseIdx + 1] = 0.0;
            flatValues[baseIdx + 2] = 0.0;
          }
        case SvgTransformType.skewX:
        case SvgTransformType.skewY:
        case SvgTransformType.rotateX:
        case SvgTransformType.rotateY:
        case SvgTransformType.rotateZ:
        case SvgTransformType.perspective:
        case SvgTransformType.matrix:
          flatValues[baseIdx] = nums.isNotEmpty ? nums[0] : 0.0;
          flatValues[baseIdx + 1] = 0.0;
          flatValues[baseIdx + 2] = 0.0;
      }

      if (i > 0) {
        final prevIdx = (i - 1) * 3;
        final dx = flatValues[baseIdx] - flatValues[prevIdx];
        final dy = flatValues[baseIdx + 1] - flatValues[prevIdx + 1];
        distances[i] = distances[i - 1] + math.sqrt(dx * dx + dy * dy);
      }
    }

    final timing = parseSmilTiming(
      animXml,
      rawKeyframes.length,
      numericValues: distances,
    );
    if (timing == null) return null;

    return SvgTransformAnimationTrack(
      timing: timing,
      targetElement: targetElement,
      targetGradient: targetGradient,
      transformType: transformType,
      keyframeValues: flatValues,
      documentViewBox: viewBox,
      hasExplicitRotateAnchor: hasExplicitRotateAnchor,
    );
  }

  void deferSmilAnimateMotionOnElement(
    SvgElement element,
    SvgXmlElement animXml,
  ) {
    final kpList = SvgCssParser.parseNumberList(animXml.attr('keyPoints'));
    final rawKeyframes = extractRawKeyframes(animXml);
    final keyframeCount = kpList.length >= 2
        ? kpList.length
        : (rawKeyframes.length >= 2 ? rawKeyframes.length : 2);
    final timing = parseSmilTiming(animXml, keyframeCount);
    if (timing == null) return;

    pendingMotions.add(
      SvgPendingMotionTrack(target: element, xmlNode: animXml, timing: timing),
    );
  }

  void resolvePendingMotions({
    required Map<String, SvgElement> elementsById,
    required Map<String, SvgElement> defsById,
    required Map<String, SvgGradientNode> gradientsById,
    required Map<String, SvgClipPathNode> clipPathsById,
    required Map<String, SvgGeometryNode> geometryById,
  }) {
    for (final pending in pendingMotions) {
      final track = _compilePendingMotionTrack(
        pending,
        elementsById: elementsById,
        defsById: defsById,
        gradientsById: gradientsById,
        clipPathsById: clipPathsById,
        geometryById: geometryById,
      );
      if (track != null) {
        tracks.add(track);
        pending.target.hasMotionAnimation = true;
        pending.target.hasSelfAnimation = true;
        animatedElementsSet.add(pending.target);
      }
    }
  }

  SvgMotionAnimationTrack? _compilePendingMotionTrack(
    SvgPendingMotionTrack pending, {
    required Map<String, SvgElement> elementsById,
    required Map<String, SvgElement> defsById,
    required Map<String, SvgGradientNode> gradientsById,
    required Map<String, SvgClipPathNode> clipPathsById,
    required Map<String, SvgGeometryNode> geometryById,
  }) {
    final xml = pending.xmlNode;
    ui.Path? motionPath;
    List<ui.PathMetric>? existingMetrics;

    // 1. Check <mpath href="#..." /> child first
    for (final child in xml.children) {
      if (child.name == 'mpath') {
        final targetId = child.hrefId;
        if (targetId != null) {
          final geom = geometryById[targetId];
          if (geom != null) {
            geom.needsPathMetrics = true;
            if (geom.cachedMetrics == null) {
              geom.initializeGeometry(
                SvgDocument(
                  viewBox: viewBox,
                  rootGroup: SvgGroupNode(style: SvgStyle()),
                  elementsById: elementsById,
                  defsById: defsById,
                  gradientsById: gradientsById,
                  clipPathsById: clipPathsById,
                  geometryById: geometryById,
                ),
              );
            }
            motionPath = geom.basePath;
            existingMetrics = geom.cachedMetrics;
          }
        }
        break;
      }
    }

    // 2. Otherwise check inline `path="..."` attribute
    if (motionPath == null) {
      final pathAttr = xml.attr('path');
      if (pathAttr != null && pathAttr.isNotEmpty) {
        final precompiled = SvgPathParser.parse(pathAttr);
        final p = ui.Path();
        precompiled.buildUiPath(p);
        motionPath = p;
      }
    }

    // 3. Fallback to `values` / `from` / `to` coordinate pairs
    if (motionPath == null) {
      final rawPts = extractRawKeyframes(xml, fallbackFrom: '0,0');
      if (rawPts.length >= 2) {
        final p = ui.Path();
        for (int i = 0; i < rawPts.length; i++) {
          final coords = SvgCssParser.parseNumberList(rawPts[i]);
          final x = coords.isNotEmpty ? coords[0] : 0.0;
          final y = coords.length > 1 ? coords[1] : 0.0;
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        motionPath = p;
      }
    }

    if (motionPath == null) return null;

    final rotateStr = (xml.attr('rotate') ?? '0').trim().toLowerCase();
    SvgMotionRotateMode rotateMode = SvgMotionRotateMode.fixedAngle;
    double fixedAngleDeg = 0.0;
    if (rotateStr == 'auto') {
      rotateMode = SvgMotionRotateMode.auto;
    } else if (rotateStr == 'auto-reverse') {
      rotateMode = SvgMotionRotateMode.autoReverse;
    } else {
      fixedAngleDeg = SvgCssParser.parseAngleOrLength(rotateStr) ?? 0.0;
    }

    final keyPoints = SvgCssParser.parseNumberList(xml.attr('keyPoints'));

    return SvgMotionAnimationTrack.fromPath(
      timing: pending.timing,
      target: pending.target,
      motionPath: motionPath,
      existingMetrics: existingMetrics,
      rotateMode: rotateMode,
      fixedAngleDeg: fixedAngleDeg,
      keyPoints: keyPoints.isNotEmpty ? keyPoints : null,
    );
  }

  List<String> extractRawKeyframes(
    SvgXmlElement animXml, {
    String? fallbackFrom,
  }) {
    final valuesAttr = animXml.attr('values');
    if (valuesAttr != null && valuesAttr.trim().isNotEmpty) {
      return valuesAttr
          .split(';')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final fromAttr = animXml.attr('from') ?? fallbackFrom;
    final toAttr = animXml.attr('to');
    final byAttr = animXml.attr('by');

    if (fromAttr != null && toAttr != null) {
      return [fromAttr.trim(), toAttr.trim()];
    }
    if (fromAttr != null && byAttr != null) {
      final fromNums = SvgCssParser.parseNumberList(fromAttr);
      final byNums = SvgCssParser.parseNumberList(byAttr);
      if (fromNums.isNotEmpty && fromNums.length == byNums.length) {
        final sumStr = [
          for (int i = 0; i < fromNums.length; i++)
            '${fromNums[i] + byNums[i]}',
        ].join(' ');
        return [fromAttr.trim(), sumStr];
      }
    }
    if (toAttr != null) {
      return [toAttr.trim()];
    }
    return const [];
  }

  SvgAnimationTiming? parseSmilTiming(
    SvgXmlElement animXml,
    int keyframeCount, {
    Float64List? numericValues,
  }) {
    final durUs = SvgCssParser.parseClockMicroseconds(animXml.attr('dur'));
    if (durUs == null || durUs <= 0) return null;

    // Parse semicolon-separated `begin` offsets (default `[0]`)
    final beginRaw = animXml.attr('begin');
    final beginList = <int>[];
    if (beginRaw != null && beginRaw.trim().isNotEmpty) {
      final parts = beginRaw.split(';');
      for (final p in parts) {
        final us = SvgCssParser.parseClockMicroseconds(p);
        if (us != null) beginList.add(us);
      }
    }
    if (beginList.isEmpty) beginList.add(0);

    final endUs = SvgCssParser.parseClockMicroseconds(animXml.attr('end'));

    final repeatRaw = (animXml.attr('repeatCount') ?? '1').trim().toLowerCase();
    final repeatCount = (repeatRaw == 'indefinite' || repeatRaw == 'infinite')
        ? double.infinity
        : (double.tryParse(repeatRaw) ?? 1.0);

    final fillRaw = (animXml.attr('fill') ?? 'remove').trim().toLowerCase();
    final fillMode = fillRaw == 'freeze'
        ? SvgAnimationFillMode.freeze
        : SvgAnimationFillMode.remove;

    final additiveRaw = (animXml.attr('additive') ?? 'replace')
        .trim()
        .toLowerCase();
    final additiveMode = additiveRaw == 'sum'
        ? SvgAdditiveMode.sum
        : SvgAdditiveMode.replace;

    final calcRaw = (animXml.attr('calcMode') ?? 'linear').trim().toLowerCase();
    SvgCalcMode calcMode;
    switch (calcRaw) {
      case 'spline':
        calcMode = SvgCalcMode.spline;
      case 'discrete':
        calcMode = SvgCalcMode.discrete;
      case 'paced':
        calcMode = SvgCalcMode.paced;
      default:
        calcMode = SvgCalcMode.linear;
    }

    // Build keyTimes
    Float64List keyTimes;
    final keyTimesAttr = animXml.attr('keyTimes');
    if (calcMode == SvgCalcMode.paced &&
        numericValues != null &&
        numericValues.length == keyframeCount &&
        keyframeCount >= 2) {
      final cumDist = Float64List(keyframeCount);
      double totalDist = 0.0;
      for (int i = 1; i < keyframeCount; i++) {
        totalDist += (numericValues[i] - numericValues[i - 1]).abs();
        cumDist[i] = totalDist;
      }
      if (totalDist > 1e-9) {
        for (int i = 1; i < keyframeCount; i++) {
          cumDist[i] /= totalDist;
        }
        keyTimes = cumDist;
      } else {
        keyTimes = _uniformKeyTimes(keyframeCount);
      }
    } else if (keyTimesAttr != null && keyTimesAttr.trim().isNotEmpty) {
      final parsedKt = SvgCssParser.parseNumberList(
        keyTimesAttr.replaceAll(';', ' '),
      );
      if (parsedKt.length == keyframeCount) {
        keyTimes = parsedKt;
      } else {
        keyTimes = _uniformKeyTimes(keyframeCount);
      }
    } else {
      keyTimes = _uniformKeyTimes(keyframeCount);
    }

    // Build keySplines using Flutter's `Cubic` class
    List<Cubic>? keySplines;
    if (calcMode == SvgCalcMode.spline) {
      final splinesAttr = animXml.attr('keySplines');
      if (splinesAttr != null && splinesAttr.trim().isNotEmpty) {
        final segments = splinesAttr
            .split(';')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final cubics = <Cubic>[];
        for (final seg in segments) {
          final coords = SvgCssParser.parseNumberList(seg);
          if (coords.length >= 4) {
            cubics.add(Cubic(coords[0], coords[1], coords[2], coords[3]));
          }
        }
        if (cubics.isNotEmpty) {
          keySplines = cubics;
        }
      }
    }

    return SvgAnimationTiming(
      beginOffsetsUs: List<int>.unmodifiable(beginList),
      durationUs: durUs,
      endUs: endUs,
      repeatCount: repeatCount,
      fillMode: fillMode,
      calcMode: calcMode,
      additiveMode: additiveMode,
      keyTimes: keyTimes,
      keySplines: keySplines,
    );
  }

  static Float64List _uniformKeyTimes(int count) {
    if (count <= 1) return Float64List.fromList([0.0]);
    final kt = Float64List(count);
    for (int i = 0; i < count; i++) {
      kt[i] = i / (count - 1);
    }
    return kt;
  }
}
