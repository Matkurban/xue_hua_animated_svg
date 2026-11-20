import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' as painting;

import 'svg_document.dart';
import 'svg_element.dart';
import 'svg_style.dart';
import 'svg_text_node.dart';
import 'svg_text_style.dart';

/// W3C SVG 1.1 / SVG 2 compliant text layout and rendering engine.
///
/// Implements:
/// - Whitespace collapsing (`xml:space` / `white-space`) across mixed content
/// - Text chunk splitting on explicit absolute `x`/`y` coordinates
/// - Per-chunk `text-anchor` (`start`, `middle`, `end`) with LTR/RTL support
/// - `dominant-baseline`, `alignment-baseline`, and `baseline-shift` alignment
/// - Cumulative `dx`/`dy` offsets and per-glyph `x`/`y`/`dx`/`dy`/`rotate` lists
/// - `textLength` + `lengthAdjust` (`spacing` and `spacingAndGlyphs`)
/// - `<textPath>` glyph placement along arbitrary `<path>` / geometry curves
/// - Fill, stroke, gradient shaders, blur mask filters, and `paint-order`
abstract final class SvgTextLayoutEngine {
  /// Computes the local bounding box of [textNode] before its own `transform`
  /// is applied (used for `transform-origin` percentages and gradient shaders).
  static ui.Rect computeBounds(SvgTextNode textNode, SvgDocument document) {
    final layout = _buildLayout(textNode, document);
    return layout.bounds;
  }

  /// Renders [textNode] onto [canvas] with [effectiveOpacity].
  static void paint(
    ui.Canvas canvas,
    SvgTextNode textNode,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    // Synchronize inherited styles onto nested <tspan> / <textPath> if animated
    _syncDescendantStyles(textNode);

    final layout = _buildLayout(textNode, document);
    if (layout.glyphPlacements.isEmpty) return;

    final shaderBounds = layout.bounds.isEmpty
        ? textNode.cachedBounds
        : layout.bounds;

    for (final placement in layout.glyphPlacements) {
      if (placement.owner.style.displayNone ||
          placement.owner.style.visibilityHidden) {
        continue;
      }
      _paintPlacement(
        canvas: canvas,
        placement: placement,
        shaderBounds: shaderBounds,
        document: document,
        parentOpacity: effectiveOpacity,
      );
    }
  }

  static void _syncDescendantStyles(SvgElement parent) {
    for (final child in parent.children) {
      child.style.syncInheritedFromParent(parent.style);
      _syncDescendantStyles(child);
    }
  }

  static _ComputedTextLayout _buildLayout(
    SvgTextNode textNode,
    SvgDocument document,
  ) {
    final viewBox = document.viewBox;
    final placements = <_TextPlacement>[];

    // 1. Collect inline runs and separate <textPath> blocks in document order
    final inlineRuns = <_RawTextRun>[];
    final textPaths = <SvgTextPathNode>[];

    _collectContent(
      items: textNode.contentItems,
      owner: textNode,
      xList: _effectiveCoordList(textNode.xList, textNode.animatedX),
      yList: _effectiveCoordList(textNode.yList, textNode.animatedY),
      dxList: _effectiveCoordList(textNode.dxList, textNode.animatedDx),
      dyList: _effectiveCoordList(textNode.dyList, textNode.animatedDy),
      rotateList: textNode.rotateList,
      textLength: textNode.textLength,
      lengthAdjust: textNode.lengthAdjust,
      outInlineRuns: inlineRuns,
      outTextPaths: textPaths,
    );

    // 2. Apply W3C SVG whitespace collapsing across inline runs
    final normalizedRuns = _normalizeWhitespace(inlineRuns);

    // 3. Layout regular inline runs into text chunks
    if (normalizedRuns.isNotEmpty) {
      _layoutInlineRuns(
        runs: normalizedRuns,
        viewBox: viewBox,
        outPlacements: placements,
      );
    }

    // 4. Layout any <textPath> children along their resolved curves
    for (final tp in textPaths) {
      _layoutTextPath(
        textPath: tp,
        document: document,
        outPlacements: placements,
      );
    }

    // 5. Compute union bounding box across all placements
    ui.Rect? bounds;
    for (final p in placements) {
      final rect = p.localBounds;
      if (rect.width > 0.0 || rect.height > 0.0) {
        bounds = bounds == null ? rect : bounds.expandToInclude(rect);
      }
    }

    return _ComputedTextLayout(
      glyphPlacements: placements,
      bounds: bounds ?? ui.Rect.zero,
    );
  }

