/// Pure-Dart resolver for W3C CSS Custom Properties (`--*`) and `var(--name, fallback)`.
/// 纯 Dart 实现的 W3C CSS 自定义变量（`--*`）与 `var(--name, fallback)` 解析器。
abstract final class SvgCssVariables {
  static const int _maxDepth = 16;

  /// Resolves all `var(--name[, fallback])` occurrences inside [rawValue] using
  /// the element's inherited [variables] table, with cycle protection.
  /// 使用元素继承的自定义变量表 [variables] 递归替换 [rawValue] 中全部 `var()` 表达式（含循环引用保护）。
  ///
  /// - [rawValue]: Raw CSS property value containing one or more `var(...)` calls.
  ///   包含一个或多个 `var(...)` 的原始 CSS 属性值。
  /// - [variables]: Inherited `--*` custom property lookup map. 继承的 `--*` 自定义变量映射表。
  /// - [depth]: Internal recursion depth guard (defaults to `0`). 内部递归深度计数（默认 `0`）。
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
