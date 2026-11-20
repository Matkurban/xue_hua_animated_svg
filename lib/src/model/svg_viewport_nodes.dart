import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_container_nodes.dart';
import 'svg_document.dart';
import 'svg_element.dart';
import 'svg_preserve_aspect_ratio.dart';
import 'svg_transform.dart';

/// Graphic-level hyperlink container `<a>` node (W3C SVG 1.1 / SVG 2).
/// 图形级超链接容器 `<a>` 节点。
class SvgAnchorNode extends SvgGroupNode {
  /// Target link URL (`href` / `xlink:href`). 链接目标地址。
  final String? href;

  /// Optional link browsing context (`target`). 可选链接打开目标。
  final String? target;

  /// Creates an [SvgAnchorNode]. 创建一个 [SvgAnchorNode] 超链接容器节点。
  SvgAnchorNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    super.children,
    this.href,
    this.target,
  }) : super(tagName: 'a');
}

/// Conditional processing attributes attached to a direct child of `<switch>`.
/// 挂载在 `<switch>` 直接子元素上的条件处理属性集合。
class SvgConditionalAttrs {
  /// `requiredExtensions` attribute (unsupported extensions reject the branch). 扩展要求属性。
  final String? requiredExtensions;

  /// Legacy `requiredFeatures` attribute. 传统特性要求属性。
  final String? requiredFeatures;

  /// BCP-47 language tags from `systemLanguage`. `systemLanguage` 语言标签列表。
  final List<String> systemLanguages;

  /// Creates an [SvgConditionalAttrs]. 创建一个 [SvgConditionalAttrs] 条件属性对象。
  const SvgConditionalAttrs({
    this.requiredExtensions,
    this.requiredFeatures,
    this.systemLanguages = const [],
  });

  /// Evaluates whether this child satisfies W3C SVG conditional processing rules.
  /// 评估当前子元素是否满足 W3C SVG 条件处理规则。
  ///
  /// - [activeLanguageTag]: Optional BCP-47 language override (defaults to platform locale).
  ///   可选语言标签覆盖（默认读取系统语言）。
  bool matches({String? activeLanguageTag}) {
    if (requiredExtensions != null && requiredExtensions!.trim().isNotEmpty) {
      return false;
    }
    if (systemLanguages.isNotEmpty) {
      final localeTag = (activeLanguageTag ?? _platformLanguageTag())
          .toLowerCase();
      bool langMatched = false;
      for (final raw in systemLanguages) {
        final candidate = raw.trim().toLowerCase();
        if (candidate.isEmpty) continue;
        if (localeTag == candidate ||
            localeTag.startsWith('$candidate-') ||
            candidate.startsWith('$localeTag-')) {
          langMatched = true;
          break;
        }
      }
      if (!langMatched) return false;
    }
    return true;
  }

  static String _platformLanguageTag() {
    final locale = ui.PlatformDispatcher.instance.locale;
    final country = locale.countryCode;
    if (country != null && country.isNotEmpty) {
      return '${locale.languageCode}-$country';
    }
    return locale.languageCode;
  }
}

/// Conditional `<switch>` container node (W3C SVG 1.1 §5.8.1 / SVG 2).
/// 条件分支 `<switch>` 容器节点，按文档顺序仅渲染首个满足条件属性的子元素。
class SvgSwitchNode extends SvgGroupNode {
  /// Conditional attributes aligned by index with [children]. 与子元素一一对应的条件属性列表。
  final List<SvgConditionalAttrs> childConditions;

  /// Optional BCP-47 language override for testing/locale switching. 可选语言覆盖标签。
  final String? languageOverride;

  SvgElement? _selectedChild;

  /// Creates an [SvgSwitchNode]. 创建一个 [SvgSwitchNode] 条件容器节点。
  SvgSwitchNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    super.children,
    required this.childConditions,
    this.languageOverride,
  }) : super(tagName: 'switch');

  /// The single child element selected by `<switch>` evaluation, or `null`.
  SvgElement? get selectedChild => _selectedChild;

  SvgElement? _resolveSelectedChild() {
    for (int i = 0; i < children.length; i++) {
      final cond = i < childConditions.length
          ? childConditions[i]
          : const SvgConditionalAttrs();
      if (cond.matches(activeLanguageTag: languageOverride)) {
        return children[i];
      }
    }
    return null;
  }

  @override
  void initializeGeometry(SvgDocument document) {
    _selectedChild = _resolveSelectedChild();
    final chosen = _selectedChild;
    if (chosen != null) {
      chosen.initializeGeometry(document);
      cachedBounds = chosen.cachedBounds;
    } else {
      cachedBounds = ui.Rect.zero;
    }
    finalizeBaseTransforms(document.viewBox);
  }

  @override
  bool propagateAnimationFlags(SvgDocument document) {
    bool animated = hasSelfAnimation || hasMotionAnimation;
    final chosen = _selectedChild;
    if (chosen != null && chosen.propagateAnimationFlags(document)) {
      animated = true;
    }
    isAnimated = animated;
    return animated;
  }

  @override
  void paintContent(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity,
  ) {
    final chosen = _selectedChild;
    if (chosen == null) return;
    if (hasSelfAnimation) {
      chosen.style.syncInheritedFromParent(style);
    }
    chosen.paint(canvas, document);
  }
}

