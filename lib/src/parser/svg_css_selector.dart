import 'svg_xml_tokenizer.dart';

/// Combinator linking two [SvgCssCompoundSelector]s in a complex CSS selector.
/// 连接复合选择器中相邻两个 [SvgCssCompoundSelector] 的 CSS 组合器枚举。
enum SvgCssCombinator {
  /// Descendant combinator (`A B`). 后代组合器（`A B`）。
  descendant,

  /// Direct child combinator (`A > B`). 直接子代组合器（`A > B`）。
  child,

  /// Adjacent sibling combinator (`A + B`). 相邻兄弟组合器（`A + B`）。
  adjacentSibling,

  /// General sibling combinator (`A ~ B`). 通用后续兄弟组合器（`A ~ B`）。
  generalSibling,
}

/// Attribute matching operator in a CSS attribute selector (`[attr op val]`).
/// CSS 属性选择器（`[attr op val]`）的匹配运算符枚举。
enum SvgCssAttrOp {
  /// Attribute presence check (`[attr]`). 属性存在匹配（`[attr]`）。
  exists,

  /// Exact equality (`[attr="val"]`). 精确相等匹配（`=`）。
  equals,

  /// Whitespace-separated word inclusion (`[attr~="val"]`). 空格分词包含匹配（`~=`）。
  includes,

  /// Exact or hyphen-prefixed match (`[attr|="val"]`). 精确或连字符前缀匹配（`|=`）。
  dashMatch,

  /// Prefix match (`[attr^="val"]`). 前缀匹配（`^=`）。
  prefix,

  /// Suffix match (`[attr$="val"]`). 后缀匹配（`$=`）。
  suffix,

  /// Substring match (`[attr*="val"]`). 子串包含匹配（`*=`）。
  substring,
}

/// A single CSS attribute selector such as `[data-role="hero"]` or `[disabled]`.
/// 单个 CSS 属性选择器节点（如 `[data-role="hero"]` 或 `[disabled]`）。
class SvgCssAttrSelector {
  /// Target XML attribute name. 目标 XML 属性名。
  final String name;

  /// Attribute comparison operator. 属性比较运算符。
  final SvgCssAttrOp op;

  /// Optional expected attribute value (`null` for [SvgCssAttrOp.exists]). 可选期望属性值。
  final String? value;

  /// Whether comparison is ASCII case-insensitive (`i` flag). 是否忽略大小写比较。
  final bool caseInsensitive;

  /// Creates an [SvgCssAttrSelector]. 创建一个 [SvgCssAttrSelector] 属性选择器。
  ///
  /// - [name]: Attribute name. 属性名。
  /// - [op]: Matching operator (defaults to [SvgCssAttrOp.exists]). 匹配运算符。
  /// - [value]: Optional expected value. 可选期望值。
  /// - [caseInsensitive]: Whether matching ignores case. 是否忽略大小写。
  const SvgCssAttrSelector({
    required this.name,
    this.op = SvgCssAttrOp.exists,
    this.value,
    this.caseInsensitive = false,
  });

  /// Returns `true` if [xml] satisfies this attribute selector.
  /// 判断元素 [xml] 是否满足该属性选择器。
  ///
  /// - [xml]: Candidate XML element. 待匹配 XML 元素。
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
/// 静态结构伪类匹配器基类（不依赖 JS 与动态交互状态）。
sealed class SvgCssPseudoClass {
  /// Creates an [SvgCssPseudoClass]. 创建一个 [SvgCssPseudoClass] 伪类匹配器。
  const SvgCssPseudoClass();

  /// Returns `true` if [ctx] matches this pseudo-class.
  /// 判断元素上下文 [ctx] 是否匹配当前伪类。
  ///
  /// - [ctx]: Element tree matching context. 元素树匹配上下文。
  bool matches(SvgCssMatchContext ctx);

