import 'svg_xml_tokenizer.dart';

/// Combinator linking two [SvgCssCompoundSelector]s in a complex CSS selector.
enum SvgCssCombinator { descendant, child, adjacentSibling, generalSibling }

/// Attribute matching operator in a CSS attribute selector (`[attr op val]`).
enum SvgCssAttrOp {
  exists,
  equals,
  includes,
  dashMatch,
  prefix,
  suffix,
  substring,
}

/// A single CSS attribute selector such as `[data-role="hero"]` or `[disabled]`.
class SvgCssAttrSelector {
  final String name;
  final SvgCssAttrOp op;
  final String? value;
  final bool caseInsensitive;

  const SvgCssAttrSelector({
    required this.name,
    this.op = SvgCssAttrOp.exists,
    this.value,
    this.caseInsensitive = false,
  });

  bool matches(SvgXmlElement xml) {
    final actual = xml.attributes[name];
    if (actual == null) return false;
    if (op == SvgCssAttrOp.exists) return true;
    final expected = value ?? '';
    final a = caseInsensitive ? actual.toLowerCase() : actual;
    final e = caseInsensitive ? expected.toLowerCase() : expected;
    switch (op) {
      case SvgCssAttrOp.exists:
        return true;
      case SvgCssAttrOp.equals:
        return a == e;
      case SvgCssAttrOp.includes:
        return a.split(RegExp(r'\s+')).contains(e);
      case SvgCssAttrOp.dashMatch:
        return a == e || a.startsWith('$e-');
      case SvgCssAttrOp.prefix:
        return e.isNotEmpty && a.startsWith(e);
      case SvgCssAttrOp.suffix:
        return e.isNotEmpty && a.endsWith(e);
      case SvgCssAttrOp.substring:
        return e.isNotEmpty && a.contains(e);
    }
  }
}

/// Static structural pseudo-class matcher (zero JS / zero dynamic DOM state).
sealed class SvgCssPseudoClass {
  const SvgCssPseudoClass();

  bool matches(SvgCssMatchContext ctx);

  /// Specificity contribution `(id, classAttrPseudo, tag)`.
  (int, int, int) get specificity => const (0, 1, 0);
}

final class SvgCssRootPseudo extends SvgCssPseudoClass {
  const SvgCssRootPseudo();
  @override
  bool matches(SvgCssMatchContext ctx) => ctx.parent == null;
}

final class SvgCssFirstChildPseudo extends SvgCssPseudoClass {
  const SvgCssFirstChildPseudo();
  @override
  bool matches(SvgCssMatchContext ctx) => ctx.siblingIndex == 0;
}

final class SvgCssLastChildPseudo extends SvgCssPseudoClass {
  const SvgCssLastChildPseudo();
  @override
  bool matches(SvgCssMatchContext ctx) =>
      ctx.siblingIndex == ctx.siblingCount - 1;
}

final class SvgCssOnlyChildPseudo extends SvgCssPseudoClass {
  const SvgCssOnlyChildPseudo();
  @override
  bool matches(SvgCssMatchContext ctx) => ctx.siblingCount == 1;
}

final class SvgCssEmptyPseudo extends SvgCssPseudoClass {
  const SvgCssEmptyPseudo();
  @override
  bool matches(SvgCssMatchContext ctx) =>
      ctx.xml.children.isEmpty && ctx.xml.textContent.isEmpty;
}

final class SvgCssNthChildPseudo extends SvgCssPseudoClass {
  final int a;
  final int b;
  final bool fromLast;

  const SvgCssNthChildPseudo(this.a, this.b, {this.fromLast = false});

  @override
  bool matches(SvgCssMatchContext ctx) {
    final pos = fromLast
        ? (ctx.siblingCount - ctx.siblingIndex)
        : (ctx.siblingIndex + 1);
    if (a == 0) return pos == b;
    final diff = pos - b;
    if (a > 0) return diff >= 0 && diff % a == 0;
    return diff <= 0 && diff % a == 0;
  }
}

final class SvgCssNotPseudo extends SvgCssPseudoClass {
  final SvgCssCompoundSelector inner;