/// Nested `<svg>` viewport container establishing a new coordinate system,
/// optional `viewBox` + `preserveAspectRatio` mapping, and `overflow: hidden`
/// viewport clipping per W3C SVG 1.1 §5.1 / SVG 2.
/// 嵌套 `<svg>` 视口容器节点，建立局部坐标系、可选 `viewBox` 映射及默认视口裁剪。
class SvgNestedSvgNode extends SvgGroupNode {
  /// Base X coordinate. 基础 X 坐标。
  final double baseX;

  /// Base Y coordinate. 基础 Y 坐标。
  final double baseY;

  /// Optional base viewport width. 可选基础视口宽度。
  final double? baseWidth;

  /// Optional base viewport height. 可选基础视口高度。
  final double? baseHeight;

  /// Optional inner `viewBox` rect. 可选内部 `viewBox` 矩形。
  final ui.Rect? innerViewBox;

  /// Aspect ratio rule for [innerViewBox]. 内部视口长宽比规则。
  final SvgPreserveAspectRatio preserveAspectRatio;

  /// Active runtime X coordinate. 运行时 X 坐标。
  double currentX;

  /// Active runtime Y coordinate. 运行时 Y 坐标。
  double currentY;

  /// Active runtime width. 运行时宽度。
  double? currentWidth;

  /// Active runtime height. 运行时高度。
  double? currentHeight;

  final Float64List _innerViewBoxMatrix = SvgMatrixMath.createIdentity();

  /// Creates an [SvgNestedSvgNode]. 创建一个 [SvgNestedSvgNode] 嵌套视口节点。
  SvgNestedSvgNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    super.children,
    this.baseX = 0.0,
    this.baseY = 0.0,
    this.baseWidth,
    this.baseHeight,
    this.innerViewBox,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
  }) : currentX = baseX,
       currentY = baseY,
       currentWidth = baseWidth,
       currentHeight = baseHeight,
       super(tagName: 'svg');

  bool get _overflowHidden => style.baseOverflowVisible != true;

  @override
  void initializeGeometry(SvgDocument document) {
    super.initializeGeometry(document);
    final w = baseWidth ?? innerViewBox?.width ?? cachedBounds.width;
    final h = baseHeight ?? innerViewBox?.height ?? cachedBounds.height;
    if (w > 0.0 && h > 0.0) {
      cachedBounds = ui.Rect.fromLTWH(baseX, baseY, w, h);
    }
    finalizeBaseTransforms(document.viewBox);
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
    paintWithViewport(
      canvas,
      document,
      effectiveOpacity,
      overrideWidth: null,
      overrideHeight: null,
    );
  }

  /// Paints this nested `<svg>` with optional width/height overrides from `<use>`.
  void paintWithViewport(
    ui.Canvas canvas,
    SvgDocument document,
    double effectiveOpacity, {
    double? overrideWidth,
    double? overrideHeight,
  }) {
    final w = overrideWidth ?? currentWidth ?? innerViewBox?.width;
    final h = overrideHeight ?? currentHeight ?? innerViewBox?.height;
    final hasOffset = currentX != 0.0 || currentY != 0.0;
    final hasClip = _overflowHidden && w != null && h != null && w > 0 && h > 0;
    final hasViewBox =
        innerViewBox != null && w != null && h != null && w > 0 && h > 0;

    final needsSave = hasOffset || hasClip || hasViewBox;
    if (needsSave) canvas.save();

    if (hasOffset) {
      canvas.translate(currentX, currentY);
    }
    if (hasClip) {
      canvas.clipRect(ui.Rect.fromLTWH(0.0, 0.0, w, h));
    }
    if (hasViewBox) {
      preserveAspectRatio.computeMatrixInPlace(
        innerViewBox!,
        ui.Size(w, h),
        _innerViewBoxMatrix,
      );
      canvas.transform(_innerViewBoxMatrix);
    }

    super.paintContent(canvas, document, effectiveOpacity);

    if (needsSave) canvas.restore();
  }
}

/// Reusable `<symbol>` template node (W3C SVG 1.1 §5.5 / SVG 2).
/// 可复用 `<symbol>` 模板节点（不直接绘制，仅通过 `<use>` 实例化并映射 `viewBox`）。
class SvgSymbolNode extends SvgGroupNode {
  /// Base X offset. 基础 X 偏移。
  final double baseX;

  /// Base Y offset. 基础 Y 偏移。
  final double baseY;

