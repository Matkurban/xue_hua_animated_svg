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
