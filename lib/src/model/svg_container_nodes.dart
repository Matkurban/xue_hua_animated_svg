import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_document.dart';
import 'svg_element.dart';
import 'svg_geometry_node.dart';
import 'svg_gradient.dart';
import 'svg_transform.dart';
import 'svg_viewport_nodes.dart';

/// Container `<g>` or root `<svg>` group node.
/// 容器分组节点（`<g>` 或根 `<svg>`）。
class SvgGroupNode extends SvgElement {
  /// Direct child elements in paint order. 按绘制顺序排列的直接子元素列表。
  @override
  final List<SvgElement> children;

  /// Creates an [SvgGroupNode]. 创建一个 [SvgGroupNode] 分组节点。
  ///
  /// - [tagName]: Tag name (defaults to `'g'`). 标签名。
  /// - [id]: Optional `id`. 可选 `id`。
  /// - [classes]: CSS class list. CSS 类名列表。
  /// - [style]: Node style. 节点样式。
  /// - [baseTransformOps]: Static transform ops. 静态变换指令。
  /// - [children]: Optional initial child list. 可选初始子节点列表。
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
          child is SvgSymbolNode ||
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
/// `<defs>` 定义容器节点（不直接绘制，仅通过 ID 被引用）。
class SvgDefsNode extends SvgGroupNode {
  /// Creates an [SvgDefsNode]. 创建一个 [SvgDefsNode] 定义容器。
  SvgDefsNode({super.id, required super.style, super.children})
    : super(tagName: 'defs');

  @override
  bool get shouldCacheStaticPicture => false;

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <defs> are never painted directly
  }
}

/// `<clipPath>` node supporting `userSpaceOnUse`, `objectBoundingBox`, `<use>`
/// children, and dynamically animated clipping geometry.
/// `<clipPath>` 裁剪路径节点，支持坐标单位、`<use>` 子节点及动态动画裁剪。
class SvgClipPathNode extends SvgGroupNode {
  /// Coordinate space unit (`userSpaceOnUse` or `objectBoundingBox`). 裁剪坐标空间单位。
  final SvgGradientUnits clipPathUnits;

  /// Precompiled union clip [ui.Path]. 预编译合并后的裁剪路径。
  final ui.Path clipPath = ui.Path();

  final Float64List _bboxMatrix = SvgMatrixMath.createIdentity();

  /// Creates an [SvgClipPathNode]. 创建一个 [SvgClipPathNode] 裁剪路径节点。
  ///
  /// - [id]: Clip path `id`. 裁剪路径 ID。
  /// - [style]: Node style. 节点样式。
  /// - [children]: Clipping geometry children. 裁剪几何子节点。
  /// - [clipPathUnits]: Coordinate units (`userSpaceOnUse` by default). 坐标单位。
  SvgClipPathNode({
    super.id,
    required super.style,
    super.children,
    this.clipPathUnits = SvgGradientUnits.userSpaceOnUse,
  }) : super(tagName: 'clipPath');

  @override
  bool get shouldCacheStaticPicture => false;

  void _rebuildClipPath(SvgDocument document) {
    clipPath.reset();
    for (final child in children) {
      _appendChildToClip(child, document, ui.Offset.zero);
    }
  }

  void _appendChildToClip(
    SvgElement child,
    SvgDocument document,
    ui.Offset extraOffset,
  ) {
    if (child.style.displayNone) return;
    if (child is SvgGeometryNode) {
      child.refreshGeometryIfNeeded();
      final matrix = child.transformMatrix;
      if (!SvgMatrixMath.isIdentity(matrix)) {
        clipPath.addPath(child.basePath, extraOffset, matrix4: matrix);
      } else {
        clipPath.addPath(child.basePath, extraOffset);
      }
    } else if (child is SvgUseNode && child.hrefId != null) {
      final target =
          document.defsById[child.hrefId!] ??
          document.elementsById[child.hrefId!];
      if (target != null && !identical(target, child)) {
        _appendChildToClip(
          target,
          document,
          extraOffset.translate(child.currentX, child.currentY),
        );
      }
    }
  }

  /// Resolves the active clipping [ui.Path] in target user space.
  ui.Path resolveClipPath(SvgDocument document, ui.Rect targetBounds) {
    if (isAnimated) {
      _rebuildClipPath(document);
    }
    if (clipPathUnits == SvgGradientUnits.objectBoundingBox) {
      SvgMatrixMath.resetToIdentity(_bboxMatrix);
      SvgMatrixMath.translateInPlace(
        _bboxMatrix,
        targetBounds.left,
        targetBounds.top,
      );
      SvgMatrixMath.scaleInPlace(
        _bboxMatrix,
        targetBounds.width,
        targetBounds.height,
      );
      return clipPath.transform(_bboxMatrix);
    }
    return clipPath;
  }

  @override
  void initializeGeometry(SvgDocument document) {
    super.initializeGeometry(document);
    _rebuildClipPath(document);
    cachedBounds = clipPath.getBounds();
  }

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // <clipPath> is applied via canvas.clipPath()
  }
}