  static List<SvgTextLength> _effectiveCoordList(
    List<SvgTextLength> baseList,
    double? animatedFirst,
  ) {
    if (animatedFirst == null) return baseList;
    if (baseList.isEmpty) {
      return [SvgTextLength(animatedFirst)];
    }
    return [SvgTextLength(animatedFirst), ...baseList.sublist(1)];
  }

  static void _collectContent({
    required List<SvgTextContentItem> items,
    required SvgElement owner,
    required List<SvgTextLength> xList,
    required List<SvgTextLength> yList,
    required List<SvgTextLength> dxList,
    required List<SvgTextLength> dyList,
    required Float64List rotateList,
    required SvgTextLength? textLength,
    required SvgLengthAdjust lengthAdjust,
    required List<_RawTextRun> outInlineRuns,
    required List<SvgTextPathNode> outTextPaths,
  }) {
    bool isFirstInOwner = true;
    for (final item in items) {
      switch (item) {
        case SvgTextLiteral(:final text):
          if (text.isEmpty) continue;
          outInlineRuns.add(
            _RawTextRun(
              text: text,
              owner: owner,
              xList: isFirstInOwner ? xList : const [],
              yList: isFirstInOwner ? yList : const [],
              dxList: isFirstInOwner ? dxList : const [],
              dyList: isFirstInOwner ? dyList : const [],
              rotateList: isFirstInOwner ? rotateList : Float64List(0),
              textLength: isFirstInOwner ? textLength : null,
              lengthAdjust: lengthAdjust,
            ),
          );
          isFirstInOwner = false;

        case SvgTextSpanNode():
          if (item.style.displayNone) continue;
          final spanX = _effectiveCoordList(item.xList, item.animatedX);
          final spanY = _effectiveCoordList(item.yList, item.animatedY);
          final spanDx = _effectiveCoordList(item.dxList, item.animatedDx);
          final spanDy = _effectiveCoordList(item.dyList, item.animatedDy);
          _collectContent(
            items: item.contentItems,
            owner: item,
            xList: spanX.isNotEmpty
                ? spanX
                : (isFirstInOwner ? xList : const []),
            yList: spanY.isNotEmpty
                ? spanY
                : (isFirstInOwner ? yList : const []),
            dxList: spanDx.isNotEmpty
                ? spanDx
                : (isFirstInOwner ? dxList : const []),
            dyList: spanDy.isNotEmpty
                ? spanDy
                : (isFirstInOwner ? dyList : const []),
            rotateList: item.rotateList.isNotEmpty
                ? item.rotateList
                : (isFirstInOwner ? rotateList : Float64List(0)),
            textLength: item.textLength ?? (isFirstInOwner ? textLength : null),
            lengthAdjust: item.textLength != null
                ? item.lengthAdjust
                : lengthAdjust,
            outInlineRuns: outInlineRuns,
            outTextPaths: outTextPaths,
          );
          isFirstInOwner = false;

        case SvgTextPathNode():
          if (item.style.displayNone) continue;
          outTextPaths.add(item);
          isFirstInOwner = false;
      }
    }
  }