  const SvgCssNotPseudo(this.inner);

  @override
  bool matches(SvgCssMatchContext ctx) => !inner.matches(ctx);

  @override
  (int, int, int) get specificity => inner.specificity;
}

/// Immutable tree context for an XML element during compile-time CSS matching.
class SvgCssMatchContext {
  final SvgXmlElement xml;
  final String tagName;
  final String? id;
  final List<String> classes;
  final SvgCssMatchContext? parent;
  final SvgCssMatchContext? previousSibling;
  final int siblingIndex;
  final int siblingCount;

  const SvgCssMatchContext({
    required this.xml,
    required this.tagName,
    this.id,
    this.classes = const [],
    this.parent,
    this.previousSibling,
    this.siblingIndex = 0,
    this.siblingCount = 1,
  });
}

/// A single compound selector without combinators (e.g., `g#hero.active[data-x]:first-child`).
class SvgCssCompoundSelector {
  final String? tagName; // null means universal `*` or omitted
  final String? id;
  final List<String> classes;
  final List<SvgCssAttrSelector> attributes;
  final List<SvgCssPseudoClass> pseudoClasses;

  const SvgCssCompoundSelector({
    this.tagName,
    this.id,
    this.classes = const [],
    this.attributes = const [],
    this.pseudoClasses = const [],
  });

  /// W3C Selectors Level 4 specificity tuple `(a: ID, b: class/attr/pseudo, c: type)`.
  (int, int, int) get specificity {
    int a = id != null ? 1 : 0;
    int b = classes.length + attributes.length;
    int c = tagName != null ? 1 : 0;
    for (final p in pseudoClasses) {
      final (pa, pb, pc) = p.specificity;
      a += pa;
      b += pb;
      c += pc;
    }
    return (a, b, c);
  }

  bool matches(SvgCssMatchContext ctx) {
    if (tagName != null && ctx.tagName != tagName) return false;
    if (id != null && ctx.id != id) return false;
    for (int i = 0; i < classes.length; i++) {
      if (!ctx.classes.contains(classes[i])) return false;
    }
    for (int i = 0; i < attributes.length; i++) {
      if (!attributes[i].matches(ctx.xml)) return false;
    }
    for (int i = 0; i < pseudoClasses.length; i++) {
      if (!pseudoClasses[i].matches(ctx)) return false;
    }
    return true;
  }
}

/// A full CSS complex selector composed of [compounds] joined by [combinators].
class SvgCssComplexSelector {
  final List<SvgCssCompoundSelector> compounds;
  final List<SvgCssCombinator> combinators;

  const SvgCssComplexSelector({
    required this.compounds,
    required this.combinators,
  });

  /// Packed specificity score for deterministic sorting `(a << 20) | (b << 10) | c`.
  int get specificity {
    int a = 0, b = 0, c = 0;
    for (final comp in compounds) {
      final (ca, cb, cc) = comp.specificity;
      a += ca;
      b += cb;
      c += cc;
    }
    return (a.clamp(0, 1023) << 20) |
        (b.clamp(0, 1023) << 10) |
        c.clamp(0, 1023);
  }

  /// Matches this selector right-to-left against [ctx].
  bool matches(SvgCssMatchContext ctx) {
    if (compounds.isEmpty) return false;
    return _matchAt(ctx, compounds.length - 1);
  }

  bool _matchAt(SvgCssMatchContext ctx, int idx) {
    if (!compounds[idx].matches(ctx)) return false;
    if (idx == 0) return true;

    final comb = combinators[idx - 1];
    switch (comb) {
      case SvgCssCombinator.child:
        final p = ctx.parent;
        return p != null && _matchAt(p, idx - 1);
      case SvgCssCombinator.descendant:
        var p = ctx.parent;
        while (p != null) {
          if (_matchAt(p, idx - 1)) return true;
          p = p.parent;
        }
        return false;
      case SvgCssCombinator.adjacentSibling:
        final prev = ctx.previousSibling;
        return prev != null && _matchAt(prev, idx - 1);
      case SvgCssCombinator.generalSibling:
        var prev = ctx.previousSibling;
        while (prev != null) {
          if (_matchAt(prev, idx - 1)) return true;
          prev = prev.previousSibling;
        }
        return false;
    }
  }
}

