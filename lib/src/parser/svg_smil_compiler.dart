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
import 'svg_smil_syncbase.dart';
import 'svg_xml_tokenizer.dart';

/// Deferred `<animateMotion>` descriptor resolved after all `<path>` elements
/// (including `<mpath>` targets) have been registered in `geometryById`.
/// 延迟解析的 `<animateMotion>` 描述对象，待文档中全部 `<path>` 注册后再绑定 `<mpath>`。
class SvgPendingMotionTrack {
  /// Scene element driven by this `<animateMotion>` element.
  /// 受该 `<animateMotion>` 驱动的目标场景元素。
  final SvgElement target;

  /// Source XML element of `<animateMotion>`.
  /// `<animateMotion>` 对应的源 XML 元素。
  final SvgXmlElement xmlNode;

  /// Precompiled animation timing configuration.
  /// 预编译的时间轴配置。
  final SvgAnimationTiming timing;

  /// Creates an [SvgPendingMotionTrack].
  /// 创建一个 [SvgPendingMotionTrack] 实例。
  ///
  /// - [target]: Target element to move. 目标移动元素。
  /// - [xmlNode]: `<animateMotion>` XML element. `<animateMotion>` XML 节点。
  /// - [timing]: Precompiled timing configuration. 预编译时间轴配置。
  const SvgPendingMotionTrack({
    required this.target,
    required this.xmlNode,
    required this.timing,
  });
}

/// Compiles SMIL `<animate>`, `<animateColor>`, `<set>`, `<animateTransform>`,
/// and `<animateMotion>` XML elements into precompiled [SvgAnimationTrack] instances.
/// 将 SMIL 动画 XML 元素编译为预编译 [SvgAnimationTrack] 轨道的编译器。
class SvgSmilCompiler {
  /// Root SVG `viewBox` used for resolving relative transform origins.
  /// 根 SVG `viewBox`，用于解析相对 `transform-origin`。
  final ui.Rect viewBox;

  /// Output list collecting all compiled animation tracks.
  /// 收集全部已编译动画轨道的输出列表。
  final List<SvgAnimationTrack> tracks;

  /// Set of elements that have at least one attached animation track.
  /// 包含至少一条动画轨道的元素集合。
  final Set<SvgElement> animatedElementsSet;

  /// Set of gradients that have at least one attached animation track.
  /// 包含至少一条动画轨道的渐变集合。
  final Set<SvgGradientNode> animatedGradientsSet;

  /// Deferred `<animateMotion>` descriptors resolved after tree construction.
  /// 树构建完成后再解析的延迟 `<animateMotion>` 列表。
  final List<SvgPendingMotionTrack> pendingMotions = <SvgPendingMotionTrack>[];

  final SvgSmilSyncbaseResolver _syncbaseResolver = SvgSmilSyncbaseResolver();

  /// Creates an [SvgSmilCompiler].
  /// 创建一个 [SvgSmilCompiler] 实例。
  ///
  /// - [viewBox]: Root document `viewBox`. 根文档 `viewBox`。
  /// - [tracks]: Mutable list receiving compiled tracks. 接收已编译轨道的列表。
  /// - [animatedElementsSet]: Mutable set tracking animated elements. 记录动画元素的集合。
  /// - [animatedGradientsSet]: Mutable set tracking animated gradients. 记录动画渐变的集合。
  SvgSmilCompiler({
    required this.viewBox,
    required this.tracks,
    required this.animatedElementsSet,
    required this.animatedGradientsSet,
  });

  /// Compiles an `<animate>` / `<animateColor>` attached to a gradient [stop].
  /// 编译挂载在渐变色标 [stop] 上的 `<animate>` / `<animateColor>` 动画。
  ///
  /// - [stop]: Target gradient stop. 目标渐变色标。
  /// - [animXml]: Animation XML element. 动画 XML 节点。
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

