import 'dart:math' as math;
import 'dart:ui' as ui;

import '../animation/svg_timeline.dart';
import '../model/svg_gradient.dart';
import '../model/svg_node.dart';
import '../model/svg_style.dart';
import 'svg_css_parser.dart';
import 'svg_path_parser.dart';
import 'svg_smil_compiler.dart';
import 'svg_xml_tokenizer.dart';

export 'svg_smil_compiler.dart';
export 'svg_xml_tokenizer.dart';

/// Complete compiled output from [SvgParser] containing the [SvgDocument] scene
/// graph and its [SvgTimelineEngine].
class CompiledSvgScene {
  final SvgDocument document;
  final SvgTimelineEngine timeline;

  const CompiledSvgScene({required this.document, required this.timeline});

  void dispose() {
    document.dispose();
  }
}

/// Precompiles an SVG XML string into a zero-allocation [CompiledSvgScene].
///
/// All string parsing, regex matching, hex color decoding, path `d` compilation,
/// CSS selector matching, and `@keyframes` / SMIL track building happen once here.
abstract final class SvgParser {
  static CompiledSvgScene compile(String svgXml) {
    final rootXml = SvgXmlTokenizer.parseRoot(svgXml);
    final builder = _SvgSceneCompiler(rootXml);
    return builder.build();
  }
}

class _SvgSceneCompiler {
  final SvgXmlElement rootXml;

  final Map<String, SvgElement> elementsById = <String, SvgElement>{};
  final Map<String, SvgElement> defsById = <String, SvgElement>{};
  final Map<String, SvgGradientNode> gradientsById =
      <String, SvgGradientNode>{};
  final Map<String, SvgClipPathNode> clipPathsById =
      <String, SvgClipPathNode>{};
  final Map<String, SvgGeometryNode> geometryById = <String, SvgGeometryNode>{};

  final List<SvgAnimationTrack> tracks = <SvgAnimationTrack>[];
  final Set<SvgElement> animatedElementsSet = <SvgElement>{};
  final Set<SvgGradientNode> animatedGradientsSet = <SvgGradientNode>{};

  late final ui.Rect viewBox;
  late final SvgStyleSheet styleSheet;
  late final SvgSmilCompiler _smilCompiler;

  _SvgSceneCompiler(this.rootXml);

