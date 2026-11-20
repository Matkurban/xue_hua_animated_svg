/// Horizontal alignment of a text chunk relative to its anchor point
/// (W3C SVG 1.1 §10.9.1 / SVG 2 `text-anchor`).
/// 文本块相对锚点的水平对齐方式枚举（`text-anchor`）。
enum SvgTextAnchor {
  /// Aligns the start edge of the text chunk to the anchor (`start`). 起始端对齐。
  start,

  /// Centers the text chunk on the anchor (`middle`). 居中对齐。
  middle,

  /// Aligns the end edge of the text chunk to the anchor (`end`). 末端对齐。
  end,
}

/// Vertical baseline alignment of text relative to its Y coordinate
/// (W3C SVG 1.1 §10.9.2 / SVG 2 `dominant-baseline` & `alignment-baseline`).
/// 文本相对 Y 坐标的垂直基线对齐模式枚举。
enum SvgDominantBaseline {
  /// Automatic script-dependent baseline (`auto`). 自动基线。
  auto,

  /// Latin alphabetic baseline (`alphabetic`). 拉丁字母基线。
  alphabetic,

  /// CJK ideographic under-side baseline (`ideographic`). 汉字表意基线。
  ideographic,

  /// Indic hanging top baseline (`hanging`). 悬挂顶基线。
  hanging,

  /// Mathematical center baseline (`mathematical`). 数学中心基线。
  mathematical,

  /// Geometric vertical center (`central`). 几何垂直居中基线。
  central,

  /// Middle of x-height above alphabetic baseline (`middle`). x 高度中线。
  middle,

  /// Top edge of the text box (`text-before-edge`). 文本盒顶边。
  textBeforeEdge,

  /// Bottom edge of the text box (`text-after-edge`). 文本盒底边。
  textAfterEdge,
}

/// How text is adjusted to fit an explicit `textLength`
/// (W3C SVG 1.1 §10.4 / SVG 2 `lengthAdjust`).
/// 文本适配显式 `textLength` 的拉伸调整方式枚举。
enum SvgLengthAdjust {
  /// Adjusts inter-glyph spacing only (`spacing`). 仅调整字间距。
  spacing,

  /// Scales both spacing and glyph geometry (`spacingAndGlyphs`). 同时缩放间距与字形。
  spacingAndGlyphs,
}

/// Whitespace collapsing mode (`xml:space` / CSS `white-space`).
/// 空白字符折叠模式枚举（`xml:space` / `white-space`）。
enum SvgWhiteSpace {
  /// Collapses consecutive whitespace and trims leading/trailing spaces (`normal` / `default`). 折叠空白。
  normal,

  /// Preserves whitespace characters as spaces (`preserve` / `pre`). 保留空白。
  preserve,
}

/// Rendering order of `fill` vs `stroke` (SVG 2 `paint-order`).
/// 填充与描边的绘制顺序枚举（`paint-order`）。
enum SvgPaintOrder {
  /// Paints fill first, then stroke (`fill stroke`). 先填充后描边。
  fillStroke,

  /// Paints stroke first, then fill (`stroke fill`). 先描边后填充。
  strokeFill,
}

/// Case transformation applied to SVG text content (CSS Text Level 3 `text-transform`).
/// 文本大小写变换模式枚举（CSS Text Level 3 `text-transform`）。
enum SvgTextTransform {
  /// No case transformation (`none`). 不变换。
  none,

  /// Converts all characters to uppercase (`uppercase`). 全部转为大写。
  uppercase,

  /// Converts all characters to lowercase (`lowercase`). 全部转为小写。
  lowercase,

  /// Capitalizes the first character of each word (`capitalize`). 每个单词首字母大写。
  capitalize,
}

/// Inline progression direction of SVG text (CSS Writing Modes / SVG `writing-mode`).
/// 文本书写方向枚举（水平或竖排 `writing-mode`）。
enum SvgWritingMode {
  /// Standard horizontal left-to-right / top-to-bottom (`horizontal-tb`). 标准横排。
  horizontalTb,

  /// Vertical top-to-bottom progression (`vertical-rl` / `tb` / `tb-rl`). 竖排（右向左列进）。
  verticalRl,

  /// Vertical top-to-bottom progression (`vertical-lr`). 竖排（左向右列进）。
  verticalLr,
}

/// Kind of `baseline-shift` specification (W3C SVG 1.1 §10.9.2).
/// `baseline-shift` 基线偏移类型枚举。
enum SvgBaselineShiftKind {
  /// Zero shift (`baseline`). 无偏移。
  baseline,

