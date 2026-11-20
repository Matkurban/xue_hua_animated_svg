/// Horizontal alignment of a text chunk relative to its anchor point
/// (W3C SVG 1.1 §10.9.1 / SVG 2 `text-anchor`).
enum SvgTextAnchor { start, middle, end }

/// Vertical baseline alignment of text relative to its Y coordinate
/// (W3C SVG 1.1 §10.9.2 / SVG 2 `dominant-baseline` & `alignment-baseline`).
enum SvgDominantBaseline {
  auto,
  alphabetic,
  ideographic,
  hanging,
  mathematical,
  central,
  middle,
  textBeforeEdge,
  textAfterEdge,
}

/// How text is adjusted to fit an explicit `textLength`
/// (W3C SVG 1.1 §10.4 / SVG 2 `lengthAdjust`).
enum SvgLengthAdjust { spacing, spacingAndGlyphs }

/// Whitespace collapsing mode (`xml:space` / CSS `white-space`).
enum SvgWhiteSpace { normal, preserve }

/// Rendering order of `fill` vs `stroke` (SVG 2 `paint-order`).
enum SvgPaintOrder { fillStroke, strokeFill }

/// Case transformation applied to SVG text content (CSS Text Level 3 `text-transform`).
enum SvgTextTransform { none, uppercase, lowercase, capitalize }

/// Inline progression direction of SVG text (CSS Writing Modes / SVG `writing-mode`).
enum SvgWritingMode { horizontalTb, verticalRl, verticalLr }

/// Kind of `baseline-shift` specification (W3C SVG 1.1 §10.9.2).
enum SvgBaselineShiftKind { baseline, sub, superScript, length, percentage }

/// Precompiled `baseline-shift` specification.
class SvgBaselineShift {
  final SvgBaselineShiftKind kind;
  final double value;

  const SvgBaselineShift(this.kind, [this.value = 0.0]);

  static const SvgBaselineShift baseline = SvgBaselineShift(
    SvgBaselineShiftKind.baseline,
  );
  static const SvgBaselineShift sub = SvgBaselineShift(
    SvgBaselineShiftKind.sub,
  );
  static const SvgBaselineShift superScript = SvgBaselineShift(
    SvgBaselineShiftKind.superScript,
  );

  /// Resolves the vertical Y delta in user-space pixels for [fontSize].
  ///
  /// Positive SVG `baseline-shift` moves text UP (negative Y in canvas space).
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
enum SvgTextLengthUnit { pixels, em, rem, percent }

/// Precompiled SVG length value supporting user-space pixels, `em`, `rem`, and `%`.
class SvgTextLength {
  final double value;
  final SvgTextLengthUnit unit;

  const SvgTextLength(this.value, [this.unit = SvgTextLengthUnit.pixels]);

  /// Resolves this length into user-space pixels.
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