  CompiledSvgScene build() {
    // 1. Parse root <svg> dimensions, viewBox, and preserveAspectRatio
    final rawWidth = rootXml.attr('width');
    final rawHeight = rootXml.attr('height');
    final explicitWidth = (rawWidth != null && rawWidth.trim().endsWith('%'))
        ? null
        : SvgCssParser.parseLength(rawWidth);
    final explicitHeight = (rawHeight != null && rawHeight.trim().endsWith('%'))
        ? null
        : SvgCssParser.parseLength(rawHeight);
    viewBox = _parseViewBox(
      rootXml.attr('viewBox'),
      explicitWidth,
      explicitHeight,
    );
    final width = SvgCssParser.parseNumberOrPercent(
      rawWidth,
      referenceExtent: viewBox.width,
    );
    final height = SvgCssParser.parseNumberOrPercent(
      rawHeight,
      referenceExtent: viewBox.height,
    );
    final preserveAspectRatio = _parsePreserveAspectRatio(
      rootXml.attr('preserveAspectRatio'),
    );

    _smilCompiler = SvgSmilCompiler(
      viewBox: viewBox,
      tracks: tracks,
      animatedElementsSet: animatedElementsSet,
      animatedGradientsSet: animatedGradientsSet,
    );

    // 2. Collect and precompile all <style> blocks first
    final styleBuffer = StringBuffer();
    _collectStyleBlocks(rootXml, styleBuffer);
    styleSheet = SvgCssParser.parseStyleSheet(styleBuffer.toString());

    // 3. Build root <g> scene graph and parse elements / SMIL animations
    final rootStyle = SvgStyle();
    final rootInlineCssAnims = <SvgCssAnimationConfig>[];
    _applyElementAttributesAndCss(
      xml: rootXml,
      tagName: 'svg',
      id: rootXml.attr('id'),
      classes: _parseClasses(rootXml.attr('class')),
      style: rootStyle,
      outCssAnimations: rootInlineCssAnims,
    );
    rootStyle.resolveInheritance(null);

    final rootGroup = SvgGroupNode(
      tagName: 'svg',
      id: rootXml.attr('id'),
      classes: _parseClasses(rootXml.attr('class')),
      style: rootStyle,
      baseTransformOps: SvgCssParser.parseTransformOps(
        rootXml.attr('transform') ?? '',
      ),
    );

    _buildChildren(
      parentXml: rootXml,
      parentGroup: rootGroup,
      insideDefs: false,
    );

    // 4. Create and initialize SvgDocument (computing bounds, PathMetrics, and base transforms)
    final document = SvgDocument(
      width: width,
      height: height,
      viewBox: viewBox,
      preserveAspectRatio: preserveAspectRatio,
      rootGroup: rootGroup,
      elementsById: elementsById,
      defsById: defsById,
      gradientsById: gradientsById,
      clipPathsById: clipPathsById,
      geometryById: geometryById,
    );

    // Resolve deferred <animateMotion> tracks now that all <path> nodes and <defs> exist
    _smilCompiler.resolvePendingMotions(
      elementsById: elementsById,
      defsById: defsById,
      gradientsById: gradientsById,
      clipPathsById: clipPathsById,
      geometryById: geometryById,
    );

    document.initialize();

    // 5. Compute timeline cycleDuration and finiteDuration
    bool hasInfinite = false;
    int maxFiniteUs = 0;
    int maxCycleUs = 0;

    for (final track in tracks) {
      final t = track.timing;
      int earliestBegin = 0;
      if (t.beginOffsetsUs.isNotEmpty) {
        earliestBegin = t.beginOffsetsUs[0];
        for (int i = 1; i < t.beginOffsetsUs.length; i++) {
          if (t.beginOffsetsUs[i] > earliestBegin) {
            earliestBegin = t.beginOffsetsUs[i];
          }
        }
      }
      final cycleEnd = math.max(0, earliestBegin) + t.durationUs;
      if (cycleEnd > maxCycleUs) {
        maxCycleUs = cycleEnd;
      }
      if (t.repeatCount.isInfinite) {
        hasInfinite = true;
      } else {
        final totalEnd =
            math.max(0, earliestBegin) + (t.durationUs * t.repeatCount).round();
        if (totalEnd > maxFiniteUs) {
          maxFiniteUs = totalEnd;
        }
      }
    }

    final cycleDuration = Duration(
      microseconds: maxCycleUs > 0 ? maxCycleUs : 1000000,
    );
    final finiteDuration = hasInfinite
        ? null
        : Duration(microseconds: maxFiniteUs);

    final timeline = SvgTimelineEngine(
      animatedElements: animatedElementsSet.toList(growable: false),
      animatedGradients: animatedGradientsSet.toList(growable: false),
      tracks: tracks,
      finiteDuration: finiteDuration,
      cycleDuration: cycleDuration,
    );

    // Apply initial frame (t = 0) so initial backwards-fill / t=0 states are active immediately
    timeline.seekMicroseconds(0);

    return CompiledSvgScene(document: document, timeline: timeline);
  }

  void _collectStyleBlocks(SvgXmlElement node, StringBuffer out) {
    if (node.name == 'style' && node.textContent.isNotEmpty) {
      out.writeln(node.textContent);
    }
    for (final child in node.children) {
      _collectStyleBlocks(child, out);
    }
  }

