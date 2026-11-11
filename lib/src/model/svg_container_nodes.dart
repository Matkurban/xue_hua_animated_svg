import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_document.dart';
import 'svg_element.dart';
import 'svg_geometry_node.dart';
import 'svg_transform.dart';

/// Container `<g>` or root `<svg>` group node.
class SvgGroupNode extends SvgElement {
  @override
  final List<SvgElement> children;

  SvgGroupNode({
    super.tagName = 'g',
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    List<SvgElement>? children,
  }) : children = children ?? <SvgElement>[];

  @override
  bool get shouldCacheStaticPicture => children.isNotEmpty;

  @override
  void initializeGeometry(SvgDocument document) {
    ui.Rect? unionBounds;
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      child.initializeGeometry(document);
      if (child is SvgDefsNode ||
          child is SvgClipPathNode ||
          child.style.displayNone) {
        continue;
      }
      final childBounds = _transformRectByMatrix(
        child.cachedBounds,
        child.baseTransformMatrix,
      );
      if (childBounds.width > 0.0 ||
          childBounds.height > 0.0 ||
          childBounds.left != 0.0 ||
          childBounds.top != 0.0) {
        unionBounds = unionBounds == null
            ? childBounds
            : unionBounds.expandToInclude(childBounds);
      }
    }
    cachedBounds = unionBounds ?? ui.Rect.zero;
    finalizeBaseTransforms(document.viewBox);
  }

  static ui.Rect _transformRectByMatrix(ui.Rect r, Float64List m) {
    if (SvgMatrixMath.isIdentity(m)) return r;
    final x0 = r.left, y0 = r.top;
    final x1 = r.right, y1 = r.bottom;

    final p0x = m[0] * x0 + m[4] * y0 + m[12];
    final p0y = m[1] * x0 + m[5] * y0 + m[13];
    final p1x = m[0] * x1 + m[4] * y0 + m[12];
    final p1y = m[1] * x1 + m[5] * y0 + m[13];
    final p2x = m[0] * x0 + m[4] * y1 + m[12];
    final p2y = m[1] * x0 + m[5] * y1 + m[13];
    final p3x = m[0] * x1 + m[4] * y1 + m[12];
    final p3y = m[1] * x1 + m[5] * y1 + m[13];

    final minX = math.min(math.min(p0x, p1x), math.min(p2x, p3x));
    final maxX = math.max(math.max(p0x, p1x), math.max(p2x, p3x));
    final minY = math.min(math.min(p0y, p1y), math.min(p2y, p3y));
    final maxY = math.max(math.max(p0y, p1y), math.max(p2y, p3y));
    return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      if (hasSelfAnimation) {
        child.style.syncInheritedFromParent(style);
      }
      child.paint(canvas, document);
    }
  }
}

/// `<defs>` container node (not rendered directly; children are referenced by ID).
class SvgDefsNode extends SvgGroupNode {
  SvgDefsNode({super.id, required super.style, super.children})
    : super(tagName: 'defs');

  @override
  bool get shouldCacheStaticPicture => false;

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <defs> are never painted directly
  }
}

/// `<clipPath>` node that precomputes and caches the union `ui.Path` of its children.
class SvgClipPathNode extends SvgGroupNode {
  final ui.Path clipPath = ui.Path();

  SvgClipPathNode({super.id, required super.style, super.children})
    : super(tagName: 'clipPath');

  @override
  void initializeGeometry(SvgDocument document) {
    super.initializeGeometry(document);
    clipPath.reset();
    for (final child in children) {
      if (child is SvgGeometryNode) {
        if (!SvgMatrixMath.isIdentity(child.baseTransformMatrix)) {
          clipPath.addPath(
            child.basePath,
            ui.Offset.zero,
            matrix4: child.baseTransformMatrix,
          );
        } else {
          clipPath.addPath(child.basePath, ui.Offset.zero);
        }
      }
    }
    cachedBounds = clipPath.getBounds();
  }

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <clipPath> is applied via canvas.clipPath()
  }
}

/// `<use>` node that references a `<defs>` element by `href` / `xlink:href` with `(x, y)` offset.
class SvgUseNode extends SvgElement {
  final String? hrefId;
  final double baseX;
  final double baseY;
  double currentX;
  double currentY;

  SvgUseNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.hrefId,
    this.baseX = 0.0,
    this.baseY = 0.0,
  }) : currentX = baseX,
       currentY = baseY,
       super(tagName: 'use');

  @override
  void initializeGeometry(SvgDocument document) {
    final target = hrefId != null ? document.defsById[hrefId!] : null;
    if (target != null) {
      target.initializeGeometry(document);
      cachedBounds = target.cachedBounds.shift(ui.Offset(baseX, baseY));
    } else {
      cachedBounds = ui.Rect.zero;
    }
    finalizeBaseTransforms(document.viewBox);
  }

  @override
  bool propagateAnimationFlags(SvgDocument document) {
    bool animated = super.propagateAnimationFlags(document);
    final target = hrefId != null ? document.defsById[hrefId!] : null;
    if (target != null) {
      if (target.propagateAnimationFlags(document)) {
        animated = true;
      }
    }
    isAnimated = animated;
    return animated;
  }

  @override
  void resetFrameState() {
    super.resetFrameState();
    currentX = baseX;
    currentY = baseY;
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    if (style.visibilityHidden || hrefId == null) return;
    final target = document.defsById[hrefId!];
    if (target == null) return;

    final hasOffset = currentX != 0.0 || currentY != 0.0;
    if (hasOffset) {
      canvas.save();
      canvas.translate(currentX, currentY);
    }
    target.style.syncInheritedFromParent(style);
    target.paint(canvas, document);
    if (hasOffset) {
      canvas.restore();
    }
  }
}