  /// Normalizes whitespace across [runs] per W3C SVG 2 / browser rules.
  static List<_RawTextRun> _normalizeWhitespace(List<_RawTextRun> runs) {
    if (runs.isEmpty) return const [];

    final processed = <_RawTextRun>[];
    bool prevEndedWithSpace = true; // strips leading whitespace on first run

    for (final run in runs) {
      final preserve =
          run.owner.style.currentWhiteSpace == SvgWhiteSpace.preserve;
      final buf = StringBuffer();
      final src = run.text;

      if (preserve) {
        for (int i = 0; i < src.length; i++) {
          final c = src.codeUnitAt(i);
          if (c == 0x0D) {
            if (i + 1 < src.length && src.codeUnitAt(i + 1) == 0x0A) {
              i++;
            }
            buf.write(' ');
          } else if (c == 0x0A || c == 0x09) {
            buf.write(' ');
          } else {
            buf.writeCharCode(c);
          }
        }
        final str = buf.toString();
        if (str.isNotEmpty) {
          prevEndedWithSpace = str.endsWith(' ');
          processed.add(run.withText(str));
        }
      } else {
        for (int i = 0; i < src.length; i++) {
          final c = src.codeUnitAt(i);
          final isWs = c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
          if (isWs) {
            if (!prevEndedWithSpace) {
              buf.write(' ');
              prevEndedWithSpace = true;
            }
          } else {
            buf.writeCharCode(c);
            prevEndedWithSpace = false;
          }
        }
        final str = buf.toString();
        if (str.isNotEmpty) {
          processed.add(run.withText(str));
        }
      }
    }

    // Strip trailing space from the last non-preserve run
    while (processed.isNotEmpty) {
      final last = processed.last;
      if (last.owner.style.currentWhiteSpace == SvgWhiteSpace.preserve) break;
      final trimmedRight = last.text.replaceFirst(RegExp(r' +$'), '');
      if (trimmedRight.isEmpty) {
        processed.removeLast();
      } else {
        if (trimmedRight.length != last.text.length) {
          processed[processed.length - 1] = last.withText(trimmedRight);
        }
        break;
      }
    }

    return processed;
  }