  /// Specificity contribution `(id, classAttrPseudo, tag)`.
  /// 优先级权重贡献元组 `(ID 数, 类/属性/伪类数, 标签数)`。
  (int, int, int) get specificity => const (0, 1, 0);
}

/// Matches the document root element (`:root`). 匹配文档根元素（`:root`）。
final class SvgCssRootPseudo extends SvgCssPseudoClass {
  /// Creates an [SvgCssRootPseudo]. 创建一个 `:root` 伪类匹配器。
  const SvgCssRootPseudo();
  @override
  bool matches(SvgCssMatchContext ctx) => ctx.parent == null;
}

/// Matches the first child element among its siblings (`:first-child`). 匹配首个子元素（`:first-child`）。
final class SvgCssFirstChildPseudo extends SvgCssPseudoClass {
  /// Creates an [SvgCssFirstChildPseudo]. 创建一个 `:first-child` 伪类匹配器。
  const SvgCssFirstChildPseudo();
  @override
  bool matches(SvgCssMatchContext ctx) => ctx.siblingIndex == 0;
}

/// Matches the last child element among its siblings (`:last-child`). 匹配末尾子元素（`:last-child`）。
final class SvgCssLastChildPseudo extends SvgCssPseudoClass {
  /// Creates an [SvgCssLastChildPseudo]. 创建一个 `:last-child` 伪类匹配器。
  const SvgCssLastChildPseudo();
  @override
  bool matches(SvgCssMatchContext ctx) =>
      ctx.siblingIndex == ctx.siblingCount - 1;
}

/// Matches an element that is the sole child of its parent (`:only-child`). 匹配唯一子元素（`:only-child`）。
final class SvgCssOnlyChildPseudo extends SvgCssPseudoClass {
  /// Creates an [SvgCssOnlyChildPseudo]. 创建一个 `:only-child` 伪类匹配器。
  const SvgCssOnlyChildPseudo();
  @override
  bool matches(SvgCssMatchContext ctx) => ctx.siblingCount == 1;
}

/// Matches an element with no child elements and no text content (`:empty`). 匹配空元素（`:empty`）。
final class SvgCssEmptyPseudo extends SvgCssPseudoClass {
  /// Creates an [SvgCssEmptyPseudo]. 创建一个 `:empty` 伪类匹配器。
  const SvgCssEmptyPseudo();
  @override
  bool matches(SvgCssMatchContext ctx) =>
      ctx.xml.children.isEmpty && ctx.xml.textContent.isEmpty;
}

/// Matches an element by its `An+B` sibling position (`:nth-child` / `:nth-last-child`).
/// 按 `An+B` 兄弟位置公式匹配元素（`:nth-child` / `:nth-last-child`）。
final class SvgCssNthChildPseudo extends SvgCssPseudoClass {
  /// Step coefficient `A` in `An+B`. `An+B` 中的步长系数 `A`。
  final int a;

  /// Offset `B` in `An+B`. `An+B` 中的偏移量 `B`。
  final int b;

  /// When `true`, counts backward from the last sibling (`:nth-last-child`). 是否倒序计数。
  final bool fromLast;

  /// Creates an [SvgCssNthChildPseudo] for `An+B`. 创建一个 `An+B` 位置伪类匹配器。
  ///
  /// - [a]: Step coefficient `A`. 步长系数 `A`。
  /// - [b]: Offset `B`. 偏移量 `B`。
  /// - [fromLast]: Whether to count from the end. 是否倒序计数。
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

/// Negation pseudo-class (`:not(<compound>)`). 取反伪类（`:not(<compound>)`）。
final class SvgCssNotPseudo extends SvgCssPseudoClass {
  /// Negated inner compound selector. 被取反的内部复合选择器。
  final SvgCssCompoundSelector inner;

  /// Creates an [SvgCssNotPseudo] wrapping [inner]. 创建一个包裹 [inner] 的 `:not()` 伪类匹配器。
  ///
  /// - [inner]: Compound selector to negate. 待取反的复合选择器。
  const SvgCssNotPseudo(this.inner);

  @override
  bool matches(SvgCssMatchContext ctx) => !inner.matches(ctx);

  @override
  (int, int, int) get specificity => inner.specificity;
}

/// Immutable tree context for an XML element during compile-time CSS matching.
/// 编译期 CSS 匹配过程中描述 XML 元素树上下文的不可变对象。
class SvgCssMatchContext {
  /// Underlying XML element. 对应的底层 XML 元素。
  final SvgXmlElement xml;

  /// Local element tag name. 元素标签名。
  final String tagName;

  /// Optional XML `id` attribute. 可选 XML `id` 属性。
  final String? id;

  /// Parsed CSS class list. 解析后的 CSS 类名列表。
  final List<String> classes;

  /// Parent element context (`null` for root `<svg>`). 父元素上下文（根节点为 `null`）。
  final SvgCssMatchContext? parent;

  /// Preceding sibling element context (`null` for first child). 前一个兄弟元素上下文。
  final SvgCssMatchContext? previousSibling;

  /// Zero-based index among parent's child elements. 在父元素子节点中的 0 基索引。
  final int siblingIndex;

  /// Total number of sibling elements under the same parent. 同父级下的兄弟元素总数。
  final int siblingCount;

