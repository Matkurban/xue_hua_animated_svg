import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_transform.dart';

/// Coordinate system for `<linearGradient>`, `<radialGradient>`, `<clipPath>`, `<mask>`, `<pattern>`, and `<filter>`.
/// 渐变、裁剪、遮罩、图案与滤镜的坐标空间单位枚举。
enum SvgGradientUnits {
  /// Normalized `[0..1]` coordinates relative to the target's bounding box (`objectBoundingBox`).
  /// 相对目标包围盒的归一化坐标（`objectBoundingBox`）。
  objectBoundingBox,

  /// Absolute coordinates in the current user coordinate system (`userSpaceOnUse`).
  /// 当前用户空间绝对坐标（`userSpaceOnUse`）。
  userSpaceOnUse,
}

/// Gradient `<stop>` element with precompiled base values and mutable runtime fields.
/// 渐变色标 `<stop>` 节点，包含不可变基础值与动画每帧更新的运行时字段。
class SvgGradientStop {
  /// Optional XML `id`. 可选 XML `id`。
  final String? id;

  /// Base stop offset in `[0.0 .. 1.0]`. 基础色标偏移量。
  final double baseOffset;

  /// Base `stop-color`. 基础色标颜色。
  final ui.Color baseColor;

  /// Base `stop-opacity` in `[0.0 .. 1.0]`. 基础色标不透明度。
  final double baseOpacity;

  /// Active runtime stop offset. 运行时色标偏移量。
  double currentOffset;

  /// Active runtime stop color. 运行时色标颜色。
  ui.Color currentColor;

  /// Active runtime stop opacity. 运行时色标不透明度。
  double currentOpacity;

  /// Whether this stop is driven by an animation track. 该色标是否受动画驱动。
  bool isAnimated = false;

  /// Creates an [SvgGradientStop]. 创建一个 [SvgGradientStop] 渐变色标。
  SvgGradientStop({
    this.id,
    required this.baseOffset,
    required this.baseColor,
    this.baseOpacity = 1.0,
  }) : currentOffset = baseOffset.clamp(0.0, 1.0),
       currentColor = baseColor,
       currentOpacity = baseOpacity.clamp(0.0, 1.0);

  /// Resets runtime stop values back to base values. 将运行时色标状态重置回初始基值。
  void resetToBase() {
    currentOffset = baseOffset.clamp(0.0, 1.0);
    currentColor = baseColor;
    currentOpacity = baseOpacity.clamp(0.0, 1.0);
  }

  /// Effective color combining [currentColor] with [currentOpacity]. 合成不透明度后的有效色标颜色。
  ui.Color get effectiveColor {
    if (currentOpacity >= 1.0) return currentColor;
    final combinedAlpha = (currentColor.a * currentOpacity.clamp(0.0, 1.0))
        .clamp(0.0, 1.0);
    return currentColor.withValues(alpha: combinedAlpha);
  }
}

/// Abstract base class for `<linearGradient>` and `<radialGradient>`.
/// `<linearGradient>` 与 `<radialGradient>` 渐变节点的抽象基类。
abstract class SvgGradientNode {
  /// Unique XML `id`. 渐变唯一 XML `id`。
  final String id;

  /// Optional template gradient `id` referenced via `href` / `xlink:href`. 模板继承引用 ID。
  final String? hrefId;

  /// Coordinate system (`objectBoundingBox` or `userSpaceOnUse`). 渐变坐标空间单位。
  final SvgGradientUnits gradientUnits;

  /// Spread tile mode (`clamp`, `mirror`, `repeated`). 渐变延展模式。
  final ui.TileMode spreadMethod;

  /// Ordered gradient `<stop>` list. 有序渐变色标列表。
  final List<SvgGradientStop> stops;

  /// Static `gradientTransform` operations. 静态 `gradientTransform` 变换操作列表。
  final List<SvgTransformOp> baseGradientTransformOps;

  /// Pre-allocated base 4×4 gradient transform matrix. 预分配基础渐变变换矩阵。
  final Float64List baseGradientMatrix = SvgMatrixMath.createIdentity();

  /// Active runtime 4×4 gradient transform matrix. 运行时活跃渐变变换矩阵。
  final Float64List currentGradientMatrix = SvgMatrixMath.createIdentity();

  /// Combined shader matrix buffer reused every frame. 每帧复用的着色器矩阵缓冲。
  final Float64List shaderMatrix = SvgMatrixMath.createIdentity();

  /// Pre-allocated stop color buffer reused every frame. 每帧复用的色标颜色缓冲。
  late List<ui.Color> cachedColors;

  /// Pre-allocated stop offset buffer reused every frame. 每帧复用的色标偏移缓冲。
  late List<double> cachedOffsets;