/// Parses CSS Selectors Level 4 strings into [SvgCssComplexSelector].
///
/// Rejects dynamic interactive pseudo-classes (`:hover`, `:active`, `:focus`,
/// `:visited`, `:target`) and pseudo-elements (`::before`, `::after`).
abstract final class SvgCssSelectorParser {
  static SvgCssComplexSelector? parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final compounds = <SvgCssCompoundSelector>[];
    final combinators = <SvgCssCombinator>[];

    int pos = 0;
    final len = s.length;

    while (pos < len) {
      final (comp, nextPos) = _parseCompound(s, pos);
      if (comp == null) return null;
      compounds.add(comp);
      pos = nextPos;

      // Skip whitespace and inspect optional combinator
      final wsStart = pos;
      while (pos < len && _isWs(s.codeUnitAt(pos))) {
        pos++;
      }
      if (pos >= len) break;

      final c = s.codeUnitAt(pos);
      if (c == 0x3E) {
        // '>'
        combinators.add(SvgCssCombinator.child);
        pos++;
      } else if (c == 0x2B) {
        // '+'
        combinators.add(SvgCssCombinator.adjacentSibling);
        pos++;
      } else if (c == 0x7E) {
        // '~'
        combinators.add(SvgCssCombinator.generalSibling);
        pos++;
      } else if (pos > wsStart) {
        combinators.add(SvgCssCombinator.descendant);
      } else {
        return null;
      }

      while (pos < len && _isWs(s.codeUnitAt(pos))) {
        pos++;
      }
    }