  /// Creates an [SvgCssMatchContext]. 创建一个 [SvgCssMatchContext] 元素匹配上下文。
  ///
  /// - [xml]: Underlying XML element. 底层 XML 元素。
  /// - [tagName]: Local tag name. 标签名。
  /// - [id]: Optional `id`. 可选 `id`。
  /// - [classes]: CSS classes on the element. 元素的 CSS 类名列表。
  /// - [parent]: Optional parent context. 可选父元素上下文。
  /// - [previousSibling]: Optional previous sibling context. 可选前兄弟上下文。
  /// - [siblingIndex]: Zero-based sibling index. 兄弟索引。
  /// - [siblingCount]: Total sibling count. 兄弟总数。
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
/// 不含组合器的单个复合选择器（如 `g#hero.active[data-x]:first-child`）。
class SvgCssCompoundSelector {
  /// Optional tag name (`null` for universal `*` or omitted type). 可选标签名（`*` 或省略时为 `null`）。
  final String? tagName;

  /// Optional `#id` constraint. 可选 `#id` 约束。
  final String? id;

  /// Required `.class` names. 要求匹配的 `.class` 类名列表。
  final List<String> classes;

  /// Attribute selector constraints. 属性选择器约束列表。
  final List<SvgCssAttrSelector> attributes;

  /// Static pseudo-class constraints. 静态伪类约束列表。
  final List<SvgCssPseudoClass> pseudoClasses;

  /// Creates an [SvgCssCompoundSelector]. 创建一个 [SvgCssCompoundSelector] 复合选择器。
  ///
  /// - [tagName]: Optional tag name. 可选标签名。
  /// - [id]: Optional `#id`. 可选 `#id`。
  /// - [classes]: Required class names. 必须包含的类名列表。
  /// - [attributes]: Attribute matchers. 属性匹配器列表。
  /// - [pseudoClasses]: Static pseudo-class matchers. 静态伪类匹配器列表。
  const SvgCssCompoundSelector({
    this.tagName,
    this.id,
    this.classes = const [],
    this.attributes = const [],
    this.pseudoClasses = const [],
  });

  /// W3C Selectors Level 4 specificity tuple `(a: ID, b: class/attr/pseudo, c: type)`.
  /// W3C Selectors Level 4 优先级元组 `(ID 数, 类/属性/伪类数, 标签数)`。
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

  /// Returns `true` if [ctx] satisfies all parts of this compound selector.
  /// 判断元素上下文 [ctx] 是否满足该复合选择器的全部条件。
  ///
  /// - [ctx]: Element matching context. 元素匹配上下文。
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
/// 由多个 [compounds] 通过 [combinators] 连接而成的完整 CSS 复杂选择器。
class SvgCssComplexSelector {
  /// Ordered compound selectors from left (ancestor/earlier sibling) to right (subject).
  /// 从左到右排列的复合选择器列表。
  final List<SvgCssCompoundSelector> compounds;

  /// Combinators between consecutive entries of [compounds] (`length == compounds.length - 1`).
  /// 相邻 [compounds] 之间的组合器列表。
  final List<SvgCssCombinator> combinators;

  /// Creates an [SvgCssComplexSelector]. 创建一个 [SvgCssComplexSelector] 复杂选择器。
  ///
  /// - [compounds]: Compound selector chain. 复合选择器链。
  /// - [combinators]: Combinators linking adjacent compounds. 连接相邻复合选择器的组合器列表。
  const SvgCssComplexSelector({
    required this.compounds,
    required this.combinators,
  });

  /// Packed specificity score for deterministic sorting `(a << 20) | (b << 10) | c`.
  /// 压缩打包后的优先级分数 `(a << 20) | (b << 10) | c`，用于确定性级联排序。
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
  /// 从右向左将本复杂选择器匹配到元素上下文 [ctx]。
  ///
  /// - [ctx]: Candidate element context. 待匹配元素上下文。
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
/// 将 CSS Selectors Level 4 选择器字符串解析为 [SvgCssComplexSelector] 的解析器。
///
/// Rejects dynamic interactive pseudo-classes (`:hover`, `:active`, `:focus`,
/// `:visited`, `:target`) and pseudo-elements (`::before`, `::after`).
/// 拒绝依赖交互状态的动态伪类与伪元素。
abstract final class SvgCssSelectorParser {
  /// Parses a single selector string [raw] into an [SvgCssComplexSelector],
  /// or returns `null` if invalid or unsupported.
  /// 解析单条选择器字符串 [raw] 为 [SvgCssComplexSelector]；若语法无效或不受支持则返回 `null`。
  ///
  /// - [raw]: Raw CSS selector string (without top-level commas). 单条原始 CSS 选择器字符串。
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
