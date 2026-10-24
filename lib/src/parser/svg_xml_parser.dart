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

/// Lightweight, zero-dependency XML element node built specifically for SVG AST construction.
class SvgXmlElement {
  final String name;
  final Map<String, String> attributes;
  final List<SvgXmlElement> children;
  final String textContent;

  const SvgXmlElement({
    required this.name,
    required this.attributes,
    required this.children,
    this.textContent = '',
  });

  String? attr(String key) => attributes[key];

  /// Resolves `href` or `xlink:href` without a leading `#`.
  String? get hrefId {
    final raw = attributes['href'] ?? attributes['xlink:href'];
    if (raw == null || raw.isEmpty) return null;
    final trimmed = raw.trim();
    return trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  }
}

/// Fast, zero-dependency XML tokenizer and tree parser for SVG documents.
abstract final class SvgXmlTokenizer {
  static SvgXmlElement parseRoot(String xmlSource) {
    final parser = _XmlScanner(xmlSource);
    return parser.parseRootSvg();
  }
}

class _XmlScanner {
  final String _src;
  final int _len;
  int _pos = 0;

  _XmlScanner(this._src) : _len = _src.length;

  SvgXmlElement parseRootSvg() {
    while (_pos < _len) {
      _skipWhitespace();
      if (_pos >= _len) break;
      if (_src.startsWith('<!--', _pos)) {
        final end = _src.indexOf('-->', _pos + 4);
        _pos = end != -1 ? end + 3 : _len;
      } else if (_src.startsWith('<?', _pos)) {
        final end = _src.indexOf('?>', _pos + 2);
        _pos = end != -1 ? end + 2 : _len;
      } else if (_src.startsWith('<!DOCTYPE', _pos) ||
          _src.startsWith('<!doctype', _pos)) {
        _skipDoctype();
      } else if (_src.codeUnitAt(_pos) == 0x3C) {
        final elem = _parseElement();
        if (elem != null) return elem;
      } else {
        _pos++;
      }
    }
    return const SvgXmlElement(name: 'svg', attributes: {}, children: []);
  }

  void _skipDoctype() {
    int depth = 0;
    while (_pos < _len) {
      final c = _src.codeUnitAt(_pos++);
      if (c == 0x3C || c == 0x5B) {
        depth++;
      } else if (c == 0x3E || c == 0x5D) {
        depth--;
        if (depth <= 0 && c == 0x3E) break;
      }
    }
  }

  SvgXmlElement? _parseElement() {
    if (_pos >= _len || _src.codeUnitAt(_pos) != 0x3C) return null;
    _pos++; // skip '<'
    final rawName = _readName();
    if (rawName.isEmpty) return null;
    final tagName = _stripNamespace(rawName);

    final attrs = <String, String>{};
    bool selfClosing = false;

    while (_pos < _len) {
      _skipWhitespace();
      if (_pos >= _len) break;
      final c = _src.codeUnitAt(_pos);
      if (c == 0x2F) {
        // '/'
        _pos++;
        if (_pos < _len && _src.codeUnitAt(_pos) == 0x3E) {
          _pos++;
        }
        selfClosing = true;
        break;
      } else if (c == 0x3E) {
        // '>'
        _pos++;
        break;
      } else {
        final attrName = _readName();
        if (attrName.isEmpty) {
          _pos++;
          continue;
        }
        _skipWhitespace();
        String attrVal = '';
        if (_pos < _len && _src.codeUnitAt(_pos) == 0x3D) {
          // '='
          _pos++;
          _skipWhitespace();
          attrVal = _readAttributeValue();
        }
        attrs[attrName] = attrVal;
        final strippedAttr = _stripNamespace(attrName);
        if (strippedAttr != attrName && !attrs.containsKey(strippedAttr)) {
          attrs[strippedAttr] = attrVal;
        }
      }
    }

    if (selfClosing) {
      return SvgXmlElement(
        name: tagName,
        attributes: attrs,
        children: const [],
      );
    }

    final children = <SvgXmlElement>[];
    final textBuf = StringBuffer();

    while (_pos < _len) {
      if (_src.startsWith('<!--', _pos)) {
        final end = _src.indexOf('-->', _pos + 4);
        _pos = end != -1 ? end + 3 : _len;
      } else if (_src.startsWith('<![CDATA[', _pos)) {
        final end = _src.indexOf(']]>', _pos + 9);
        if (end != -1) {
          textBuf.write(_src.substring(_pos + 9, end));
          _pos = end + 3;
        } else {
          _pos = _len;
        }
      } else if (_src.startsWith('</', _pos)) {
        final closeEnd = _src.indexOf('>', _pos + 2);
        _pos = closeEnd != -1 ? closeEnd + 1 : _len;
        break;
      } else if (_src.codeUnitAt(_pos) == 0x3C) {
        final child = _parseElement();
        if (child != null) {
          children.add(child);
        } else {
          _pos++;
        }
      } else {
        final nextTag = _src.indexOf('<', _pos);
        if (nextTag == -1) {
          textBuf.write(_decodeEntities(_src.substring(_pos)));
          _pos = _len;
        } else {
          textBuf.write(_decodeEntities(_src.substring(_pos, nextTag)));
          _pos = nextTag;
        }
      }
    }

    return SvgXmlElement(
      name: tagName,
      attributes: attrs,
      children: children,
      textContent: textBuf.toString(),
    );
  }