    if (compounds.isEmpty || combinators.length != compounds.length - 1) {
      return null;
    }
    return SvgCssComplexSelector(
      compounds: compounds,
      combinators: combinators,
    );
  }

  static (SvgCssCompoundSelector?, int) _parseCompound(String s, int start) {
    int pos = start;
    final len = s.length;
    String? tag;
    String? id;
    final classes = <String>[];
    final attrs = <SvgCssAttrSelector>[];
    final pseudos = <SvgCssPseudoClass>[];
    bool consumedAny = false;

    // Optional type selector or `*`
    if (pos < len) {
      final c = s.codeUnitAt(pos);
      if (c == 0x2A) {
        // '*'
        consumedAny = true;
        pos++;
      } else if (_isIdentStart(c)) {
        final (ident, next) = _readIdent(s, pos);
        tag = ident;
        consumedAny = true;
        pos = next;
      }
    }

    while (pos < len) {
      final c = s.codeUnitAt(pos);
      if (_isWs(c) || c == 0x3E || c == 0x2B || c == 0x7E) break;

      if (c == 0x23) {
        // '#id'
        pos++;
        final (ident, next) = _readIdent(s, pos);
        if (ident.isEmpty) return (null, pos);
        id = ident;
        consumedAny = true;
        pos = next;
      } else if (c == 0x2E) {
        // '.class'
        pos++;
        final (ident, next) = _readIdent(s, pos);
        if (ident.isEmpty) return (null, pos);
        classes.add(ident);
        consumedAny = true;
        pos = next;
      } else if (c == 0x5B) {
        // '[attr...]'
        final close = s.indexOf(']', pos + 1);
        if (close == -1) return (null, pos);
        final parsed = _parseAttrSelector(s.substring(pos + 1, close));
        if (parsed == null) return (null, pos);
        attrs.add(parsed);
        consumedAny = true;
        pos = close + 1;
      } else if (c == 0x3A) {
        // ':pseudo'
        if (pos + 1 < len && s.codeUnitAt(pos + 1) == 0x3A) {
          // Pseudo-elements (`::before`, etc.) unsupported
          return (null, pos);
        }
        pos++;
        final (name, next) = _readIdent(s, pos);
        final lower = name.toLowerCase();
        pos = next;
        String? arg;
        if (pos < len && s.codeUnitAt(pos) == 0x28) {
          final close = _findMatchingParen(s, pos);
          if (close == -1) return (null, pos);
          arg = s.substring(pos + 1, close).trim();
          pos = close + 1;
        }
        final pseudo = _buildPseudo(lower, arg);
        if (pseudo == null) return (null, pos);
        pseudos.add(pseudo);
        consumedAny = true;
      } else {
        return (null, pos);
      }
    }

    if (!consumedAny) return (null, pos);
    return (
      SvgCssCompoundSelector(
        tagName: tag,
        id: id,
        classes: classes,
        attributes: attrs,
        pseudoClasses: pseudos,
      ),
      pos,
    );
  }

  static SvgCssAttrSelector? _parseAttrSelector(String inner) {
    final trimmed = inner.trim();
    if (trimmed.isEmpty) return null;
    final m = RegExp(
      r'^([a-zA-Z0-9_:-]+)\s*(?:([~|^$*]?=)\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s]+))(?:\s+([iIsS]))?)?$',
    ).firstMatch(trimmed);
    if (m == null) return null;
    final name = m.group(1)!;
    final opStr = m.group(2);
    if (opStr == null) return SvgCssAttrSelector(name: name);
    final val = m.group(3) ?? m.group(4) ?? m.group(5) ?? '';
    final ci = m.group(6)?.toLowerCase() == 'i';
    final SvgCssAttrOp op;
    switch (opStr) {
      case '=':
        op = SvgCssAttrOp.equals;
      case '~=':
        op = SvgCssAttrOp.includes;
      case '|=':
        op = SvgCssAttrOp.dashMatch;
      case '^=':
        op = SvgCssAttrOp.prefix;
      case r'$=':
        op = SvgCssAttrOp.suffix;
      case '*=':
        op = SvgCssAttrOp.substring;
      default:
        return null;
    }
    return SvgCssAttrSelector(
      name: name,
      op: op,
      value: val,
      caseInsensitive: ci,
    );
  }

  static SvgCssPseudoClass? _buildPseudo(String name, String? arg) {
    switch (name) {
      case 'root':
        return const SvgCssRootPseudo();
      case 'first-child':
        return const SvgCssFirstChildPseudo();
      case 'last-child':
        return const SvgCssLastChildPseudo();
      case 'only-child':
        return const SvgCssOnlyChildPseudo();
      case 'empty':
        return const SvgCssEmptyPseudo();
      case 'nth-child':
        final ab = _parseAnPlusB(arg ?? '');
        return ab != null ? SvgCssNthChildPseudo(ab.$1, ab.$2) : null;
      case 'nth-last-child':
        final ab = _parseAnPlusB(arg ?? '');
        return ab != null
            ? SvgCssNthChildPseudo(ab.$1, ab.$2, fromLast: true)
            : null;
      case 'not':
        if (arg == null || arg.isEmpty) return null;
        final (inner, end) = _parseCompound(arg, 0);
        if (inner == null || end != arg.length) return null;
        return SvgCssNotPseudo(inner);
      default:
        // Dynamic interactive pseudos (:hover, :active, :focus, etc.) rejected
        return null;
    }
  }

  static (int, int)? _parseAnPlusB(String raw) {
    final s = raw.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (s == 'odd') return (2, 1);
    if (s == 'even') return (2, 0);
    final intOnly = int.tryParse(s);
    if (intOnly != null) return (0, intOnly);
    final m = RegExp(r'^([+-]?\d*)n([+-]\d+)?$').firstMatch(s);
    if (m == null) return null;
    final aStr = m.group(1)!;
    final bStr = m.group(2);
    final a = (aStr.isEmpty || aStr == '+')
        ? 1
        : (aStr == '-' ? -1 : int.tryParse(aStr));
    final b = bStr == null ? 0 : int.tryParse(bStr);
    if (a == null || b == null) return null;
    return (a, b);
  }

  static bool _isWs(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  static bool _isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x2D;

  static bool _isIdentChar(int c) =>
      _isIdentStart(c) || (c >= 0x30 && c <= 0x39);

  static (String, int) _readIdent(String s, int start) {
    int p = start;
    while (p < s.length && _isIdentChar(s.codeUnitAt(p))) {
      p++;
    }
    return (s.substring(start, p), p);
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
}