  static void _layoutInlineRuns({
    required List<_RawTextRun> runs,
    required ui.Rect viewBox,
    required List<_TextPlacement> outPlacements,
  }) {
    final chunks = <_TextChunk>[];
    _TextChunk? currentChunk;

    double cursorX = 0.0;
    double cursorY = 0.0;

    for (int rIdx = 0; rIdx < runs.length; rIdx++) {
      final run = runs[rIdx];
      final style = run.owner.style;
      final fontSize = style.currentFontSize;
      if (fontSize <= 0.0 || run.text.isEmpty) continue;

      final needsPerChar =
          run.xList.length > 1 ||
          run.yList.length > 1 ||
          run.dxList.length > 1 ||
          run.dyList.length > 1 ||
          run.rotateList.isNotEmpty;

      if (!needsPerChar) {
        final hasAbsX = run.xList.isNotEmpty;
        final hasAbsY = run.yList.isNotEmpty;

        if (hasAbsX) {
          cursorX = run.xList.first.resolve(
            fontSize: fontSize,
            referenceExtent: viewBox.width,
          );
        }
        if (hasAbsY) {
          cursorY = run.yList.first.resolve(
            fontSize: fontSize,
            referenceExtent: viewBox.height,
          );
        }

        if (currentChunk == null || hasAbsX || hasAbsY) {
          currentChunk = _TextChunk(
            anchor: style.currentTextAnchor,
            direction: style.currentTextDirection,
          );
          chunks.add(currentChunk);
        }

        if (run.dxList.isNotEmpty) {
          cursorX += run.dxList.first.resolve(
            fontSize: fontSize,
            referenceExtent: viewBox.width,
          );
        }
        if (run.dyList.isNotEmpty) {
          cursorY += run.dyList.first.resolve(
            fontSize: fontSize,
            referenceExtent: viewBox.height,
          );
        }

        final measured = _measureText(
          text: run.text,
          style: style,
          extraLetterSpacing: 0.0,
        );

        double extraLetterSpacing = 0.0;
        double scaleX = 1.0;
        double advanceWidth = measured.width;

        if (run.textLength != null && measured.width > 1e-6) {
          final targetLen = run.textLength!.resolve(
            fontSize: fontSize,
            referenceExtent: viewBox.width,
          );
          if (targetLen > 0.0) {
            if (run.lengthAdjust == SvgLengthAdjust.spacingAndGlyphs) {
              scaleX = targetLen / measured.width;
              advanceWidth = targetLen;
            } else if (run.text.length > 1) {
              extraLetterSpacing =
                  (targetLen - measured.width) / (run.text.length - 1);
              advanceWidth = targetLen;
            }
          }
        }

        final baselineY = _computeBaselineOffsetY(style, measured);
        final topLeft = ui.Offset(cursorX, cursorY + baselineY);
        final localBounds = ui.Rect.fromLTWH(
          topLeft.dx,
          topLeft.dy,
          advanceWidth,
          measured.height,
        );

        currentChunk.items.add(
          _TextPlacement(
            text: run.text,
            owner: run.owner,
            position: ui.Offset(cursorX, cursorY),
            topLeft: topLeft,
            width: advanceWidth,
            height: measured.height,
            extraLetterSpacing: extraLetterSpacing,
            scaleX: scaleX,
            rotationRad: 0.0,
            localBounds: localBounds,
          ),
        );
        cursorX += advanceWidth;
      } else {
        // Per-character positioning for x/y/dx/dy/rotate lists
        final chars = run.text.runes.toList();
        for (int cIdx = 0; cIdx < chars.length; cIdx++) {
          final ch = String.fromCharCode(chars[cIdx]);
          final hasAbsX = cIdx < run.xList.length;
          final hasAbsY = cIdx < run.yList.length;

          if (hasAbsX) {
            cursorX = run.xList[cIdx].resolve(
              fontSize: fontSize,
              referenceExtent: viewBox.width,
            );
          }
          if (hasAbsY) {
            cursorY = run.yList[cIdx].resolve(
              fontSize: fontSize,
              referenceExtent: viewBox.height,
            );
          }

          if (currentChunk == null || hasAbsX || hasAbsY) {
            currentChunk = _TextChunk(
              anchor: style.currentTextAnchor,
              direction: style.currentTextDirection,
            );
            chunks.add(currentChunk);
          }

          if (cIdx < run.dxList.length) {
            cursorX += run.dxList[cIdx].resolve(
              fontSize: fontSize,
              referenceExtent: viewBox.width,
            );
          }
          if (cIdx < run.dyList.length) {
            cursorY += run.dyList[cIdx].resolve(
              fontSize: fontSize,
              referenceExtent: viewBox.height,
            );
          }

          double rotDeg = 0.0;
          if (run.rotateList.isNotEmpty) {
            // Per W3C SVG spec: last rotate value applies to all remaining glyphs
            final rotIdx = math.min(cIdx, run.rotateList.length - 1);
            rotDeg = run.rotateList[rotIdx];
          }

          final measured = _measureText(
            text: ch,
            style: style,
            extraLetterSpacing: 0.0,
          );
          final baselineY = _computeBaselineOffsetY(style, measured);
          final topLeft = ui.Offset(cursorX, cursorY + baselineY);
          final localBounds = ui.Rect.fromLTWH(
            topLeft.dx,
            topLeft.dy,
            measured.width,
            measured.height,
          );

          currentChunk.items.add(
            _TextPlacement(
              text: ch,
              owner: run.owner,
              position: ui.Offset(cursorX, cursorY),
              topLeft: topLeft,
              width: measured.width,
              height: measured.height,
              extraLetterSpacing: 0.0,
              scaleX: 1.0,
              rotationRad: rotDeg * (math.pi / 180.0),
              localBounds: localBounds,
            ),
          );
          cursorX += measured.width;
        }
      }
    }

    // Apply per-chunk text-anchor alignment and emit final placements
    for (final chunk in chunks) {
      if (chunk.items.isEmpty) continue;
      double minX = chunk.items.first.position.dx;
      double maxX = chunk.items.first.position.dx + chunk.items.first.width;
      for (int i = 1; i < chunk.items.length; i++) {
        final item = chunk.items[i];
        if (item.position.dx < minX) minX = item.position.dx;
        final right = item.position.dx + item.width;
        if (right > maxX) maxX = right;
      }
      final chunkWidth = maxX - minX;
      final shiftX = _computeTextAnchorShift(
        anchor: chunk.anchor,
        direction: chunk.direction,
        chunkWidth: chunkWidth,
      );

      for (final item in chunk.items) {
        outPlacements.add(shiftX == 0.0 ? item : item.shiftX(shiftX));
      }
    }
  }