  /// Whether this gradient or any of its stops is animated. 该渐变或其色标是否包含动画。
  bool isAnimated = false;

  /// Creates an [SvgGradientNode]. 创建一个 [SvgGradientNode] 渐变基类实例。
  SvgGradientNode({
    required this.id,
    this.hrefId,
    this.gradientUnits = SvgGradientUnits.objectBoundingBox,
    this.spreadMethod = ui.TileMode.clamp,
    required this.stops,
    this.baseGradientTransformOps = const [],
  }) {
    for (int i = 0; i < baseGradientTransformOps.length; i++) {
      SvgMatrixMath.applyOpInPlace(
        baseGradientMatrix,
        baseGradientTransformOps[i],
      );
    }
    SvgMatrixMath.copyInto(baseGradientMatrix, currentGradientMatrix);
    _allocateStopBuffers();
  }

  void _allocateStopBuffers() {
    cachedColors = List<ui.Color>.filled(
      stops.length,
      const ui.Color(0x00000000),
    );
    cachedOffsets = List<double>.filled(stops.length, 0.0);
    syncStopsToBuffers();
  }

  /// Resolves inherited stops (and gradientTransform) recursively along `href`
  /// template chains with cycle protection (W3C SVG 2 §14.2).
  void resolveTemplate(Map<String, SvgGradientNode> gradientsById) {
    final visited = <String>{id};
    SvgGradientNode? cur = this;
    while (cur != null && cur.hrefId != null) {
      final nextId = cur.hrefId!;
      if (!visited.add(nextId)) break;
      final template = gradientsById[nextId];
      if (template == null) break;
      if (stops.isEmpty && template.stops.isNotEmpty) {
        stops.addAll(template.stops);
        _allocateStopBuffers();
      }
      if (baseGradientTransformOps.isEmpty &&
          template.baseGradientTransformOps.isNotEmpty) {
        SvgMatrixMath.copyInto(template.baseGradientMatrix, baseGradientMatrix);
        SvgMatrixMath.copyInto(baseGradientMatrix, currentGradientMatrix);
      }
      cur = template;
    }
    for (final stop in stops) {
      if (stop.isAnimated) {
        isAnimated = true;
      }
    }
  }

  /// Updates [cachedColors] and [cachedOffsets] in-place from [stops].
  void syncStopsToBuffers() {
    if (cachedColors.length != stops.length) {
      _allocateStopBuffers();
      return;
    }
    double lastOffset = 0.0;
    for (int i = 0; i < stops.length; i++) {
      final stop = stops[i];
      cachedColors[i] = stop.effectiveColor;
      final clamped = stop.currentOffset.clamp(0.0, 1.0);
      final monotonic = clamped < lastOffset ? lastOffset : clamped;
      cachedOffsets[i] = monotonic;
      lastOffset = monotonic;
    }
  }

  void resetToBase() {
    SvgMatrixMath.copyInto(baseGradientMatrix, currentGradientMatrix);
    for (int i = 0; i < stops.length; i++) {
      stops[i].resetToBase();
    }
    syncStopsToBuffers();
  }

  /// Computes the combined 4x4 matrix mapping gradient coordinates into [targetBounds]
  /// when [gradientUnits] is [SvgGradientUnits.objectBoundingBox].
  Float64List computeShaderMatrix(ui.Rect targetBounds) {
    SvgMatrixMath.resetToIdentity(shaderMatrix);
    if (gradientUnits == SvgGradientUnits.objectBoundingBox) {
      SvgMatrixMath.translateInPlace(
        shaderMatrix,
        targetBounds.left,
        targetBounds.top,
      );
      SvgMatrixMath.scaleInPlace(
        shaderMatrix,
        targetBounds.width == 0.0 ? 1.0 : targetBounds.width,
        targetBounds.height == 0.0 ? 1.0 : targetBounds.height,
      );
    }
    SvgMatrixMath.multiply4x4InPlace(shaderMatrix, currentGradientMatrix);
    return shaderMatrix;
  }

  /// Builds a [ui.Shader] for the given geometry [targetBounds].
  ui.Shader? createShader(ui.Rect targetBounds);
}

/// Precompiled `<linearGradient>` node with mutable endpoints `(x1, y1)` -> `(x2, y2)`.
/// 预编译的 `<linearGradient>` 线性渐变节点，支持起止点坐标动画。
class SvgLinearGradientNode extends SvgGradientNode {
  /// Base start X (`x1`). 基础起点 X。
  final double baseX1;

  /// Base start Y (`y1`). 基础起点 Y。
  final double baseY1;

  /// Base end X (`x2`). 基础终点 X。
  final double baseX2;

  /// Base end Y (`y2`). 基础终点 Y。
  final double baseY2;