  /// Subscript shift downward (`sub`). 下标偏移。
  sub,

  /// Superscript shift upward (`super`). 上标偏移。
  superScript,

  /// Explicit user-space length offset. 显式像素长度偏移。
  length,

  /// Percentage of current `font-size`. 相对当前字号的百分比偏移。
  percentage,
}

/// Precompiled `baseline-shift` specification.
/// 预编译的 `baseline-shift` 基线偏移配置。
class SvgBaselineShift {
  /// Shift mode discriminator. 基线偏移类型。
  final SvgBaselineShiftKind kind;

  /// Numeric magnitude for [SvgBaselineShiftKind.length] or [SvgBaselineShiftKind.percentage]. 偏移数值。
  final double value;

  /// Creates an [SvgBaselineShift]. 创建一个 [SvgBaselineShift] 基线偏移对象。
  ///
  /// - [kind]: Baseline shift mode. 偏移类型。
  /// - [value]: Optional numeric value (defaults to `0.0`). 可选偏移量。
  const SvgBaselineShift(this.kind, [this.value = 0.0]);

  /// Default zero baseline shift (`baseline`). 默认零偏移。
  static const SvgBaselineShift baseline = SvgBaselineShift(
    SvgBaselineShiftKind.baseline,
  );

  /// Standard subscript shift (`sub`). 标准下标偏移。
  static const SvgBaselineShift sub = SvgBaselineShift(
    SvgBaselineShiftKind.sub,
  );

  /// Standard superscript shift (`super`). 标准上标偏移。
  static const SvgBaselineShift superScript = SvgBaselineShift(
    SvgBaselineShiftKind.superScript,
  );

  /// Resolves the vertical Y delta in user-space pixels for [fontSize].
  /// 根据当前字号 [fontSize] 解析用户空间中的垂直 Y 偏移量（SVG 正值向上移）。
  ///
  /// - [fontSize]: Resolved current font size in pixels. 当前已解析字号（像素）。
  double resolveOffsetY(double fontSize) {
    switch (kind) {
      case SvgBaselineShiftKind.baseline:
        return 0.0;
      case SvgBaselineShiftKind.sub:
        return fontSize * 0.33;
      case SvgBaselineShiftKind.superScript:
        return -fontSize * 0.4;
      case SvgBaselineShiftKind.length:
        return -value;
      case SvgBaselineShiftKind.percentage:
        return -(value * fontSize);
    }
  }
}

/// Unit for an SVG text coordinate or font-size length value.
/// SVG 文本坐标或字号长度单位枚举。
enum SvgTextLengthUnit {
  /// User-space pixels (`px` or unitless). 用户空间像素。
  pixels,

  /// Relative to the element's `font-size` (`em`). 相对当前字号倍数。
  em,

  /// Relative to the root `font-size` (`rem`). 相对根字号倍数。
  rem,

  /// Percentage of reference extent (`%`). 相对参考尺寸的百分比。
  percent,
}

/// Precompiled SVG length value supporting user-space pixels, `em`, `rem`, and `%`.
/// 预编译的 SVG 文本长度值对象，支持像素、`em`、`rem` 与 `%`。
class SvgTextLength {
  /// Numeric magnitude (normalized `0..1` when [unit] is [SvgTextLengthUnit.percent]). 数值大小。
  final double value;

  /// Length unit. 长度单位。
  final SvgTextLengthUnit unit;

  /// Creates an [SvgTextLength]. 创建一个 [SvgTextLength] 文本长度对象。
  ///
  /// - [value]: Numeric value. 数值。
  /// - [unit]: Unit type (defaults to [SvgTextLengthUnit.pixels]). 单位类型。
  const SvgTextLength(this.value, [this.unit = SvgTextLengthUnit.pixels]);

  /// Resolves this length into user-space pixels.
  /// 将当前长度解析为用户空间像素值。
  ///
  /// - [fontSize]: Current element font size for `em`. 当前字号。
  /// - [rootFontSize]: Root font size for `rem` (defaults to `16.0`). 根字号。
  /// - [referenceExtent]: Reference axis extent for `%`. 百分比参考尺寸。
  double resolve({
    required double fontSize,
    double rootFontSize = 16.0,
    double referenceExtent = 0.0,
  }) {
    switch (unit) {
      case SvgTextLengthUnit.pixels:
        return value;
      case SvgTextLengthUnit.em:
        return value * fontSize;
      case SvgTextLengthUnit.rem:
        return value * rootFontSize;
      case SvgTextLengthUnit.percent:
        return value * referenceExtent;
    }
  }
}