  static void _layoutTextPath({
    required SvgTextPathNode textPath,
    required SvgDocument document,
    required List<_TextPlacement> outPlacements,
  }) {
    final metrics = textPath.resolvePathMetrics(document);
    if (metrics == null ||
        metrics.isEmpty ||
        textPath.cachedTotalPathLength <= 0.0) {
      return;
    }

    final nestedRuns = <_RawTextRun>[];
    final nestedPaths = <SvgTextPathNode>[];
    _collectContent(
      items: textPath.contentItems,
      owner: textPath,
      xList: const [],
      yList: const [],
      dxList: const [],
      dyList: const [],
      rotateList: Float64List(0),
      textLength: textPath.textLength,
      lengthAdjust: textPath.lengthAdjust,
      outInlineRuns: nestedRuns,
      outTextPaths: nestedPaths,
    );

    final runs = _normalizeWhitespace(nestedRuns);
    if (runs.isEmpty) return;

    // Pre-measure every character to compute total advance for text-anchor
    final glyphs = <_PathGlyph>[];
    double totalAdvance = 0.0;

    for (final run in runs) {
      final style = run.owner.style;
      if (style.currentFontSize <= 0.0) continue;
      for (final rune in run.text.runes) {
        final ch = String.fromCharCode(rune);
        final measured = _measureText(
          text: ch,
          style: style,
          extraLetterSpacing: 0.0,
        );
        final baselineY = _computeBaselineOffsetY(style, measured);
        glyphs.add(
          _PathGlyph(
            text: ch,
            owner: run.owner,
            width: measured.width,
            height: measured.height,
            baselineOffsetY: baselineY,
          ),
        );
        totalAdvance += measured.width;
      }
    }

    if (glyphs.isEmpty) return;

    final totalPathLen = textPath.cachedTotalPathLength;
    double startDist =
        textPath.startOffset?.resolve(
          fontSize: textPath.style.currentFontSize,
          referenceExtent: totalPathLen,
        ) ??
        0.0;

    startDist += _computeTextAnchorShift(
      anchor: textPath.style.currentTextAnchor,
      direction: textPath.style.currentTextDirection,
      chunkWidth: totalAdvance,
    );

    // Optional textLength spacing along path
    double extraSpacing = 0.0;
    if (textPath.textLength != null && glyphs.length > 1) {
      final targetLen = textPath.textLength!.resolve(
        fontSize: textPath.style.currentFontSize,
        referenceExtent: totalPathLen,
      );
      if (targetLen > 0.0) {
        extraSpacing = (targetLen - totalAdvance) / (glyphs.length - 1);
      }
    }

    double dist = startDist;
    for (final g in glyphs) {
      final midDist = dist + g.width * 0.5;
      dist += g.width + extraSpacing;
      if (midDist < 0.0 || midDist > totalPathLen) continue;

      final sampleDist = textPath.sideRight
          ? (totalPathLen - midDist)
          : midDist;
      final tangent = _samplePathTangent(metrics, sampleDist);
      if (tangent == null) continue;

      final pos = tangent.position;
      final vec = tangent.vector;
      final angle =
          math.atan2(vec.dy, vec.dx) + (textPath.sideRight ? math.pi : 0.0);

      final topLeft = ui.Offset(
        pos.dx - g.width * 0.5,
        pos.dy + g.baselineOffsetY,
      );
      final localBounds = ui.Rect.fromCenter(
        center: pos,
        width: math.max(g.width, g.height),
        height: math.max(g.width, g.height),
      );

      outPlacements.add(
        _TextPlacement(
          text: g.text,
          owner: g.owner,
          position: pos,
          topLeft: topLeft,
          width: g.width,
          height: g.height,
          extraLetterSpacing: 0.0,
          scaleX: 1.0,
          rotationRad: angle,
          localBounds: localBounds,
        ),
      );
    }
  }