  /// Active runtime start X. 运行时起点 X。
  double currentX1;

  /// Active runtime start Y. 运行时起点 Y。
  double currentY1;

  /// Active runtime end X. 运行时终点 X。
  double currentX2;

  /// Active runtime end Y. 运行时终点 Y。
  double currentY2;

  /// Creates an [SvgLinearGradientNode]. 创建一个 [SvgLinearGradientNode] 线性渐变节点。
  SvgLinearGradientNode({
    required super.id,
    super.hrefId,
    super.gradientUnits,
    super.spreadMethod,
    required super.stops,
    super.baseGradientTransformOps,
    this.baseX1 = 0.0,
    this.baseY1 = 0.0,
    this.baseX2 = 1.0,
    this.baseY2 = 0.0,
  }) : currentX1 = baseX1,
       currentY1 = baseY1,
       currentX2 = baseX2,
       currentY2 = baseY2;

  @override
  void resetToBase() {
    super.resetToBase();
    currentX1 = baseX1;
    currentY1 = baseY1;
    currentX2 = baseX2;
    currentY2 = baseY2;
  }

  @override
  ui.Shader? createShader(ui.Rect targetBounds) {
    if (stops.isEmpty) return null;
    syncStopsToBuffers();
    final matrix = computeShaderMatrix(targetBounds);
    return ui.Gradient.linear(
      ui.Offset(currentX1, currentY1),
      ui.Offset(currentX2, currentY2),
      cachedColors,
      cachedOffsets,
      spreadMethod,
      matrix,
    );
  }
}

/// Precompiled `<radialGradient>` node with mutable center `(cx, cy)`, radius `r`,
/// focal point `(fx, fy)`, and SVG 2 focal radius `fr`.
/// 预编译的 `<radialGradient>` 径向渐变节点，支持中心、半径、焦点与 SVG 2 `fr` 动画。
class SvgRadialGradientNode extends SvgGradientNode {
  /// Base center X (`cx`). 基础圆心 X。
  final double baseCx;

  /// Base center Y (`cy`). 基础圆心 Y。
  final double baseCy;

  /// Base radius (`r`). 基础半径。
  final double baseR;

  /// Base focal X (`fx`). 基础焦点 X。
  final double baseFx;

  /// Base focal Y (`fy`). 基础焦点 Y。
  final double baseFy;

  /// Base SVG 2 focal radius (`fr`). 基础 SVG 2 焦点半径。
  final double baseFr;

  /// Active runtime center X. 运行时圆心 X。
  double currentCx;

  /// Active runtime center Y. 运行时圆心 Y。
  double currentCy;

  /// Active runtime radius. 运行时半径。
  double currentR;

  /// Active runtime focal X. 运行时焦点 X。
  double currentFx;

  /// Active runtime focal Y. 运行时焦点 Y。
  double currentFy;

  /// Active runtime focal radius. 运行时焦点半径。
  double currentFr;

  /// Creates an [SvgRadialGradientNode]. 创建一个 [SvgRadialGradientNode] 径向渐变节点。
  SvgRadialGradientNode({
    required super.id,
    super.hrefId,
    super.gradientUnits,
    super.spreadMethod,
    required super.stops,
    super.baseGradientTransformOps,
    this.baseCx = 0.5,
    this.baseCy = 0.5,
    this.baseR = 0.5,
    double? baseFx,
    double? baseFy,
    this.baseFr = 0.0,
  }) : baseFx = baseFx ?? baseCx,
       baseFy = baseFy ?? baseCy,
       currentCx = baseCx,
       currentCy = baseCy,
       currentR = baseR,
       currentFx = baseFx ?? baseCx,
       currentFy = baseFy ?? baseCy,
       currentFr = baseFr;

  @override
  void resetToBase() {
    super.resetToBase();
    currentCx = baseCx;
    currentCy = baseCy;
    currentR = baseR;
    currentFx = baseFx;
    currentFy = baseFy;
    currentFr = baseFr;
  }

  @override
  ui.Shader? createShader(ui.Rect targetBounds) {
    if (stops.isEmpty || currentR <= 0.0) return null;
    syncStopsToBuffers();
    final matrix = computeShaderMatrix(targetBounds);
    final hasFocal =
        currentFr > 0.0 ||
        (currentFx - currentCx).abs() > 1e-5 ||
        (currentFy - currentCy).abs() > 1e-5;
    return ui.Gradient.radial(
      ui.Offset(currentCx, currentCy),
      currentR,
      cachedColors,
      cachedOffsets,
      spreadMethod,
      matrix,
      hasFocal ? ui.Offset(currentFx, currentFy) : null,
      currentFr.clamp(0.0, double.infinity),
    );
  }
}