/// `<use>` node that references a `<defs>` or scene element by `href` / `xlink:href`
/// with `(x, y)` offset, optional `(width, height)` viewport sizing, and cycle protection.
/// `<use>` 引用实例化节点，支持偏移、视口缩放、深层样式隔离与循环引用保护。
class SvgUseNode extends SvgElement {
  static const int _maxUseDepth = 16;
  static int _activeUseDepth = 0;

  /// Referenced target element `id` (without `#`). 被引用目标元素的 ID（不含 `#`）。
  final String? hrefId;

  /// Static base X offset. 静态基础 X 偏移。
  final double baseX;

  /// Static base Y offset. 静态基础 Y 偏移。
  final double baseY;

  /// Optional static width override. 可选静态宽度覆盖。
  final double? baseWidth;

  /// Optional static height override. 可选静态高度覆盖。
  final double? baseHeight;

  /// Active runtime X offset. 运行时活跃 X 偏移。
  double currentX;

  /// Active runtime Y offset. 运行时活跃 Y 偏移。
  double currentY;

  /// Active runtime width override. 运行时活跃宽度覆盖。
  double? currentWidth;

  /// Active runtime height override. 运行时活跃高度覆盖。
  double? currentHeight;

  /// Creates an [SvgUseNode]. 创建一个 [SvgUseNode] 引用节点。
  ///
  /// - [hrefId]: Target element `id`. 目标元素 ID。
  /// - [baseX]: Base X offset. 基础 X 偏移。
  /// - [baseY]: Base Y offset. 基础 Y 偏移。
  /// - [baseWidth]: Optional width override. 可选宽度。
  /// - [baseHeight]: Optional height override. 可选高度。
  SvgUseNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    this.hrefId,
    this.baseX = 0.0,
    this.baseY = 0.0,
    this.baseWidth,
    this.baseHeight,
  }) : currentX = baseX,
       currentY = baseY,
       currentWidth = baseWidth,
       currentHeight = baseHeight,
       super(tagName: 'use');

  SvgElement? _resolveTarget(SvgDocument document) {
    if (hrefId == null || hrefId!.isEmpty) return null;
    final target = document.defsById[hrefId!] ?? document.elementsById[hrefId!];
    if (identical(target, this)) return null;
    return target;
  }

  @override
  void initializeGeometry(SvgDocument document) {
    final target = _resolveTarget(document);
    if (target != null && _activeUseDepth < _maxUseDepth) {
      _activeUseDepth++;
      try {
        target.initializeGeometry(document);
        if (target is SvgSymbolNode) {
          final sz = target.resolveInstantiatedSize(
            useWidth: baseWidth,
            useHeight: baseHeight,
          );
          if (sz != null) {
            cachedBounds = ui.Rect.fromLTWH(baseX, baseY, sz.width, sz.height);
          } else {
            cachedBounds = target.cachedBounds.shift(ui.Offset(baseX, baseY));
          }
        } else if (baseWidth != null && baseHeight != null) {
          cachedBounds = ui.Rect.fromLTWH(
            baseX,
            baseY,
            baseWidth!,
            baseHeight!,
          );
        } else {
          cachedBounds = target.cachedBounds.shift(ui.Offset(baseX, baseY));
        }
      } finally {
        _activeUseDepth--;
      }
    } else {
      cachedBounds = ui.Rect.zero;
    }
    finalizeBaseTransforms(document.viewBox);
  }

  @override
  bool propagateAnimationFlags(SvgDocument document) {
    bool animated = super.propagateAnimationFlags(document);
    final target = _resolveTarget(document);
    if (target != null && _activeUseDepth < _maxUseDepth) {
      _activeUseDepth++;
      try {
        if (target.propagateAnimationFlags(document)) {
          animated = true;
        }
      } finally {
        _activeUseDepth--;
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
    currentWidth = baseWidth;
    currentHeight = baseHeight;
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    if (style.visibilityHidden || hrefId == null) return;
    if (_activeUseDepth >= _maxUseDepth) return;
    final target = _resolveTarget(document);
    if (target == null) return;

    _activeUseDepth++;
    SvgElement.beginDynamicUsePaint();
    try {
      final hasOffset = currentX != 0.0 || currentY != 0.0;
      if (hasOffset) {
        canvas.save();
        canvas.translate(currentX, currentY);
      }
      target.syncInheritedStyleTree(style);
      try {
        if (target is SvgSymbolNode) {
          target.paintInstantiated(
            canvas,
            document,
            useWidth: currentWidth,
            useHeight: currentHeight,
          );
        } else if (target is SvgNestedSvgNode) {
          target.paintWithViewport(
            canvas,
            document,
            effectiveOpacity,
            overrideWidth: currentWidth,
            overrideHeight: currentHeight,
          );
        } else {
          target.paint(canvas, document);
        }
      } finally {
        target.restoreBaseStyleTree(target.parent?.style);
      }
      if (hasOffset) {
        canvas.restore();
      }
    } finally {
      SvgElement.endDynamicUsePaint();
      _activeUseDepth--;
    }
  }
}
