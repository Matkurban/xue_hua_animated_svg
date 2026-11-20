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
  final Map<String, SvgMaskNode> masksById = <String, SvgMaskNode>{};
  final Map<String, SvgPatternNode> patternsById = <String, SvgPatternNode>{};
  final Map<String, SvgMarkerNode> markersById = <String, SvgMarkerNode>{};
  final Map<String, SvgFilterNode> filtersById = <String, SvgFilterNode>{};
  final Map<String, SvgViewNode> viewsById = <String, SvgViewNode>{};
  final List<SvgImageNode> imageNodes = <SvgImageNode>[];

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
      masksById: masksById,
      patternsById: patternsById,
      markersById: markersById,
      filtersById: filtersById,
      viewsById: viewsById,
      imageNodes: imageNodes,
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

        case 'mask':
          final mask = _buildMask(childXml, parentGroup.style);
          if (mask.id != null && mask.id!.isNotEmpty) {
            masksById[mask.id!] = mask;
          }

        case 'pattern':
          final pattern = _buildPattern(childXml, parentGroup.style);
          if (pattern.id != null && pattern.id!.isNotEmpty) {
            patternsById[pattern.id!] = pattern;
          }

        case 'marker':
          final marker = _buildMarker(childXml, parentGroup.style);
          if (marker.id != null && marker.id!.isNotEmpty) {
            markersById[marker.id!] = marker;
          }

        case 'filter':
          final filterNode = _buildFilter(childXml);
          if (filterNode != null && filterNode.id.isNotEmpty) {
            filtersById[filterNode.id] = filterNode;
          }

        case 'view':
          final viewId = childXml.attr('id');
          if (viewId != null && viewId.isNotEmpty) {
            viewsById[viewId] = SvgViewNode(
              id: viewId,
              viewBox: _parseOptionalViewBox(childXml.attr('viewBox')),
              preserveAspectRatio: childXml.attr('preserveAspectRatio') != null
                  ? _parsePreserveAspectRatio(
                      childXml.attr('preserveAspectRatio'),
                    )
                  : null,
            );
          }

        case 'animate':
        case 'animateColor':
          _smilCompiler.compileSmilAnimateOnElement(parentGroup, childXml);

        case 'set':
          _smilCompiler.compileSmilSetOnElement(parentGroup, childXml);

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
              if (insideDefs || elem is SvgSymbolNode) {
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
          insideDefs: insideDefs,
        );
        node = group;

      case 'a':
        final anchor = SvgAnchorNode(
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          href: xml.attr('href') ?? xml.attr('xlink:href'),
          target: xml.attr('target'),
        );
        _buildChildren(
          parentXml: xml,
          parentGroup: anchor,
          insideDefs: insideDefs,
        );
        node = anchor;

      case 'switch':
        final childConditions = <SvgConditionalAttrs>[];
        final switchNode = SvgSwitchNode(
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          childConditions: childConditions,
        );
        for (final childXml in xml.children) {
          final childTag = childXml.name;
          if (childTag == 'style' ||
              childTag == 'title' ||
              childTag == 'desc' ||
              childTag == 'metadata') {
            continue;
          }
          if (childTag == 'animate' || childTag == 'animateColor') {
            _smilCompiler.compileSmilAnimateOnElement(switchNode, childXml);
            continue;
          }
          if (childTag == 'set') {
            _smilCompiler.compileSmilSetOnElement(switchNode, childXml);
            continue;
          }
          if (childTag == 'animateTransform') {
            _smilCompiler.compileSmilAnimateTransformOnElement(
              switchNode,
              childXml,
            );
            continue;
          }
          if (childTag == 'animateMotion') {
            _smilCompiler.deferSmilAnimateMotionOnElement(switchNode, childXml);
            continue;
          }
          final childElem = _buildElementNode(
            xml: childXml,
            parentElement: switchNode,
            insideDefs: insideDefs,
          );
          if (childElem != null) {
            childElem.parent = switchNode;
            switchNode.children.add(childElem);
            childConditions.add(
              SvgConditionalAttrs(
                requiredExtensions: childXml.attr('requiredExtensions'),
                requiredFeatures: childXml.attr('requiredFeatures'),
                systemLanguages: _parseCommaOrSpaceList(
                  childXml.attr('systemLanguage'),
                ),
              ),
            );
            if (childElem.id != null && childElem.id!.isNotEmpty) {
              elementsById[childElem.id!] = childElem;
              if (insideDefs || childElem is SvgSymbolNode) {
                defsById[childElem.id!] = childElem;
              }
              if (childElem is SvgGeometryNode) {
                geometryById[childElem.id!] = childElem;
              }
            }
          }
        }
        node = switchNode;

      case 'svg':
        final nestedSvg = SvgNestedSvgNode(
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
          baseWidth: SvgCssParser.parseNumberOrPercent(
            xml.attr('width'),
            referenceExtent: viewBox.width,
          ),
          baseHeight: SvgCssParser.parseNumberOrPercent(
            xml.attr('height'),
            referenceExtent: viewBox.height,
          ),
          innerViewBox: _parseOptionalViewBox(xml.attr('viewBox')),
          preserveAspectRatio: _parsePreserveAspectRatio(
            xml.attr('preserveAspectRatio'),
          ),
        );
        _buildChildren(
          parentXml: xml,
          parentGroup: nestedSvg,
          insideDefs: insideDefs,
        );
        node = nestedSvg;

      case 'symbol':
        final symbolNode = SvgSymbolNode(
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
          baseWidth: SvgCssParser.parseNumberOrPercent(
            xml.attr('width'),
            referenceExtent: viewBox.width,
          ),
          baseHeight: SvgCssParser.parseNumberOrPercent(
            xml.attr('height'),
            referenceExtent: viewBox.height,
          ),
          refX:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('refX'),
                referenceExtent: viewBox.width,
              ) ??
              0.0,
          refY:
              SvgCssParser.parseNumberOrPercent(
                xml.attr('refY'),
                referenceExtent: viewBox.height,
              ) ??
              0.0,
          innerViewBox: _parseOptionalViewBox(xml.attr('viewBox')),
          preserveAspectRatio: _parsePreserveAspectRatio(
            xml.attr('preserveAspectRatio'),
          ),
        );
        _buildChildren(
          parentXml: xml,
          parentGroup: symbolNode,
          insideDefs: true,
        );
        node = symbolNode;

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
          baseWidth: SvgCssParser.parseNumberOrPercent(
            xml.attr('width'),
            referenceExtent: viewBox.width,
          ),
          baseHeight: SvgCssParser.parseNumberOrPercent(
            xml.attr('height'),
            referenceExtent: viewBox.height,
          ),
        );

      case 'image':
        final imageNode = SvgImageNode(
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          href: xml.attr('href') ?? xml.attr('xlink:href'),
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
          preserveAspectRatio: _parsePreserveAspectRatio(
            xml.attr('preserveAspectRatio'),
          ),
        );
        imageNodes.add(imageNode);
        node = imageNode;

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

      case 'text':
        final contentItems = _buildTextContentItems(
          parentXml: xml,
          parentStyle: style,
          insideDefs: insideDefs,
        );
        final textNode = SvgTextNode(
          id: id,
          classes: classes,
          style: style,
          baseTransformOps: baseTransformOps,
          xList: SvgCssValueParser.parseTextLengthList(xml.attr('x')),
          yList: SvgCssValueParser.parseTextLengthList(xml.attr('y')),
          dxList: SvgCssValueParser.parseTextLengthList(xml.attr('dx')),
          dyList: SvgCssValueParser.parseTextLengthList(xml.attr('dy')),
          rotateList: SvgCssParser.parseNumberList(xml.attr('rotate')),
          textLength: SvgCssValueParser.parseTextLength(xml.attr('textLength')),
          lengthAdjust: _parseLengthAdjust(xml.attr('lengthAdjust')),
          contentItems: contentItems,
        );
        for (final item in contentItems) {
          if (item case final SvgElement elem) {
            elem.parent = textNode;
          }
        }
        node = textNode;

      default:
        return null;
    }

    // Parse SMIL animation children attached to non-group shape/use nodes
    if (node is! SvgGroupNode) {
      for (final animXml in xml.children) {
        switch (animXml.name) {
          case 'animate':
          case 'animateColor':
            _smilCompiler.compileSmilAnimateOnElement(node, animXml);
          case 'set':
            _smilCompiler.compileSmilSetOnElement(node, animXml);
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
    final units = xml.attr('clipPathUnits') == 'objectBoundingBox'
        ? SvgGradientUnits.objectBoundingBox
        : SvgGradientUnits.userSpaceOnUse;
    final clipNode = SvgClipPathNode(
      id: xml.attr('id'),
      style: style,
      clipPathUnits: units,
    );
    _buildChildren(parentXml: xml, parentGroup: clipNode, insideDefs: true);
    return clipNode;
  }

  SvgMaskNode _buildMask(SvgXmlElement xml, SvgStyle parentStyle) {
    final id = xml.attr('id');
    final classes = _parseClasses(xml.attr('class'));
    final style = SvgStyle();
    _applyElementAttributesAndCss(
      xml: xml,
      tagName: 'mask',
      id: id,
      classes: classes,
      style: style,
      outCssAnimations: <SvgCssAnimationConfig>[],
    );
    style.resolveInheritance(parentStyle);

    final maskUnits = xml.attr('maskUnits') == 'userSpaceOnUse'
        ? SvgGradientUnits.userSpaceOnUse
        : SvgGradientUnits.objectBoundingBox;
    final maskContentUnits = xml.attr('maskContentUnits') == 'objectBoundingBox'
        ? SvgGradientUnits.objectBoundingBox
        : SvgGradientUnits.userSpaceOnUse;
    final inlineDecls = xml.attr('style') != null
        ? SvgCssParser.parseDeclarationsMap(xml.attr('style')!)
        : const <String, String>{};
    final maskTypeRaw =
        (inlineDecls['mask-type'] ?? xml.attr('mask-type') ?? 'luminance')
            .trim()
            .toLowerCase();
    final maskType = maskTypeRaw == 'alpha'
        ? SvgMaskType.alpha
        : SvgMaskType.luminance;

    final isUserSpace = maskUnits == SvgGradientUnits.userSpaceOnUse;
    final x =
        SvgCssParser.parseNumberOrPercent(
          xml.attr('x'),
          referenceExtent: isUserSpace ? viewBox.width : null,
        ) ??
        (isUserSpace ? viewBox.left : -0.1);
    final y =
        SvgCssParser.parseNumberOrPercent(
          xml.attr('y'),
          referenceExtent: isUserSpace ? viewBox.height : null,
        ) ??
        (isUserSpace ? viewBox.top : -0.1);
    final w =
        SvgCssParser.parseNumberOrPercent(
          xml.attr('width'),
          referenceExtent: isUserSpace ? viewBox.width : null,
        ) ??
        (isUserSpace ? viewBox.width : 1.2);
    final h =
        SvgCssParser.parseNumberOrPercent(
          xml.attr('height'),
          referenceExtent: isUserSpace ? viewBox.height : null,
        ) ??
        (isUserSpace ? viewBox.height : 1.2);

    final maskNode = SvgMaskNode(
      id: id,
      classes: classes,
      style: style,
      maskUnits: maskUnits,
      maskContentUnits: maskContentUnits,
      maskType: maskType,
      x: x,
      y: y,
      width: w,
      height: h,
    );
    _buildChildren(parentXml: xml, parentGroup: maskNode, insideDefs: true);
    return maskNode;
  }

  SvgPatternNode _buildPattern(SvgXmlElement xml, SvgStyle parentStyle) {
    final id = xml.attr('id');
    final classes = _parseClasses(xml.attr('class'));
    final style = SvgStyle();
    _applyElementAttributesAndCss(
      xml: xml,
      tagName: 'pattern',
      id: id,
      classes: classes,
      style: style,
      outCssAnimations: <SvgCssAnimationConfig>[],
    );
    style.resolveInheritance(parentStyle);

    final patternUnits = xml.attr('patternUnits') == 'userSpaceOnUse'
        ? SvgGradientUnits.userSpaceOnUse
        : SvgGradientUnits.objectBoundingBox;
    final patternContentUnits =
        xml.attr('patternContentUnits') == 'objectBoundingBox'
        ? SvgGradientUnits.objectBoundingBox
        : SvgGradientUnits.userSpaceOnUse;
    final isUserSpace = patternUnits == SvgGradientUnits.userSpaceOnUse;

    final patternNode = SvgPatternNode(
      id: id,
      classes: classes,
      style: style,
      hrefId: xml.hrefId,
      patternUnits: patternUnits,
      patternContentUnits: patternContentUnits,
      x:
          SvgCssParser.parseNumberOrPercent(
            xml.attr('x'),
            referenceExtent: isUserSpace ? viewBox.width : null,
          ) ??
          0.0,
      y:
          SvgCssParser.parseNumberOrPercent(
            xml.attr('y'),
            referenceExtent: isUserSpace ? viewBox.height : null,
          ) ??
          0.0,
      width:
          SvgCssParser.parseNumberOrPercent(
            xml.attr('width'),
            referenceExtent: isUserSpace ? viewBox.width : null,
          ) ??
          0.0,
      height:
          SvgCssParser.parseNumberOrPercent(
            xml.attr('height'),
            referenceExtent: isUserSpace ? viewBox.height : null,
          ) ??
          0.0,
      innerViewBox: _parseOptionalViewBox(xml.attr('viewBox')),
      preserveAspectRatio: _parsePreserveAspectRatio(
        xml.attr('preserveAspectRatio'),
      ),
      basePatternTransformOps: SvgCssParser.parseTransformOps(
        xml.attr('patternTransform') ?? '',
      ),
    );
    _buildChildren(parentXml: xml, parentGroup: patternNode, insideDefs: true);
    return patternNode;
  }

  SvgMarkerNode _buildMarker(SvgXmlElement xml, SvgStyle parentStyle) {
    final id = xml.attr('id');
    final classes = _parseClasses(xml.attr('class'));
    final style = SvgStyle();
    _applyElementAttributesAndCss(
      xml: xml,
      tagName: 'marker',
      id: id,
      classes: classes,
      style: style,
      outCssAnimations: <SvgCssAnimationConfig>[],
    );
    style.resolveInheritance(parentStyle);

    final markerUnits = xml.attr('markerUnits') == 'userSpaceOnUse'
        ? SvgMarkerUnits.userSpaceOnUse
        : SvgMarkerUnits.strokeWidth;
    final orientRaw = (xml.attr('orient') ?? '0').trim().toLowerCase();
    SvgMarkerOrientMode orientMode = SvgMarkerOrientMode.fixedAngle;
    double fixedDeg = 0.0;
    if (orientRaw == 'auto') {
      orientMode = SvgMarkerOrientMode.auto;
    } else if (orientRaw == 'auto-start-reverse') {
      orientMode = SvgMarkerOrientMode.autoStartReverse;
    } else {
      fixedDeg = SvgCssParser.parseAngleOrLength(orientRaw) ?? 0.0;
    }

    final markerNode = SvgMarkerNode(
      id: id,
      classes: classes,
      style: style,
      refX: SvgCssParser.parseLength(xml.attr('refX')) ?? 0.0,
      refY: SvgCssParser.parseLength(xml.attr('refY')) ?? 0.0,
      markerWidth: SvgCssParser.parseLength(xml.attr('markerWidth')) ?? 3.0,
      markerHeight: SvgCssParser.parseLength(xml.attr('markerHeight')) ?? 3.0,
      markerUnits: markerUnits,
      orientMode: orientMode,
      fixedOrientDeg: fixedDeg,
      innerViewBox: _parseOptionalViewBox(xml.attr('viewBox')),
      preserveAspectRatio: _parsePreserveAspectRatio(
        xml.attr('preserveAspectRatio'),
      ),
    );
    _buildChildren(parentXml: xml, parentGroup: markerNode, insideDefs: true);
    return markerNode;
  }

  SvgFilterNode? _buildFilter(SvgXmlElement xml) {
    final id = xml.attr('id') ?? '';
    if (id.isEmpty) return null;

    final filterUnits = xml.attr('filterUnits') == 'userSpaceOnUse'
        ? SvgGradientUnits.userSpaceOnUse
        : SvgGradientUnits.objectBoundingBox;
    final primitiveUnits = xml.attr('primitiveUnits') == 'objectBoundingBox'
        ? SvgGradientUnits.objectBoundingBox
        : SvgGradientUnits.userSpaceOnUse;
    final isUserSpace = filterUnits == SvgGradientUnits.userSpaceOnUse;

    final x =
        SvgCssParser.parseNumberOrPercent(
          xml.attr('x'),
          referenceExtent: isUserSpace ? viewBox.width : null,
        ) ??
        (isUserSpace ? viewBox.left : -0.1);
    final y =
        SvgCssParser.parseNumberOrPercent(
          xml.attr('y'),
          referenceExtent: isUserSpace ? viewBox.height : null,
        ) ??
        (isUserSpace ? viewBox.top : -0.1);
    final w =
        SvgCssParser.parseNumberOrPercent(
          xml.attr('width'),
          referenceExtent: isUserSpace ? viewBox.width : null,
        ) ??
        (isUserSpace ? viewBox.width : 1.2);
    final h =
        SvgCssParser.parseNumberOrPercent(
          xml.attr('height'),
          referenceExtent: isUserSpace ? viewBox.height : null,
        ) ??
        (isUserSpace ? viewBox.height : 1.2);

    final primitives = <SvgFilterPrimitive>[];
    for (final child in xml.children) {
      final prim = _buildFilterPrimitive(child);
      if (prim != null) primitives.add(prim);
    }

    return SvgFilterNode(
      id: id,
      filterUnits: filterUnits,
      primitiveUnits: primitiveUnits,
      x: x,
      y: y,
      width: w,
      height: h,
      primitives: primitives,
    );
  }

  SvgFilterPrimitive? _buildFilterPrimitive(SvgXmlElement xml) {
    final inSrc = xml.attr('in');
    final res = xml.attr('result');
    final inlineDecls = xml.attr('style') != null
        ? SvgCssParser.parseDeclarationsMap(xml.attr('style')!)
        : const <String, String>{};

    switch (xml.name) {
      case 'feGaussianBlur':
        final sd = SvgCssParser.parseNumberList(xml.attr('stdDeviation'));
        final sx = sd.isNotEmpty ? sd[0] : 0.0;
        final sy = sd.length > 1 ? sd[1] : sx;
        final edgeModeRaw = xml.attr('edgeMode')?.trim().toLowerCase();
        final ui.TileMode tileMode;
        switch (edgeModeRaw) {
          case 'duplicate':
            tileMode = ui.TileMode.clamp;
          case 'wrap':
            tileMode = ui.TileMode.repeated;
          default:
            tileMode = ui.TileMode.decal;
        }
        return SvgFeGaussianBlur(
          inSource: inSrc,
          result: res,
          sigmaX: sx,
          sigmaY: sy,
          tileMode: tileMode,
        );

      case 'feDropShadow':
        final sd = SvgCssParser.parseNumberList(xml.attr('stdDeviation'));
        final sx = sd.isNotEmpty ? sd[0] : 2.0;
        final sy = sd.length > 1 ? sd[1] : sx;
        final fcRaw = xml.attr('flood-color') ?? inlineDecls['flood-color'];
        final foRaw = xml.attr('flood-opacity') ?? inlineDecls['flood-opacity'];
        return SvgFeDropShadow(
          inSource: inSrc,
          result: res,
          dx: SvgCssParser.parseLength(xml.attr('dx')) ?? 2.0,
          dy: SvgCssParser.parseLength(xml.attr('dy')) ?? 2.0,
          sigmaX: sx,
          sigmaY: sy,
          floodColor:
              SvgCssParser.parseColor(fcRaw) ?? const ui.Color(0xFF000000),
          floodOpacity:
              (SvgCssParser.parseNumberOrPercent(foRaw) ?? 1.0).clamp(0.0, 1.0),
        );

      case 'feOffset':
        return SvgFeOffset(
          inSource: inSrc,
          result: res,
          dx: SvgCssParser.parseLength(xml.attr('dx')) ?? 0.0,
          dy: SvgCssParser.parseLength(xml.attr('dy')) ?? 0.0,
        );

      case 'feColorMatrix':
        final typeRaw = (xml.attr('type') ?? 'matrix').trim().toLowerCase();
        final SvgFeColorMatrixType cmType;
        switch (typeRaw) {
          case 'saturate':
            cmType = SvgFeColorMatrixType.saturate;
          case 'huerotate':
            cmType = SvgFeColorMatrixType.hueRotate;
          case 'luminancetoalpha':
            cmType = SvgFeColorMatrixType.luminanceToAlpha;
          default:
            cmType = SvgFeColorMatrixType.matrix;
        }
        return SvgFeColorMatrix(
          inSource: inSrc,
          result: res,
          type: cmType,
          values: SvgCssParser.parseNumberList(xml.attr('values')),
        );

      case 'feFlood':
        final fcRaw = xml.attr('flood-color') ?? inlineDecls['flood-color'];
        final foRaw = xml.attr('flood-opacity') ?? inlineDecls['flood-opacity'];
        return SvgFeFlood(
          inSource: inSrc,
          result: res,
          floodColor:
              SvgCssParser.parseColor(fcRaw) ?? const ui.Color(0xFF000000),
          floodOpacity:
              (SvgCssParser.parseNumberOrPercent(foRaw) ?? 1.0).clamp(0.0, 1.0),
        );

      case 'feBlend':
        return SvgFeBlend(
          inSource: inSrc,
          result: res,
          in2: xml.attr('in2'),
          mode: _parseBlendMode(xml.attr('mode')),
        );

      case 'feComposite':
        return SvgFeComposite(
          inSource: inSrc,
          result: res,
          in2: xml.attr('in2'),
          operatorMode: _parseCompositeMode(xml.attr('operator')),
        );

      case 'feMerge':
        final inputs = <String?>[
          for (final child in xml.children)
            if (child.name == 'feMergeNode') child.attr('in'),
        ];
        return SvgFeMerge(inSource: inSrc, result: res, inputs: inputs);

      case 'feMorphology':
        final rad = SvgCssParser.parseNumberList(xml.attr('radius'));
        final rx = rad.isNotEmpty ? rad[0] : 0.0;
        final ry = rad.length > 1 ? rad[1] : rx;
        return SvgFeMorphology(
          inSource: inSrc,
          result: res,
          isDilate: xml.attr('operator')?.trim().toLowerCase() == 'dilate',
          radiusX: rx,
          radiusY: ry,
        );

      case 'feComponentTransfer':
        SvgFeTransferFunc? rFunc;
        SvgFeTransferFunc? gFunc;
        SvgFeTransferFunc? bFunc;
        SvgFeTransferFunc? aFunc;
        for (final child in xml.children) {
          switch (child.name) {
            case 'feFuncR':
              rFunc = _buildTransferFunc(child);
            case 'feFuncG':
              gFunc = _buildTransferFunc(child);
            case 'feFuncB':
              bFunc = _buildTransferFunc(child);
            case 'feFuncA':
              aFunc = _buildTransferFunc(child);
          }
        }
        return SvgFeComponentTransfer(
          inSource: inSrc,
          result: res,
          funcR: rFunc,
          funcG: gFunc,
          funcB: bFunc,
          funcA: aFunc,
        );

      case 'feTurbulence':
        final bf = SvgCssParser.parseNumberList(xml.attr('baseFrequency'));
        final bfx = bf.isNotEmpty ? bf[0] : 0.0;
        final bfy = bf.length > 1 ? bf[1] : bfx;
        final oct = int.tryParse((xml.attr('numOctaves') ?? '1').trim()) ?? 1;
        final seedVal =
            double.tryParse((xml.attr('seed') ?? '0').trim())?.round() ?? 0;
        final isFractal =
            xml.attr('type')?.trim().toLowerCase() == 'fractalnoise';
        final stitch =
            xml.attr('stitchTiles')?.trim().toLowerCase() == 'stitch';
        return SvgFeTurbulence(
          inSource: inSrc,
          result: res,
          isFractalNoise: isFractal,
          baseFreqX: bfx,
          baseFreqY: bfy,
          numOctaves: oct,
          seed: seedVal,
          stitchTiles: stitch,
        );

      case 'feDisplacementMap':
        return SvgFeDisplacementMap(
          inSource: inSrc,
          result: res,
          in2: xml.attr('in2'),
          scale: SvgCssParser.parseLength(xml.attr('scale')) ?? 0.0,
          xChannel: _parseChannelSelector(xml.attr('xChannelSelector')),
          yChannel: _parseChannelSelector(xml.attr('yChannelSelector')),
        );

      default:
        return null;
    }
  }

  static SvgChannelSelector _parseChannelSelector(String? raw) {
    switch (raw?.trim().toUpperCase()) {
      case 'R':
        return SvgChannelSelector.r;
      case 'G':
        return SvgChannelSelector.g;
      case 'B':
        return SvgChannelSelector.b;
      default:
        return SvgChannelSelector.a;
    }
  }

  SvgFeTransferFunc _buildTransferFunc(SvgXmlElement xml) {
    final rawType = (xml.attr('type') ?? 'identity').trim().toLowerCase();
    final SvgFeTransferFuncType type;
    switch (rawType) {
      case 'linear':
        type = SvgFeTransferFuncType.linear;
      case 'gamma':
        type = SvgFeTransferFuncType.gamma;
      case 'table':
        type = SvgFeTransferFuncType.table;
      case 'discrete':
        type = SvgFeTransferFuncType.discrete;
      default:
        type = SvgFeTransferFuncType.identity;
    }
    return SvgFeTransferFunc(
      type: type,
      slope: SvgCssParser.parseLength(xml.attr('slope')) ?? 1.0,
      intercept: SvgCssParser.parseLength(xml.attr('intercept')) ?? 0.0,
      amplitude: SvgCssParser.parseLength(xml.attr('amplitude')) ?? 1.0,
      exponent: SvgCssParser.parseLength(xml.attr('exponent')) ?? 1.0,
      offset: SvgCssParser.parseLength(xml.attr('offset')) ?? 0.0,
      tableValues: SvgCssParser.parseNumberList(xml.attr('tableValues')),
    );
  }

  static ui.BlendMode _parseBlendMode(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'multiply':
        return ui.BlendMode.multiply;
      case 'screen':
        return ui.BlendMode.screen;
      case 'overlay':
        return ui.BlendMode.overlay;
      case 'darken':
        return ui.BlendMode.darken;
      case 'lighten':
        return ui.BlendMode.lighten;
      case 'color-dodge':
        return ui.BlendMode.colorDodge;
      case 'color-burn':
        return ui.BlendMode.colorBurn;
      case 'hard-light':
        return ui.BlendMode.hardLight;
      case 'soft-light':
        return ui.BlendMode.softLight;
      case 'difference':
        return ui.BlendMode.difference;
      case 'exclusion':
        return ui.BlendMode.exclusion;
      case 'hue':
        return ui.BlendMode.hue;
      case 'saturation':
        return ui.BlendMode.saturation;
      case 'color':
        return ui.BlendMode.color;
      case 'luminosity':
        return ui.BlendMode.luminosity;
      default:
        return ui.BlendMode.srcOver;
    }
  }

  static ui.BlendMode _parseCompositeMode(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'in':
        return ui.BlendMode.srcIn;
      case 'out':
        return ui.BlendMode.srcOut;
      case 'atop':
        return ui.BlendMode.srcATop;
      case 'xor':
        return ui.BlendMode.xor;
      case 'lighter':
        return ui.BlendMode.plus;
      default:
        return ui.BlendMode.srcOver;
    }
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
    final fr = SvgCssParser.parseNumberOrPercent(xml.attr('fr')) ?? 0.0;

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
      baseFr: fr,
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
        if (animXml.name == 'animate' || animXml.name == 'animateColor') {
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

  List<SvgTextContentItem> _buildTextContentItems({
    required SvgXmlElement parentXml,
    required SvgStyle parentStyle,
    required bool insideDefs,
  }) {
    final items = <SvgTextContentItem>[];
    for (final content in parentXml.contentNodes) {
      switch (content) {
        case SvgXmlTextContent(:final text):
          if (text.isNotEmpty) {
            items.add(SvgTextLiteral(text));
          }
        case SvgXmlElement():
          final tag = content.name;
          if (tag == 'tspan' || tag == 'a') {
            final id = content.attr('id');
            final classes = _parseClasses(content.attr('class'));
            final spanStyle = SvgStyle();
            final cssAnims = <SvgCssAnimationConfig>[];
            _applyElementAttributesAndCss(
              xml: content,
              tagName: tag,
              id: id,
              classes: classes,
              style: spanStyle,
              outCssAnimations: cssAnims,
            );
            spanStyle.resolveInheritance(parentStyle);

            final nestedItems = _buildTextContentItems(
              parentXml: content,
              parentStyle: spanStyle,
              insideDefs: insideDefs,
            );
            final spanNode = SvgTextSpanNode(
              tagName: tag,
              id: id,
              classes: classes,
              style: spanStyle,
              baseTransformOps: SvgCssParser.parseTransformOps(
                content.attr('transform') ?? '',
              ),
              xList: SvgCssValueParser.parseTextLengthList(content.attr('x')),
              yList: SvgCssValueParser.parseTextLengthList(content.attr('y')),
              dxList: SvgCssValueParser.parseTextLengthList(content.attr('dx')),
              dyList: SvgCssValueParser.parseTextLengthList(content.attr('dy')),
              rotateList: SvgCssParser.parseNumberList(content.attr('rotate')),
              textLength: SvgCssValueParser.parseTextLength(
                content.attr('textLength'),
              ),
              lengthAdjust: _parseLengthAdjust(content.attr('lengthAdjust')),
              contentItems: nestedItems,
            );
            for (final child in nestedItems) {
              if (child case final SvgElement elem) {
                elem.parent = spanNode;
              }
            }
            if (id != null && id.isNotEmpty) {
              elementsById[id] = spanNode;
              if (insideDefs) defsById[id] = spanNode;
            }
            _compileChildTextAnimations(spanNode, content, cssAnims);
            items.add(spanNode);
          } else if (tag == 'textPath') {
            final id = content.attr('id');
            final classes = _parseClasses(content.attr('class'));
            final tpStyle = SvgStyle();
            final cssAnims = <SvgCssAnimationConfig>[];
            _applyElementAttributesAndCss(
              xml: content,
              tagName: tag,
              id: id,
              classes: classes,
              style: tpStyle,
              outCssAnimations: cssAnims,
            );
            tpStyle.resolveInheritance(parentStyle);

            final nestedItems = _buildTextContentItems(
              parentXml: content,
              parentStyle: tpStyle,
              insideDefs: insideDefs,
            );
            final tpNode = SvgTextPathNode(
              id: id,
              classes: classes,
              style: tpStyle,
              baseTransformOps: SvgCssParser.parseTransformOps(
                content.attr('transform') ?? '',
              ),
              hrefId: content.hrefId,
              inlinePathData: content.attr('path'),
              startOffset: SvgCssValueParser.parseTextLength(
                content.attr('startOffset'),
              ),
              sideRight: content.attr('side')?.trim().toLowerCase() == 'right',
              textLength: SvgCssValueParser.parseTextLength(
                content.attr('textLength'),
              ),
              lengthAdjust: _parseLengthAdjust(content.attr('lengthAdjust')),
              contentItems: nestedItems,
            );
            for (final child in nestedItems) {
              if (child case final SvgElement elem) {
                elem.parent = tpNode;
              }
            }
            if (id != null && id.isNotEmpty) {
              elementsById[id] = tpNode;
              if (insideDefs) defsById[id] = tpNode;
            }
            _compileChildTextAnimations(tpNode, content, cssAnims);
            items.add(tpNode);
          }
      }
    }
    return items;
  }

  void _compileChildTextAnimations(
    SvgElement element,
    SvgXmlElement xml,
    List<SvgCssAnimationConfig> cssAnims,
  ) {
    for (final child in xml.children) {
      switch (child.name) {
        case 'animate':
        case 'animateColor':
          _smilCompiler.compileSmilAnimateOnElement(element, child);
        case 'set':
          _smilCompiler.compileSmilSetOnElement(element, child);
        case 'animateTransform':
          _smilCompiler.compileSmilAnimateTransformOnElement(element, child);
        case 'animateMotion':
          _smilCompiler.deferSmilAnimateMotionOnElement(element, child);
      }
    }
    for (final cssAnim in cssAnims) {
      final stops = styleSheet.keyframesByName[cssAnim.name];
      if (stops != null && stops.isNotEmpty) {
        final compiledTracks = SvgCssParser.compileKeyframesForElement(
          target: element,
          config: cssAnim,
          stops: stops,
          documentViewBox: viewBox,
        );
        if (compiledTracks.isNotEmpty) {
          tracks.addAll(compiledTracks);
          element.hasSelfAnimation = true;
          animatedElementsSet.add(element);
        }
      }
    }
  }

  static SvgLengthAdjust _parseLengthAdjust(String? raw) {
    if (raw?.trim() == 'spacingAndGlyphs') {
      return SvgLengthAdjust.spacingAndGlyphs;
    }
    return SvgLengthAdjust.spacing;
  }

  static ui.Rect? _parseOptionalViewBox(String? viewBoxAttr) {
    if (viewBoxAttr == null || viewBoxAttr.trim().isEmpty) return null;
    final nums = SvgCssParser.parseNumberList(viewBoxAttr);
    if (nums.length >= 4) {
      return ui.Rect.fromLTWH(nums[0], nums[1], nums[2], nums[3]);
    }
    return null;
  }

  static List<String> _parseCommaOrSpaceList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
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