  void _buildChildren({
    required SvgXmlElement parentXml,
    required SvgGroupNode parentGroup,
    required bool insideDefs,
  }) {
    for (final childXml in parentXml.children) {
      final tag = childXml.name;
      switch (tag) {
        case 'style':
        case 'title':
        case 'desc':
        case 'metadata':
          continue;

        case 'defs':
          final defsNode = SvgDefsNode(
            id: childXml.attr('id'),
            style: SvgStyle()..resolveInheritance(parentGroup.style),
          );
          _buildChildren(
            parentXml: childXml,
            parentGroup: defsNode,
            insideDefs: true,
          );
          parentGroup.children.add(defsNode);

        case 'linearGradient':
          final grad = _buildLinearGradient(childXml);
          gradientsById[grad.id] = grad;

        case 'radialGradient':
          final grad = _buildRadialGradient(childXml);
          gradientsById[grad.id] = grad;

        case 'clipPath':
          final clip = _buildClipPath(childXml, parentGroup.style);
          if (clip.id != null) {
            clipPathsById[clip.id!] = clip;
          }

        case 'animate':
          _smilCompiler.compileSmilAnimateOnElement(parentGroup, childXml);

        case 'animateTransform':
          _smilCompiler.compileSmilAnimateTransformOnElement(
            parentGroup,
            childXml,
          );

        case 'animateMotion':
          _smilCompiler.deferSmilAnimateMotionOnElement(parentGroup, childXml);

        default:
          final elem = _buildElementNode(
            xml: childXml,
            parentElement: parentGroup,
            insideDefs: insideDefs,
          );
          if (elem != null) {
            elem.parent = parentGroup;
            parentGroup.children.add(elem);
            if (elem.id != null && elem.id!.isNotEmpty) {
              elementsById[elem.id!] = elem;
              if (insideDefs) {
                defsById[elem.id!] = elem;
              }
              if (elem is SvgGeometryNode) {
                geometryById[elem.id!] = elem;
              }
            }
          }
      }
    }
  }

  SvgElement? _buildElementNode({
    required SvgXmlElement xml,
    required SvgElement parentElement,
    required bool insideDefs,
  }) {
    final tag = xml.name;
    final id = xml.attr('id');
    final classes = _parseClasses(xml.attr('class'));
    final style = SvgStyle();
    final cssAnims = <SvgCssAnimationConfig>[];

    _applyElementAttributesAndCss(
      xml: xml,
      tagName: tag,
      id: id,
      classes: classes,
      style: style,
      outCssAnimations: cssAnims,
    );
    style.resolveInheritance(parentElement.style);

    final baseTransformOps = SvgCssParser.parseTransformOps(
      xml.attr('transform') ?? '',
    );

    SvgElement? node;

    switch (tag) {
      case 'g':
      case 'svg':
      case 'symbol':
        final group = SvgGroupNode(
          tagName: tag,
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
        );
        _buildChildren(
          parentXml: xml,
          parentGroup: group,
          insideDefs: insideDefs || tag == 'symbol',
        );
        node = group;

      case 'use':
        node = SvgUseNode(
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          hrefId: xml.hrefId,
          baseX:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('x'),
                referenceExtent: viewBox.width,
              ) ??
              0.0,
          baseY:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('y'),
                referenceExtent: viewBox.height,
              ) ??
              0.0,
        );

      case 'path':
        final d = xml.attr('d') ?? '';
        final precompiled = SvgPathParser.parse(d);
        node = SvgPathNode(
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          precompiledPath: precompiled,
          xmlBaseD: d,
        );