  String _stripNamespace(String name) {
    final colon = name.indexOf(':');
    return colon != -1 ? name.substring(colon + 1) : name;
  }

  void _skipWhitespace() {
    while (_pos < _len) {
      final c = _src.codeUnitAt(_pos);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        _pos++;
      } else {
        break;
      }
    }
  }

  String _readName() {
    final start = _pos;
    while (_pos < _len) {
      final c = _src.codeUnitAt(_pos);
      if (c == 0x20 ||
          c == 0x09 ||
          c == 0x0A ||
          c == 0x0D ||
          c == 0x3D ||
          c == 0x2F ||
          c == 0x3E ||
          c == 0x3C) {
        break;
      }
      _pos++;
    }
    return _src.substring(start, _pos);
  }

  String _readAttributeValue() {
    if (_pos >= _len) return '';
    final quote = _src.codeUnitAt(_pos);
    if (quote == 0x22 || quote == 0x27) {
      _pos++;
      final start = _pos;
      while (_pos < _len && _src.codeUnitAt(_pos) != quote) {
        _pos++;
      }
      final val = _src.substring(start, _pos);
      if (_pos < _len) _pos++;
      return _decodeEntities(val);
    } else {
      final start = _pos;
      while (_pos < _len) {
        final c = _src.codeUnitAt(_pos);
        if (c == 0x20 ||
            c == 0x09 ||
            c == 0x0A ||
            c == 0x0D ||
            c == 0x3E ||
            c == 0x2F) {
          break;
        }
        _pos++;
      }
      return _decodeEntities(_src.substring(start, _pos));
    }
  }

  static String _decodeEntities(String input) {
    if (!input.contains('&')) return input;
    return input
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
}

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

/// Deferred `<animateMotion>` descriptor resolved after all `<path>` elements
/// (including `<mpath>` targets) have been registered in `geometryById`.
class _PendingMotionTrack {
  final SvgElement target;
  final SvgXmlElement xmlNode;
  final SvgAnimationTiming timing;

  const _PendingMotionTrack({
    required this.target,
    required this.xmlNode,
    required this.timing,
  });
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
  final List<_PendingMotionTrack> _pendingMotions = <_PendingMotionTrack>[];

  late final ui.Rect viewBox;
  late final SvgStyleSheet styleSheet;

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
    for (final pending in _pendingMotions) {
      final track = _compilePendingMotionTrack(pending);
      if (track != null) {
        tracks.add(track);
        pending.target.hasMotionAnimation = true;
        pending.target.hasSelfAnimation = true;
        animatedElementsSet.add(pending.target);
      }
    }

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
          _compileSmilAnimateOnElement(parentGroup, childXml);

        case 'animateTransform':
          _compileSmilAnimateTransformOnElement(parentGroup, childXml);