  static ui.Tangent? _samplePathTangent(
    List<ui.PathMetric> metrics,
    double distance,
  ) {
    double remaining = distance;
    for (final metric in metrics) {
      if (remaining <= metric.length) {
        return metric.getTangentForOffset(remaining.clamp(0.0, metric.length));
      }
      remaining -= metric.length;
    }
    final last = metrics.last;
    return last.getTangentForOffset(last.length);
  }

  static double _computeTextAnchorShift({
    required SvgTextAnchor anchor,
    required ui.TextDirection direction,
    required double chunkWidth,
  }) {
    if (direction == ui.TextDirection.rtl) {
      switch (anchor) {
        case SvgTextAnchor.start:
          return -chunkWidth;
        case SvgTextAnchor.middle:
          return -chunkWidth * 0.5;
        case SvgTextAnchor.end:
          return 0.0;
      }
    }
    switch (anchor) {
      case SvgTextAnchor.start:
        return 0.0;
      case SvgTextAnchor.middle:
        return -chunkWidth * 0.5;
      case SvgTextAnchor.end:
        return -chunkWidth;
    }
  }

  static _MeasuredTextMetrics _measureText({
    required String text,
    required SvgStyle style,
    required double extraLetterSpacing,
  }) {
    final painter = painting.TextPainter(
      text: painting.TextSpan(
        text: text,
        style: _buildFlutterTextStyle(
          style: style,
          foreground: null,
          extraLetterSpacing: extraLetterSpacing,
        ),
      ),
      textDirection: style.currentTextDirection,
    )..layout();

    final width = painter.width;
    final height = painter.height;
    final alphabetic = painter.computeDistanceToActualBaseline(
      ui.TextBaseline.alphabetic,
    );
    final lineMetrics = painter.computeLineMetrics();
    final ascent = lineMetrics.isNotEmpty
        ? lineMetrics.first.ascent
        : alphabetic;
    final descent = lineMetrics.isNotEmpty
        ? lineMetrics.first.descent
        : (height - alphabetic).clamp(0.0, height);

    painter.dispose();
    return _MeasuredTextMetrics(
      width: width,
      height: height,
      alphabeticBaseline: alphabetic,
      ascent: ascent,
      descent: descent,
    );
  }

  /// Computes Y offset from SVG baseline anchor `y` to Flutter `TextPainter` top-left.
  static double _computeBaselineOffsetY(
    SvgStyle style,
    _MeasuredTextMetrics m,
  ) {
    final baseline =
        style.currentAlignmentBaseline ?? style.currentDominantBaseline;
    double offset;
    switch (baseline) {
      case SvgDominantBaseline.auto:
      case SvgDominantBaseline.alphabetic:
        offset = -m.alphabeticBaseline;
      case SvgDominantBaseline.ideographic:
        offset = -(m.alphabeticBaseline + m.descent * 0.5);
      case SvgDominantBaseline.hanging:
        offset = -(m.alphabeticBaseline - m.ascent * 0.8);
      case SvgDominantBaseline.mathematical:
        offset = -(m.alphabeticBaseline - m.ascent * 0.5);
      case SvgDominantBaseline.middle:
        // Per W3C SVG 1.1 §10.9.2: middle = alphabetic baseline + 0.5 * x-height
        offset = -(m.alphabeticBaseline - m.ascent * 0.35);
      case SvgDominantBaseline.central:
        offset = -m.height * 0.5;
      case SvgDominantBaseline.textBeforeEdge:
        offset = 0.0;
      case SvgDominantBaseline.textAfterEdge:
        offset = -m.height;
    }
    return offset +
        style.currentBaselineShift.resolveOffsetY(style.currentFontSize);
  }

  static painting.TextStyle _buildFlutterTextStyle({
    required SvgStyle style,
    required ui.Paint? foreground,
    required double extraLetterSpacing,
  }) {
    final baseLetterSpacing = style.currentLetterSpacing ?? 0.0;
    final combinedLetterSpacing = baseLetterSpacing + extraLetterSpacing;

    return painting.TextStyle(
      fontFamily: style.currentFontFamily,
      fontFamilyFallback: style.currentFontFamilyFallback,
      fontSize: style.currentFontSize,
      fontWeight: style.currentFontWeight,
      fontStyle: style.currentFontStyle,
      letterSpacing: combinedLetterSpacing != 0.0
          ? combinedLetterSpacing
          : null,
      wordSpacing: style.currentWordSpacing,
      decoration: style.currentTextDecoration,
      fontFeatures: style.currentFontVariantSmallCaps
          ? const [ui.FontFeature.enable('smcp')]
          : null,
      foreground: foreground,
      color: foreground == null ? const ui.Color(0xFF000000) : null,
    );
  }