      case 'rect':
        node = SvgRectNode(
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          baseX:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('x'),
                referenceExtent: viewBox.width,
              ) ??
              0.0,
          baseY:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('y'),
                referenceExtent: viewBox.height,
              ) ??
              0.0,
          baseWidth:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('width'),
                referenceExtent: viewBox.width,
              ) ??
              0.0,
          baseHeight:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('height'),
                referenceExtent: viewBox.height,
              ) ??
              0.0,
          baseRx:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('rx'),
                referenceExtent: viewBox.width,
              ) ??
              0.0,
          baseRy:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('ry'),
                referenceExtent: viewBox.height,
              ) ??
              0.0,
        );

      case 'circle':
        final diag = math.sqrt(
          (viewBox.width * viewBox.width + viewBox.height * viewBox.height) *
              0.5,
        );
        node = SvgCircleNode(
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          baseCx:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('cx'),
                referenceExtent: viewBox.width,
              ) ??
              0.0,
          baseCy:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('cy'),
                referenceExtent: viewBox.height,
              ) ??
              0.0,
          baseR:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('r'),
                referenceExtent: diag,
              ) ??
              0.0,
        );

      case 'ellipse':
        node = SvgEllipseNode(
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          baseCx:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('cx'),
                referenceExtent: viewBox.width,
              ) ??
              0.0,
          baseCy:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('cy'),
                referenceExtent: viewBox.height,
              ) ??
              0.0,
          baseRx:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('rx'),
                referenceExtent: viewBox.width,
              ) ??
              0.0,
          baseRy:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('ry'),
                referenceExtent: viewBox.height,
              ) ??
              0.0,
        );

      case 'line':
        node = SvgLineNode(
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          baseX1:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('x1'),
                referenceExtent: viewBox.width,
              ) ??
              0.0,
          baseY1:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('y1'),
                referenceExtent: viewBox.height,
              ) ??
              0.0,
          baseX2:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('x2'),
                referenceExtent: viewBox.width,
              ) ??
              0.0,
          baseY2:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('y2'),
                referenceExtent: viewBox.height,
              ) ??
              0.0,
        );

      case 'polyline':
      case 'polygon':
        final pts = SvgCssParser.parseNumberList(xml.attr('points'));
        node = SvgPolyNode(
          tagName: tag,
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          points: pts,
          closePath: tag == 'polygon',
        );

      default:
        return null;
    }

    // Parse SMIL animation children attached to non-group shape/use nodes
    if (node is! SvgGroupNode) {
      for (final animXml in xml.children) {
        switch (animXml.name) {
          case 'animate':
            _smilCompiler.compileSmilAnimateOnElement(node, animXml);
          case 'animateTransform':
            _smilCompiler.compileSmilAnimateTransformOnElement(node, animXml);
          case 'animateMotion':
            _smilCompiler.deferSmilAnimateMotionOnElement(node, animXml);
        }
      }
    }

    // Compile any CSS @keyframes animations bound to this element
    for (final cssAnim in cssAnims) {
      final stops = styleSheet.keyframesByName[cssAnim.name];
      if (stops != null && stops.isNotEmpty) {
        final compiledTracks = SvgCssParser.compileKeyframesForElement(
          target: node,
          config: cssAnim,
          stops: stops,
          documentViewBox: viewBox,
        );
        if (compiledTracks.isNotEmpty) {
          tracks.addAll(compiledTracks);
          node.hasSelfAnimation = true;
          animatedElementsSet.add(node);
        }
      }
    }

    return node;
  }

  void _applyElementAttributesAndCss({
    required SvgXmlElement xml,
    required String tagName,
    required String? id,
    required List<String> classes,
    required SvgStyle style,
    required List<SvgCssAnimationConfig> outCssAnimations,
  }) {
    // 1. Presentation attributes on the XML element (lowest precedence)
    xml.attributes.forEach((key, value) {
      if (key != 'style' &&
          key != 'transform' &&
          key != 'id' &&
          key != 'class') {
        SvgCssParser.applySingleAttribute(key, value, style);
      }
    });

    // 2. Matched <style> sheet rules ordered by (specificity, orderIndex)
    if (styleSheet.rules.isNotEmpty) {
      final matched = <SvgCssRule>[];
      for (final rule in styleSheet.rules) {
        final sel = rule.selector;
        bool isMatch = false;
        switch (sel.type) {
          case SvgCssSelectorType.id:
            isMatch = id != null && id == sel.name;
          case SvgCssSelectorType.className:
            isMatch = classes.contains(sel.name);
          case SvgCssSelectorType.tag:
            isMatch = tagName == sel.name;
        }
        if (isMatch) {
          matched.add(rule);
        }
      }
      matched.sort((a, b) {
        final cmp = a.selector.specificity.compareTo(b.selector.specificity);
        return cmp != 0 ? cmp : a.orderIndex.compareTo(b.orderIndex);
      });
      for (final rule in matched) {
        style.mergeFrom(rule.style);
        if (rule.animations.isNotEmpty) {
          outCssAnimations.addAll(rule.animations);
        }
      }
    }

    // 3. Inline `style="..."` attribute (highest precedence)
    final inlineStyle = xml.attr('style');
    if (inlineStyle != null && inlineStyle.isNotEmpty) {
      final declMap = SvgCssParser.parseDeclarationsMap(inlineStyle);
      SvgCssParser.applyDeclarationsToStyle(declMap, style, outCssAnimations);
    }
  }

  SvgClipPathNode _buildClipPath(SvgXmlElement xml, SvgStyle parentStyle) {
    final style = SvgStyle()..resolveInheritance(parentStyle);
    final clipNode = SvgClipPathNode(id: xml.attr('id'), style: style);
    _buildChildren(parentXml: xml, parentGroup: clipNode, insideDefs: true);
    return clipNode;
  }

  SvgLinearGradientNode _buildLinearGradient(SvgXmlElement xml) {
    final id = xml.attr('id') ?? '';
    final units = xml.attr('gradientUnits') == 'userSpaceOnUse'
        ? SvgGradientUnits.userSpaceOnUse
        : SvgGradientUnits.objectBoundingBox;
    final spread = _parseSpreadMethod(xml.attr('spreadMethod'));
    final transformOps = SvgCssParser.parseTransformOps(
      xml.attr('gradientTransform') ?? '',
    );
    final stops = _buildGradientStops(xml);

    final grad = SvgLinearGradientNode(
      id: id,
      hrefId: xml.hrefId,
      gradientUnits: units,
      spreadMethod: spread,
      stops: stops,
      baseGradientTransformOps: transformOps,
      baseX1: SvgCssParser.parseNumberOrPercent(xml.attr('x1')) ?? 0.0,
      baseY1: SvgCssParser.parseNumberOrPercent(xml.attr('y1')) ?? 0.0,
      baseX2: SvgCssParser.parseNumberOrPercent(xml.attr('x2')) ?? 1.0,
      baseY2: SvgCssParser.parseNumberOrPercent(xml.attr('y2')) ?? 0.0,
    );

    _smilCompiler.compileGradientAnimations(grad, xml);
    return grad;
  }

  SvgRadialGradientNode _buildRadialGradient(SvgXmlElement xml) {
    final id = xml.attr('id') ?? '';
    final units = xml.attr('gradientUnits') == 'userSpaceOnUse'
        ? SvgGradientUnits.userSpaceOnUse
        : SvgGradientUnits.objectBoundingBox;
    final spread = _parseSpreadMethod(xml.attr('spreadMethod'));
    final transformOps = SvgCssParser.parseTransformOps(
      xml.attr('gradientTransform') ?? '',
    );
    final stops = _buildGradientStops(xml);

    final cx = SvgCssParser.parseNumberOrPercent(xml.attr('cx')) ?? 0.5;
    final cy = SvgCssParser.parseNumberOrPercent(xml.attr('cy')) ?? 0.5;
    final r = SvgCssParser.parseNumberOrPercent(xml.attr('r')) ?? 0.5;
    final fx = SvgCssParser.parseNumberOrPercent(xml.attr('fx'));
    final fy = SvgCssParser.parseNumberOrPercent(xml.attr('fy'));

    final grad = SvgRadialGradientNode(
      id: id,
      hrefId: xml.hrefId,
      gradientUnits: units,
      spreadMethod: spread,
      stops: stops,
      baseGradientTransformOps: transformOps,
      baseCx: cx,
      baseCy: cy,
      baseR: r,
      baseFx: fx,
      baseFy: fy,
    );

    _smilCompiler.compileGradientAnimations(grad, xml);
    return grad;
  }

  List<SvgGradientStop> _buildGradientStops(SvgXmlElement gradXml) {
    final stops = <SvgGradientStop>[];
    for (final child in gradXml.children) {
      if (child.name != 'stop') continue;
      final inlineDecls = child.attr('style') != null
          ? SvgCssParser.parseDeclarationsMap(child.attr('style')!)
          : const <String, String>{};

      final offsetRaw = child.attr('offset') ?? inlineDecls['offset'] ?? '0';
      final colorRaw =
          child.attr('stop-color') ?? inlineDecls['stop-color'] ?? '#000000';
      final opacityRaw =
          child.attr('stop-opacity') ?? inlineDecls['stop-opacity'] ?? '1';

      final stop = SvgGradientStop(
        id: child.attr('id'),
        baseOffset: (SvgCssParser.parseNumberOrPercent(offsetRaw) ?? 0.0).clamp(
          0.0,
          1.0,
        ),
        baseColor:
            SvgCssParser.parseColor(colorRaw) ?? const ui.Color(0xFF000000),
        baseOpacity: (SvgCssParser.parseNumberOrPercent(opacityRaw) ?? 1.0)
            .clamp(0.0, 1.0),
      );

      for (final animXml in child.children) {
        if (animXml.name == 'animate') {
          _smilCompiler.compileStopAnimate(stop, animXml);
        }
      }
      stops.add(stop);
    }
    return stops;
  }

  static ui.Rect _parseViewBox(
    String? viewBoxAttr,
    double? width,
    double? height,
  ) {
    if (viewBoxAttr != null && viewBoxAttr.trim().isNotEmpty) {
      final nums = SvgCssParser.parseNumberList(viewBoxAttr);
      if (nums.length >= 4) {
        return ui.Rect.fromLTWH(nums[0], nums[1], nums[2], nums[3]);
      }
    }
    return ui.Rect.fromLTWH(0.0, 0.0, width ?? 100.0, height ?? 100.0);
  }

  static SvgPreserveAspectRatio _parsePreserveAspectRatio(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return SvgPreserveAspectRatio.defaultValue;
    }
    final tokens = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    SvgAspectRatioAlign align = SvgAspectRatioAlign.xMidYMid;
    SvgMeetOrSlice meetOrSlice = SvgMeetOrSlice.meet;

    for (final tok in tokens) {
      switch (tok) {
        case 'none':
          align = SvgAspectRatioAlign.none;
        case 'xMinYMin':
          align = SvgAspectRatioAlign.xMinYMin;
        case 'xMidYMin':
          align = SvgAspectRatioAlign.xMidYMin;
        case 'xMaxYMin':
          align = SvgAspectRatioAlign.xMaxYMin;
        case 'xMinYMid':
          align = SvgAspectRatioAlign.xMinYMid;
        case 'xMidYMid':
          align = SvgAspectRatioAlign.xMidYMid;
        case 'xMaxYMid':
          align = SvgAspectRatioAlign.xMaxYMid;
        case 'xMinYMax':
          align = SvgAspectRatioAlign.xMinYMax;
        case 'xMidYMax':
          align = SvgAspectRatioAlign.xMidYMax;
        case 'xMaxYMax':
          align = SvgAspectRatioAlign.xMaxYMax;
        case 'slice':
          meetOrSlice = SvgMeetOrSlice.slice;
        case 'meet':
          meetOrSlice = SvgMeetOrSlice.meet;
      }
    }
    return SvgPreserveAspectRatio(align: align, meetOrSlice: meetOrSlice);
  }

  static ui.TileMode _parseSpreadMethod(String? raw) {
    switch (raw?.trim()) {
      case 'reflect':
        return ui.TileMode.mirror;
      case 'repeat':
        return ui.TileMode.repeated;
      default:
        return ui.TileMode.clamp;
    }
  }

  static List<String> _parseClasses(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
}