        case 'animateMotion':
          _deferSmilAnimateMotionOnElement(parentGroup, childXml);

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
            _compileSmilAnimateOnElement(node, animXml);
          case 'animateTransform':
            _compileSmilAnimateTransformOnElement(node, animXml);
          case 'animateMotion':
            _deferSmilAnimateMotionOnElement(node, animXml);
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

    _compileGradientAnimations(grad, xml);
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

    _compileGradientAnimations(grad, xml);
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
          _compileStopAnimate(stop, animXml);
        }
      }
      stops.add(stop);
    }
    return stops;
  }

  void _compileStopAnimate(SvgGradientStop stop, SvgXmlElement animXml) {
    final attrName = animXml.attr('attributeName')?.trim() ?? '';
    final rawKeyframes = _extractRawKeyframes(
      animXml,
      fallbackFrom: _defaultStopAttrValue(stop, attrName),
    );
    if (rawKeyframes.isEmpty) return;

    if (attrName == 'stop-color') {
      final colors = <ui.Color>[
        for (final r in rawKeyframes)
          SvgCssParser.parseColor(r) ?? stop.baseColor,
      ];
      final timing = _parseSmilTiming(animXml, colors.length);
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
      final timing = _parseSmilTiming(
        animXml,
        nums.length,
        numericValues: nums,
      );
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

  void _compileGradientAnimations(SvgGradientNode grad, SvgXmlElement gradXml) {
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
          final rawKf = _extractRawKeyframes(child);
          if (rawKf.isNotEmpty) {
            final nums = Float64List.fromList([
              for (final r in rawKf)
                SvgCssParser.parseNumberOrPercent(r) ?? 0.0,
            ]);
            final timing = _parseSmilTiming(
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
        final track = _buildSmilTransformTrack(
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

  void _compileSmilAnimateOnElement(SvgElement element, SvgXmlElement animXml) {
    final attrName = animXml.attr('attributeName')?.trim() ?? '';
    if (attrName.isEmpty) return;

    final rawKeyframes = _extractRawKeyframes(
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

      final timing = _parseSmilTiming(animXml, parsedPaths.length);
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
      final timing = _parseSmilTiming(animXml, colors.length);
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
      final timing = _parseSmilTiming(animXml, normalized.length);
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
      final timing = _parseSmilTiming(
        animXml,
        nums.length,
        numericValues: nums,
      );
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
      default:
        return null;
    }
  }

  void _compileSmilAnimateTransformOnElement(
    SvgElement element,
    SvgXmlElement animXml,
  ) {
    final track = _buildSmilTransformTrack(
      animXml: animXml,
      targetElement: element,
    );
    if (track != null) {
      tracks.add(track);
      element.hasSelfAnimation = true;
      animatedElementsSet.add(element);
    }
  }

  SvgTransformAnimationTrack? _buildSmilTransformTrack({
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

    final rawKeyframes = _extractRawKeyframes(
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

    final timing = _parseSmilTiming(
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

  void _deferSmilAnimateMotionOnElement(
    SvgElement element,
    SvgXmlElement animXml,
  ) {
    final kpList = SvgCssParser.parseNumberList(animXml.attr('keyPoints'));
    final rawKeyframes = _extractRawKeyframes(animXml);
    final keyframeCount = kpList.length >= 2
        ? kpList.length
        : (rawKeyframes.length >= 2 ? rawKeyframes.length : 2);
    final timing = _parseSmilTiming(animXml, keyframeCount);
    if (timing == null) return;

    _pendingMotions.add(
      _PendingMotionTrack(target: element, xmlNode: animXml, timing: timing),
    );
  }

  SvgMotionAnimationTrack? _compilePendingMotionTrack(
    _PendingMotionTrack pending,
  ) {
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
      final rawPts = _extractRawKeyframes(xml, fallbackFrom: '0,0');
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

  List<String> _extractRawKeyframes(
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

  SvgAnimationTiming? _parseSmilTiming(
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
      beginOffsetsUs: Int64List.fromList(beginList),
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