  static void _paintPlacement({
    required ui.Canvas canvas,
    required _TextPlacement placement,
    required ui.Rect shaderBounds,
    required SvgDocument document,
    required double parentOpacity,
  }) {
    final owner = placement.owner;
    final style = owner.style;
    final effectiveOpacity = owner is SvgTextNode
        ? parentOpacity
        : (parentOpacity * style.currentOpacity).clamp(0.0, 1.0);
    if (effectiveOpacity <= 0.0) return;

    final maskFilter = owner.resolveMaskFilter();

    // Prepare fill paint if visible
    ui.Paint? fillPaint;
    final fillServer = style.resolvedFill;
    final fillAlpha = (style.currentFillOpacity * effectiveOpacity).clamp(
      0.0,
      1.0,
    );
    if (fillServer.isVisible && fillAlpha > 0.0) {
      fillPaint = owner.cachedFillPaint..maskFilter = maskFilter;
      if (fillServer.type == SvgPaintType.gradient &&
          fillServer.gradientId != null) {
        final serverId = fillServer.gradientId!;
        final grad = document.gradientsById[serverId];
        final pat = document.patternsById[serverId];
        fillPaint.shader =
            grad?.createShader(shaderBounds) ??
            pat?.createShader(shaderBounds, document);
        fillPaint.color = ui.Color.fromARGB(
          (fillAlpha * 255.0).round().clamp(0, 255),
          255,
          255,
          255,
        );
      } else {
        fillPaint.shader = null;
        final c = style.currentFillColor;
        fillPaint.color = c.withValues(
          alpha: (c.a * fillAlpha).clamp(0.0, 1.0),
        );
      }
    }

    // Prepare stroke paint if visible
    ui.Paint? strokePaint;
    final strokeServer = style.resolvedStroke;
    final strokeWidth = style.currentStrokeWidth;
    final strokeAlpha = (style.currentStrokeOpacity * effectiveOpacity).clamp(
      0.0,
      1.0,
    );
    if (strokeServer.isVisible && strokeWidth > 0.0 && strokeAlpha > 0.0) {
      strokePaint = owner.cachedStrokePaint
        ..strokeWidth = strokeWidth
        ..strokeCap = style.currentStrokeCap
        ..strokeJoin = style.currentStrokeJoin
        ..strokeMiterLimit = style.currentStrokeMiterLimit
        ..maskFilter = maskFilter;
      if (strokeServer.type == SvgPaintType.gradient &&
          strokeServer.gradientId != null) {
        final serverId = strokeServer.gradientId!;
        final grad = document.gradientsById[serverId];
        final pat = document.patternsById[serverId];
        strokePaint.shader =
            grad?.createShader(shaderBounds) ??
            pat?.createShader(shaderBounds, document);
        strokePaint.color = ui.Color.fromARGB(
          (strokeAlpha * 255.0).round().clamp(0, 255),
          255,
          255,
          255,
        );
      } else {
        strokePaint.shader = null;
        final c = style.currentStrokeColor;
        strokePaint.color = c.withValues(
          alpha: (c.a * strokeAlpha).clamp(0.0, 1.0),
        );
      }
    }

    if (fillPaint == null && strokePaint == null) return;

    final needsLocalTransform =
        placement.rotationRad != 0.0 || placement.scaleX != 1.0;
    if (needsLocalTransform) {
      canvas.save();
      canvas.translate(placement.position.dx, placement.position.dy);
      if (placement.rotationRad != 0.0) {
        canvas.rotate(placement.rotationRad);
      }
      if (placement.scaleX != 1.0) {
        canvas.scale(placement.scaleX, 1.0);
      }
      canvas.translate(-placement.position.dx, -placement.position.dy);
    }

    if (style.currentPaintOrder == SvgPaintOrder.strokeFill) {
      if (strokePaint != null) {
        _drawTextPass(canvas, placement, style, strokePaint);
      }
      if (fillPaint != null) {
        _drawTextPass(canvas, placement, style, fillPaint);
      }
    } else {
      if (fillPaint != null) {
        _drawTextPass(canvas, placement, style, fillPaint);
      }
      if (strokePaint != null) {
        _drawTextPass(canvas, placement, style, strokePaint);
      }
    }

    if (needsLocalTransform) {
      canvas.restore();
    }
  }