  /// Compiles `<animate>` and `<animateTransform>` children attached to [grad].
  /// 编译挂载在渐变节点 [grad] 上的 `<animate>` 与 `<animateTransform>` 子动画。
  ///
  /// - [grad]: Target gradient node. 目标渐变节点。
  /// - [gradXml]: Source gradient XML element. 源渐变 XML 节点。
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
      case 'fr':
        return SvgScalarTarget.fr;
      default:
        return null;
    }
  }

  /// Compiles an `<animate>` or `<animateColor>` element targeting [element].
  /// 编译作用于 [element] 的 `<animate>` 或 `<animateColor>` 动画元素。
  ///
  /// - [element]: Target scene element. 目标场景元素。
  /// - [animXml]: Animation XML element. 动画 XML 节点。
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
      case 'font-size':
        return SvgScalarTarget.fontSize;
      case 'letter-spacing':
        return SvgScalarTarget.letterSpacing;
      case 'x':
        return SvgScalarTarget.x;
      case 'y':
        return SvgScalarTarget.y;
      case 'dx':
        return SvgScalarTarget.dx;
      case 'dy':
        return SvgScalarTarget.dy;
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
      case 'font-size':
        return '${element.style.currentFontSize}';
      case 'letter-spacing':
        return '${element.style.currentLetterSpacing ?? 0.0}';
      case 'x':
        if (element is SvgRectNode) return '${element.baseX}';
        if (element is SvgUseNode) return '${element.baseX}';
        if (element is SvgTextNode) return '${element.resolveBaseX(viewBox)}';
        return '0';
      case 'y':
        if (element is SvgRectNode) return '${element.baseY}';
        if (element is SvgUseNode) return '${element.baseY}';
        if (element is SvgTextNode) return '${element.resolveBaseY(viewBox)}';
        return '0';
      case 'dx':
      case 'dy':
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

  /// Compiles a SMIL `<set attributeName="..." to="..." />` element into a
  /// discrete animation track (supports `display`, `visibility`, `fill`, `stroke`,
  /// and all scalar numeric attributes, including omitted/indefinite `dur`).
  void compileSmilSetOnElement(SvgElement element, SvgXmlElement setXml) {
    final attrName = setXml.attr('attributeName')?.trim() ?? '';
    final toRaw = setXml.attr('to')?.trim();
    if (attrName.isEmpty || toRaw == null || toRaw.isEmpty) return;

    final timing = _parseSetTiming(setXml);
    if (timing == null) return;

    if (attrName == 'visibility') {
      final lower = toRaw.toLowerCase();
      final isHidden = lower == 'hidden' || lower == 'collapse';
      tracks.add(
        SvgSetAnimationTrack.boolean(
          timing: timing,
          target: element,
          kind: SvgSetTargetKind.visibilityHidden,
          boolValue: isHidden,
        ),
      );
      element.hasSelfAnimation = true;
      animatedElementsSet.add(element);
      return;
    }

    if (attrName == 'display') {
      final isNone = toRaw.toLowerCase() == 'none';
      tracks.add(
        SvgSetAnimationTrack.boolean(
          timing: timing,
          target: element,
          kind: SvgSetTargetKind.displayNone,
          boolValue: isNone,
        ),
      );
      element.hasSelfAnimation = true;
      animatedElementsSet.add(element);
      return;
    }

    if (attrName == 'fill' || attrName == 'stroke') {
      final paint = SvgCssParser.parsePaintServer(toRaw);
      if (paint == null) return;
      tracks.add(
        SvgSetAnimationTrack.paint(
          timing: timing,
          target: element,
          kind: attrName == 'fill'
              ? SvgSetTargetKind.fillPaint
              : SvgSetTargetKind.strokePaint,
          paintValue: paint,
        ),
      );
      element.hasSelfAnimation = true;
      animatedElementsSet.add(element);
      return;
    }

    final scalarTarget = _mapElementScalarTarget(attrName);
    if (scalarTarget != null) {
      final numVal =
          (attrName.contains('opacity')
              ? SvgCssParser.parseNumberOrPercent(toRaw)
              : SvgCssParser.parseLength(toRaw)) ??
          0.0;
      if (scalarTarget == SvgScalarTarget.strokeDashoffset &&
          element is SvgGeometryNode) {
        element.needsPathMetrics = true;
      }
      tracks.add(
        SvgScalarAnimationTrack(
          timing: timing,
          target: element,
          property: scalarTarget,
          keyframes: Float64List.fromList([numVal]),
        ),
      );
      element.hasSelfAnimation = true;
      animatedElementsSet.add(element);
    }
  }

  SvgAnimationTiming? _parseSetTiming(SvgXmlElement setXml) {
    final rawDur = setXml.attr('dur')?.trim().toLowerCase();
    final isIndefiniteDur =
        rawDur == null || rawDur.isEmpty || rawDur == 'indefinite';
    final durUs = isIndefiniteDur
        ? 1000000
        : SvgCssParser.parseClockMicroseconds(rawDur);
    if (durUs == null || durUs <= 0) return null;

    final (beginList, syncRefs) = _parseBeginAttribute(setXml.attr('begin'));

    final endUs = SvgCssParser.parseClockMicroseconds(setXml.attr('end'));
    final fillRaw = (setXml.attr('fill') ?? 'remove').trim().toLowerCase();
    final fillMode = fillRaw == 'freeze'
        ? SvgAnimationFillMode.freeze
        : SvgAnimationFillMode.remove;

    final timing = SvgAnimationTiming(
      beginOffsetsUs: beginList,
      durationUs: durUs,
      endUs: endUs,
      repeatCount: isIndefiniteDur ? double.infinity : 1.0,
      fillMode: fillMode,
      calcMode: SvgCalcMode.discrete,
      additiveMode: SvgAdditiveMode.replace,
      keyTimes: Float64List.fromList([0.0]),
    );
    _syncbaseResolver.registerTiming(setXml.attr('id'), timing);
    _syncbaseResolver.addPendingRefs(timing, syncRefs);
    return timing;
  }

  /// Compiles an `<animateTransform>` child element targeting [element].
  /// 编译作用于 [element] 的 `<animateTransform>` 变换动画。
  ///
  /// - [element]: Target scene element. 目标场景元素。
  /// - [animXml]: `<animateTransform>` XML node. `<animateTransform>` XML 节点。
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

  /// Builds an [SvgTransformAnimationTrack] for either [targetElement] or [targetGradient].
  /// 为元素 [targetElement] 或渐变 [targetGradient] 构建 [SvgTransformAnimationTrack] 轨道。
  ///
  /// - [animXml]: `<animateTransform>` XML node. `<animateTransform>` XML 节点。
  /// - [targetElement]: Optional target element. 可选目标元素。
  /// - [targetGradient]: Optional target gradient. 可选目标渐变。
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

  /// Queues an `<animateMotion>` element on [element] for deferred resolution.
  /// 将 [element] 上的 `<animateMotion>` 加入延迟解析队列，待全部 `<path>` 就绪后绑定。
  ///
  /// - [element]: Target element to move. 目标运动元素。
  /// - [animXml]: `<animateMotion>` XML node. `<animateMotion>` XML 节点。
  void deferSmilAnimateMotionOnElement(
    SvgElement element,
    SvgXmlElement animXml,
  ) {
    final kpList = SvgCssParser.parseNumberList(
      animXml.attr('keyPoints')?.replaceAll(';', ' '),
    );
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

  /// Resolves all queued `<animateMotion>` tracks once document geometry IDs exist.
  /// 在文档几何节点 ID 表构建完成后，解析全部延迟 `<animateMotion>` 轨道。
  ///
  /// - [elementsById]: Global elements map by `id`. 全局元素 ID 映射表。
  /// - [defsById]: `<defs>` elements map by `id`. `<defs>` 定义映射表。
  /// - [gradientsById]: Gradients map by `id`. 渐变映射表。
  /// - [clipPathsById]: Clip paths map by `id`. 裁剪路径映射表。
  /// - [geometryById]: Geometry nodes map by `id` for `<mpath>` lookup. 几何节点映射表。
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

  /// Resolves all SMIL syncbase `begin` references (e.g. `anim1.end+0.5s`).
  void resolveSyncbaseTimings() {
    _syncbaseResolver.resolveAll();
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

    final keyPoints = SvgCssParser.parseNumberList(
      xml.attr('keyPoints')?.replaceAll(';', ' '),
    );

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

  /// Extracts raw keyframe string values from `values`, `from`/`to`, or `from`/`by`.
  /// 从 `values`、`from`/`to` 或 `from`/`by` 属性中提取原始关键帧字符串列表。
  ///
  /// - [animXml]: Animation XML element. 动画 XML 节点。
  /// - [fallbackFrom]: Optional fallback start value when `from` is omitted. 省略 `from` 时的回退初值。
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

  /// Parses SMIL timing attributes (`dur`, `begin`, `end`, `repeatCount`, `fill`,
  /// `additive`, `accumulate`, `calcMode`, `keyTimes`, `keySplines`) into [SvgAnimationTiming].
  /// 解析 SMIL 时间轴与缓动属性并构建 [SvgAnimationTiming]。
  ///
  /// - [animXml]: Animation XML element. 动画 XML 节点。
  /// - [keyframeCount]: Total number of keyframes. 关键帧总数。
  /// - [numericValues]: Optional numeric keyframes used for `calcMode='paced'`.
  ///   可选数值关键帧数组，供 `calcMode='paced'` 等速插值计算距离。
  SvgAnimationTiming? parseSmilTiming(
    SvgXmlElement animXml,
    int keyframeCount, {
    Float64List? numericValues,
  }) {
    final durUs = SvgCssParser.parseClockMicroseconds(animXml.attr('dur'));
    if (durUs == null || durUs <= 0) return null;

    // Parse semicolon-separated `begin` offsets & SMIL syncbase references
    final (beginList, syncRefs) = _parseBeginAttribute(animXml.attr('begin'));

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

    final accumulateRaw = (animXml.attr('accumulate') ?? 'none')
        .trim()
        .toLowerCase();
    final accumulateSum = accumulateRaw == 'sum';

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

    final timing = SvgAnimationTiming(
      beginOffsetsUs: beginList,
      durationUs: durUs,
      endUs: endUs,
      repeatCount: repeatCount,
      fillMode: fillMode,
      calcMode: calcMode,
      additiveMode: additiveMode,
      accumulateSum: accumulateSum,
      keyTimes: keyTimes,
      keySplines: keySplines,
    );
    _syncbaseResolver.registerTiming(animXml.attr('id'), timing);
    _syncbaseResolver.addPendingRefs(timing, syncRefs);
    return timing;
  }

  static (List<int>, List<SvgSmilSyncbaseRef>) _parseBeginAttribute(
    String? beginRaw,
  ) {
    final beginList = <int>[];
    final syncRefs = <SvgSmilSyncbaseRef>[];
    if (beginRaw != null && beginRaw.trim().isNotEmpty) {
      for (final p in beginRaw.split(';')) {
        final token = p.trim();
        if (token.isEmpty) continue;
        final syncRef = SvgSmilSyncbaseRef.parse(token);
        if (syncRef != null) {
          syncRefs.add(syncRef);
        } else {
          final us = SvgCssParser.parseClockMicroseconds(token);
          if (us != null) beginList.add(us);
        }
      }
    }
    if (beginList.isEmpty && syncRefs.isEmpty) {
      beginList.add(0);
    }
    return (beginList, syncRefs);
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