  /// Optional intrinsic width. 可选固有宽度。
  final double? baseWidth;

  /// Optional intrinsic height. 可选固有高度。
  final double? baseHeight;

  /// SVG 2 reference anchor X (`refX`). SVG 2 参考锚点 X。
  final double refX;

  /// SVG 2 reference anchor Y (`refY`). SVG 2 参考锚点 Y。
  final double refY;

  /// Optional symbol `viewBox`. 可选符号 `viewBox`。
  final ui.Rect? innerViewBox;

  /// Aspect ratio mapping rule. 长宽比映射规则。
  final SvgPreserveAspectRatio preserveAspectRatio;

  final Float64List _symbolMatrix = SvgMatrixMath.createIdentity();

  SvgSymbolNode({
    super.id,
    super.classes,
    required super.style,
    super.baseTransformOps,
    super.children,
    this.baseX = 0.0,
    this.baseY = 0.0,
    this.baseWidth,
    this.baseHeight,
    this.refX = 0.0,
    this.refY = 0.0,
    this.innerViewBox,
    this.preserveAspectRatio = SvgPreserveAspectRatio.defaultValue,
  }) : super(tagName: 'symbol');

  bool get _overflowHidden => style.baseOverflowVisible != true;

  @override
  bool get shouldCacheStaticPicture => false;

  @override
  void paint(ui.Canvas canvas, SvgDocument document) {
    // Per W3C SVG spec, <symbol> is never rendered directly; only via <use>.
  }

  /// Resolves the effective `(width, height)` for a `<use>` instantiation,
  /// preserving `innerViewBox` aspect ratio when only one dimension is given.
  ui.Size? resolveInstantiatedSize({double? useWidth, double? useHeight}) {
    final explicitW = useWidth ?? baseWidth;
    final explicitH = useHeight ?? baseHeight;
    final vb = innerViewBox;
    if (explicitW != null && explicitH != null) {
      return ui.Size(explicitW, explicitH);
    }
    if (explicitW != null) {
      if (vb != null && vb.width > 0.0 && vb.height > 0.0) {
        return ui.Size(explicitW, explicitW * (vb.height / vb.width));
      }
      return ui.Size(explicitW, explicitW);
    }
    if (explicitH != null) {
      if (vb != null && vb.width > 0.0 && vb.height > 0.0) {
        return ui.Size(explicitH * (vb.width / vb.height), explicitH);
      }
      return ui.Size(explicitH, explicitH);
    }
    if (vb != null && vb.width > 0.0 && vb.height > 0.0) {
      return ui.Size(vb.width, vb.height);
    }
    return null;
  }

  /// Instantiates and paints this `<symbol>` from a `<use>` element.
  void paintInstantiated(
    ui.Canvas canvas,
    SvgDocument document, {
    double? useWidth,
    double? useHeight,
  }) {
    if (style.displayNone) return;

    final resolvedSize = resolveInstantiatedSize(
      useWidth: useWidth,
      useHeight: useHeight,
    );
    final w = resolvedSize?.width;
    final h = resolvedSize?.height;
    final hasClip = _overflowHidden && w != null && h != null && w > 0 && h > 0;
    final hasViewBox =
        innerViewBox != null && w != null && h != null && w > 0 && h > 0;
    final hasOffset =
        baseX != 0.0 || baseY != 0.0 || refX != 0.0 || refY != 0.0;

    canvas.save();
    if (hasOffset) {
      canvas.translate(baseX - refX, baseY - refY);
    }
    if (hasClip) {
      canvas.clipRect(ui.Rect.fromLTWH(0.0, 0.0, w, h));
    }
    if (hasViewBox) {
      preserveAspectRatio.computeMatrixInPlace(
        innerViewBox!,
        ui.Size(w, h),
        _symbolMatrix,
      );
      canvas.transform(_symbolMatrix);
    }

    super.paintContent(canvas, document, style.currentOpacity.clamp(0.0, 1.0));
    canvas.restore();
  }
}

/// Named `<view>` specification defining an alternate `viewBox` and
/// `preserveAspectRatio` for SVG sprite sheets and view anchors (W3C SVG 1.1 §17.3 / SVG 2).
/// 命名 `<view>` 视口定义节点，用于通过 `viewId` 切换备用 `viewBox` 与长宽比规则。
class SvgViewNode {
  /// Unique XML `id` of this `<view>`. `<view>` 唯一标识。
  final String id;

  /// Optional alternate `viewBox`. 可选替换 `viewBox`。
  final ui.Rect? viewBox;

  /// Optional alternate `preserveAspectRatio`. 可选替换长宽比规则。
  final SvgPreserveAspectRatio? preserveAspectRatio;

  /// Creates an [SvgViewNode]. 创建一个 [SvgViewNode] 命名视图对象。
  const SvgViewNode({required this.id, this.viewBox, this.preserveAspectRatio});
}
