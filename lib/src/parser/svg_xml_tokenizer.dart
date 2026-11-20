/// Ordered mixed-content node inside an [SvgXmlElement].
/// [SvgXmlElement] 内部的有序混合内容节点基类。
///
/// Either a character data segment ([SvgXmlTextContent]) or a child element
/// ([SvgXmlElement]). Preserving document order is required by W3C SVG `<text>`
/// mixed content such as `<text>Hello <tspan>World</tspan>!</text>`.
/// 可为文本片段（[SvgXmlTextContent]）或子元素（[SvgXmlElement]），用于保留 `<text>` 混合内容顺序。
sealed class SvgXmlNode {
  /// Creates an [SvgXmlNode].
  /// 创建一个 [SvgXmlNode] 节点。
  const SvgXmlNode();
}

/// Character data segment inside an [SvgXmlElement].
/// [SvgXmlElement] 内部的字符数据文本片段节点。
final class SvgXmlTextContent extends SvgXmlNode {
  /// Decoded text payload of this character data segment.
  /// 解码后的字符文本内容。
  final String text;

  /// Creates an [SvgXmlTextContent] holding [text].
  /// 创建一个包含 [text] 的文本片段节点。
  ///
  /// - [text]: Decoded character data. 解码后的字符数据。
  const SvgXmlTextContent(this.text);
}

/// Lightweight, zero-dependency XML element node built specifically for SVG AST construction.
/// 专为 SVG AST 构建设计的轻量、零依赖 XML 元素节点。
final class SvgXmlElement extends SvgXmlNode {
  /// Local tag name with any XML namespace prefix stripped (e.g., `'path'`, `'g'`).
  /// 去除命名空间前缀后的标签名（如 `'path'`、`'g'`）。
  final String name;

  /// Map of decoded XML attribute names to values.
  /// 解码后的 XML 属性名值映射表。
  final Map<String, String> attributes;

  /// Direct child elements in document order.
  /// 按文档顺序排列的直接子元素列表。
  final List<SvgXmlElement> children;

  /// Ordered mixed-content child nodes (interleaved text segments and elements).
  /// 按文档顺序排列的混合内容节点列表（交错包含文本片段与子元素）。
  final List<SvgXmlNode> contentNodes;

  /// Concatenated text content of all direct text/CDATA segments inside this element.
  /// 当前元素内所有直接文本与 CDATA 片段拼接后的纯文本内容。
  final String textContent;

  /// Creates an [SvgXmlElement].
  /// 创建一个 [SvgXmlElement] 实例。
  ///
  /// - [name]: Local XML tag name. 标签名。
  /// - [attributes]: Parsed attribute map. 属性映射表。
  /// - [children]: Direct child elements. 直接子元素列表。
  /// - [contentNodes]: Ordered mixed-content nodes. 有序混合内容节点列表。
  /// - [textContent]: Concatenated direct text content. 拼接后的直接文本内容。
  const SvgXmlElement({
    required this.name,
    required this.attributes,
    required this.children,
    this.contentNodes = const [],
    this.textContent = '',
  });

  /// Returns the attribute value for [key], or `null` if absent.
  /// 返回属性 [key] 对应的值；若不存在则返回 `null`。
  ///
  /// - [key]: XML attribute name to look up. 要查询的 XML 属性名。
  String? attr(String key) => attributes[key];

  /// Resolves `href` or `xlink:href` without a leading `#`.
  /// 解析 `href` 或 `xlink:href` 属性，并去除前导 `#`。
  String? get hrefId {
    final raw = attributes['href'] ?? attributes['xlink:href'];
    if (raw == null || raw.isEmpty) return null;
    final trimmed = raw.trim();
    return trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  }
}

/// Fast, zero-dependency XML tokenizer and tree parser for SVG documents.
/// 高速、零依赖的 SVG 文档 XML 词法与树解析器。
abstract final class SvgXmlTokenizer {
  /// Parses [xmlSource] and returns its root [SvgXmlElement] (typically `<svg>`).
  /// 解析 [xmlSource] 字符串并返回其根 [SvgXmlElement]（通常为 `<svg>`）。
  ///
  /// - [xmlSource]: Raw SVG XML source string. 原始 SVG XML 源码字符串。
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
        contentNodes: const [],
      );
    }

    final children = <SvgXmlElement>[];
    final contentNodes = <SvgXmlNode>[];
    final textBuf = StringBuffer();

    while (_pos < _len) {
      if (_src.startsWith('<!--', _pos)) {
        final end = _src.indexOf('-->', _pos + 4);
        _pos = end != -1 ? end + 3 : _len;
      } else if (_src.startsWith('<![CDATA[', _pos)) {
        final end = _src.indexOf(']]>', _pos + 9);
        if (end != -1) {
          final cdata = _src.substring(_pos + 9, end);
          textBuf.write(cdata);
          if (cdata.isNotEmpty) {
            contentNodes.add(SvgXmlTextContent(cdata));
          }
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
          contentNodes.add(child);
        } else {
          _pos++;
        }
      } else {
        final nextTag = _src.indexOf('<', _pos);
        final rawSegment = nextTag == -1
            ? _src.substring(_pos)
            : _src.substring(_pos, nextTag);
        _pos = nextTag == -1 ? _len : nextTag;
        final decoded = _decodeEntities(rawSegment);
        textBuf.write(decoded);
        if (decoded.isNotEmpty) {
          contentNodes.add(SvgXmlTextContent(decoded));
        }
      }
    }

    return SvgXmlElement(
      name: tagName,
      attributes: attrs,
      children: children,
      contentNodes: contentNodes,
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

  static final RegExp _numericEntityRegExp = RegExp(
    r'&#(?:x([0-9a-fA-F]+)|([0-9]+));',
  );

  static String _decodeEntities(String input) {
    if (!input.contains('&')) return input;
    var out = input
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', '\u00A0');
    if (out.contains('&#')) {
      out = out.replaceAllMapped(_numericEntityRegExp, (m) {
        final hex = m.group(1);
        final dec = m.group(2);
        final codePoint = hex != null
            ? int.tryParse(hex, radix: 16)
            : int.tryParse(dec ?? '');
        if (codePoint == null || codePoint < 0 || codePoint > 0x10FFFF) {
          return m.group(0)!;
        }
        return String.fromCharCode(codePoint);
      });
    }
    return out.replaceAll('&amp;', '&');
  }
}
