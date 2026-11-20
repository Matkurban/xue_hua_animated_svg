/// Pure-Dart resolver for W3C CSS Custom Properties (`--*`) and `var(--name, fallback)`.
abstract final class SvgCssVariables {
  static const int _maxDepth = 16;

  /// Resolves all `var(--name[, fallback])` occurrences inside [rawValue] using
  /// the element's inherited [variables] table, with cycle protection.
  static String resolve(
    String rawValue,
    Map<String, String> variables, {
    int depth = 0,
  }) {
    if (depth >= _maxDepth || !rawValue.contains('var(')) {
      return rawValue;
    }

    final buf = StringBuffer();
    int pos = 0;
    final len = rawValue.length;

    while (pos < len) {
      final idx = rawValue.indexOf('var(', pos);
      if (idx == -1) {
        buf.write(rawValue.substring(pos));
        break;
      }
      buf.write(rawValue.substring(pos, idx));

      final close = _findMatchingParen(rawValue, idx + 3);
      if (close == -1) {
        buf.write(rawValue.substring(idx));
        break;
      }

      final inner = rawValue.substring(idx + 4, close).trim();
      final commaIdx = _findTopLevelComma(inner);
      final varName = (commaIdx == -1 ? inner : inner.substring(0, commaIdx))
          .trim();
      final fallback = commaIdx == -1
          ? null
          : inner.substring(commaIdx + 1).trim();

      final resolved = variables[varName];
      if (resolved != null && resolved.trim().isNotEmpty) {
        buf.write(resolve(resolved.trim(), variables, depth: depth + 1));
      } else if (fallback != null) {
        buf.write(resolve(fallback, variables, depth: depth + 1));
      }

      pos = close + 1;
    }

    return buf.toString();
  }

  static int _findMatchingParen(String s, int openIdx) {
    int depth = 0;
    for (int i = openIdx; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x28) {
        depth++;
      } else if (c == 0x29) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static int _findTopLevelComma(String s) {
    int depth = 0;
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x28) {
        depth++;
      } else if (c == 0x29) {
        if (depth > 0) depth--;
      } else if (c == 0x2C && depth == 0) {
        return i;
      }
    }
    return -1;
  }
}