  static void _drawTextPass(
    ui.Canvas canvas,
    _TextPlacement placement,
    SvgStyle style,
    ui.Paint paint,
  ) {
    final painter = painting.TextPainter(
      text: painting.TextSpan(
        text: placement.text,
        style: _buildFlutterTextStyle(
          style: style,
          foreground: paint,
          extraLetterSpacing: placement.extraLetterSpacing,
        ),
      ),
      textDirection: style.currentTextDirection,
    )..layout();
    painter.paint(canvas, placement.topLeft);
    painter.dispose();
  }
}

class _RawTextRun {
  final String text;
  final SvgElement owner;
  final List<SvgTextLength> xList;
  final List<SvgTextLength> yList;
  final List<SvgTextLength> dxList;
  final List<SvgTextLength> dyList;
  final Float64List rotateList;
  final SvgTextLength? textLength;
  final SvgLengthAdjust lengthAdjust;

  const _RawTextRun({
    required this.text,
    required this.owner,
    required this.xList,
    required this.yList,
    required this.dxList,
    required this.dyList,
    required this.rotateList,
    required this.textLength,
    required this.lengthAdjust,
  });

  _RawTextRun withText(String newText) => _RawTextRun(
    text: newText,
    owner: owner,
    xList: xList,
    yList: yList,
    dxList: dxList,
    dyList: dyList,
    rotateList: rotateList,
    textLength: textLength,
    lengthAdjust: lengthAdjust,
  );
}

class _TextChunk {
  final SvgTextAnchor anchor;
  final ui.TextDirection direction;
  final List<_TextPlacement> items = <_TextPlacement>[];

  _TextChunk({required this.anchor, required this.direction});
}

class _PathGlyph {
  final String text;
  final SvgElement owner;
  final double width;
  final double height;
  final double baselineOffsetY;

  const _PathGlyph({
    required this.text,
    required this.owner,
    required this.width,
    required this.height,
    required this.baselineOffsetY,
  });
}

class _MeasuredTextMetrics {
  final double width;
  final double height;
  final double alphabeticBaseline;
  final double ascent;
  final double descent;

  const _MeasuredTextMetrics({
    required this.width,
    required this.height,
    required this.alphabeticBaseline,
    required this.ascent,
    required this.descent,
  });
}

class _TextPlacement {
  final String text;
  final SvgElement owner;
  final ui.Offset position;
  final ui.Offset topLeft;
  final double width;
  final double height;
  final double extraLetterSpacing;
  final double scaleX;
  final double rotationRad;
  final ui.Rect localBounds;

  const _TextPlacement({
    required this.text,
    required this.owner,
    required this.position,
    required this.topLeft,
    required this.width,
    required this.height,
    required this.extraLetterSpacing,
    required this.scaleX,
    required this.rotationRad,
    required this.localBounds,
  });

  _TextPlacement shiftX(double dx) => _TextPlacement(
    text: text,
    owner: owner,
    position: position.translate(dx, 0.0),
    topLeft: topLeft.translate(dx, 0.0),
    width: width,
    height: height,
    extraLetterSpacing: extraLetterSpacing,
    scaleX: scaleX,
    rotationRad: rotationRad,
    localBounds: localBounds.shift(ui.Offset(dx, 0.0)),
  );
}

class _ComputedTextLayout {
  final List<_TextPlacement> glyphPlacements;
  final ui.Rect bounds;

  const _ComputedTextLayout({
    required this.glyphPlacements,
    required this.bounds,
  });
}
