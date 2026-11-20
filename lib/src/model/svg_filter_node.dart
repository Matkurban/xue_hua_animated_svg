import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'svg_filter_noise.dart';
import 'svg_gradient.dart';
import 'svg_preserve_aspect_ratio.dart';

export 'svg_filter_noise.dart';

part 'svg_filter_advanced.dart';

/// Base sealed class for precompiled SVG `<filter>` primitives (`fe*`).
///
/// 预编译 SVG `<filter>` 滤镜图元（`fe*`）的密封基类。
sealed class SvgFilterPrimitive {
  /// Optional input source name (`in`, e.g. `SourceGraphic`, `SourceAlpha`, or
  /// a prior primitive's [result]).
  ///
  /// 可选输入源名称（`in`，如 `SourceGraphic`、`SourceAlpha` 或前序图元的 [result]）。
  final String? inSource;

  /// Optional named output buffer identifier (`result`) for downstream
  /// primitives to reference.
  ///
  /// 可选输出缓冲区名称（`result`），供后续滤镜图元引用。
  final String? result;

  /// Optional primitive subregion X origin (`x`).
  ///
  /// 可选图元子区域 X 起点（`x`）。
  final double? x;

  /// Optional primitive subregion Y origin (`y`).
  ///
  /// 可选图元子区域 Y 起点（`y`）。
  final double? y;

  /// Optional primitive subregion width (`width`).
  ///
  /// 可选图元子区域宽度（`width`）。
  final double? width;

  /// Optional primitive subregion height (`height`).
  ///
  /// 可选图元子区域高度（`height`）。
  final double? height;

  /// Creates an [SvgFilterPrimitive] with optional [inSource], [result], and
  /// subregion bounds ([x], [y], [width], [height]).
  ///
  /// 创建 [SvgFilterPrimitive]，配置可选的输入源 [inSource]、结果名 [result] 及子区域边界（[x]、[y]、[width]、[height]）。
  const SvgFilterPrimitive({
    this.inSource,
    this.result,
    this.x,
    this.y,
    this.width,
    this.height,
  });

  /// Resolves the primitive subregion clipped within [filterRegion] for
  /// [targetBounds] using [primitiveUnits].
  ///
  /// 根据 [primitiveUnits] 和目标边界 [targetBounds]，解析位于 [filterRegion] 内的图元子区域。
  ui.Rect resolveSubregion(
    ui.Rect filterRegion,
    ui.Rect targetBounds,
    SvgGradientUnits primitiveUnits,
  ) {
    if (x == null && y == null && width == null && height == null) {
      return filterRegion;
    }
    if (primitiveUnits == SvgGradientUnits.objectBoundingBox) {
      final bw = targetBounds.width == 0.0
          ? filterRegion.width
          : targetBounds.width;
      final bh = targetBounds.height == 0.0
          ? filterRegion.height
          : targetBounds.height;
      final rx = x != null ? targetBounds.left + x! * bw : filterRegion.left;
      final ry = y != null ? targetBounds.top + y! * bh : filterRegion.top;
      final rw = width != null ? width! * bw : filterRegion.width;
      final rh = height != null ? height! * bh : filterRegion.height;
      return ui.Rect.fromLTWH(rx, ry, rw, rh);
    }
    return ui.Rect.fromLTWH(
      x ?? filterRegion.left,
      y ?? filterRegion.top,
      width ?? filterRegion.width,
      height ?? filterRegion.height,
    );
  }
}

/// Precompiled `<feGaussianBlur stdDeviation="sx [sy]" edgeMode="none|duplicate|wrap" />` primitive.
///
/// 预编译的 `<feGaussianBlur>` 高斯模糊滤镜图元。
final class SvgFeGaussianBlur extends SvgFilterPrimitive {
  /// Horizontal Gaussian blur standard deviation (`stdDeviation` X).
  ///
  /// 水平高斯模糊标准差（`stdDeviation` X 分量）。
  final double sigmaX;

  /// Vertical Gaussian blur standard deviation (`stdDeviation` Y).
  ///
  /// 垂直高斯模糊标准差（`stdDeviation` Y 分量）。
  final double sigmaY;

  /// Edge sampling mode mapped from `edgeMode` (`none` -> decal, `duplicate` ->
  /// clamp, `wrap` -> repeated).
  ///
  /// 由 `edgeMode` 映射而来的边缘采样模式。
  final ui.TileMode tileMode;

  /// Creates an [SvgFeGaussianBlur] with [sigmaX], [sigmaY], and [tileMode].
  ///
  /// 创建 [SvgFeGaussianBlur]，指定模糊标准差 [sigmaX]、[sigmaY] 及边缘模式 [tileMode]。
  const SvgFeGaussianBlur({
    super.inSource,
    super.result,
    required this.sigmaX,
    required this.sigmaY,
    this.tileMode = ui.TileMode.decal,
  });
}

/// Precompiled `<feDropShadow dx="..." dy="..." stdDeviation="..." flood-color="..." flood-opacity="..." />` primitive.
///
/// 预编译的 `<feDropShadow>` 投影滤镜图元。
final class SvgFeDropShadow extends SvgFilterPrimitive {
  /// Horizontal shadow offset (`dx`).
  ///
  /// 阴影水平偏移量（`dx`）。
  final double dx;

  /// Vertical shadow offset (`dy`).
  ///
  /// 阴影垂直偏移量（`dy`）。
  final double dy;

  /// Horizontal shadow blur standard deviation (`stdDeviation` X).
  ///
  /// 阴影水平模糊标准差（`stdDeviation` X 分量）。
  final double sigmaX;

  /// Vertical shadow blur standard deviation (`stdDeviation` Y).
  ///
  /// 阴影垂直模糊标准差（`stdDeviation` Y 分量）。
  final double sigmaY;

  /// Shadow color (`flood-color`).
  ///
  /// 阴影颜色（`flood-color`）。
  final ui.Color floodColor;

  /// Shadow opacity multiplier in `[0.0, 1.0]` (`flood-opacity`).
  ///
  /// 阴影不透明度系数（`flood-opacity`，范围 `[0.0, 1.0]`）。
  final double floodOpacity;

  /// Creates an [SvgFeDropShadow] with offset ([dx], [dy]), blur ([sigmaX],
  /// [sigmaY]), [floodColor], and [floodOpacity].
  ///
  /// 创建 [SvgFeDropShadow]，配置偏移量（[dx]、[dy]）、模糊半径（[sigmaX]、[sigmaY]）、颜色 [floodColor] 与不透明度 [floodOpacity]。
  const SvgFeDropShadow({
    super.inSource,
    super.result,
    this.dx = 2.0,
    this.dy = 2.0,
    this.sigmaX = 2.0,
    this.sigmaY = 2.0,
    this.floodColor = const ui.Color(0xFF000000),
    this.floodOpacity = 1.0,
  });
}

/// Precompiled `<feOffset dx="..." dy="..." />` primitive.
///
/// 预编译的 `<feOffset>` 平移偏移滤镜图元。
final class SvgFeOffset extends SvgFilterPrimitive {
  /// Horizontal translation offset (`dx`).
  ///
  /// 水平平移偏移量（`dx`）。
  final double dx;

  /// Vertical translation offset (`dy`).
  ///
  /// 垂直平移偏移量（`dy`）。
  final double dy;

  /// Creates an [SvgFeOffset] with translation offsets [dx] and [dy].
  ///
  /// 创建 [SvgFeOffset]，指定平移偏移量 [dx] 和 [dy]。
  const SvgFeOffset({
    super.inSource,
    super.result,
    this.dx = 0.0,
    this.dy = 0.0,
  });
}

/// Operation mode for `<feColorMatrix type="...">`.
///
/// `<feColorMatrix type="...">` 的颜色矩阵运算模式。
enum SvgFeColorMatrixType {
  /// Full 4x5 RGBA transformation matrix (`type="matrix"`).
  ///
  /// 完整 4x5 RGBA 颜色变换矩阵（`type="matrix"`）。
  matrix,

  /// Saturation adjustment by a single scalar (`type="saturate"`).
  ///
  /// 单标量饱和度调整（`type="saturate"`）。
  saturate,

  /// Hue rotation in degrees (`type="hueRotate"`).
  ///
  /// 按角度旋转色相（`type="hueRotate"`）。
  hueRotate,

  /// Converts RGB luminance into the alpha channel (`type="luminanceToAlpha"`).
  ///
  /// 将 RGB 亮度转换为 Alpha 通道（`type="luminanceToAlpha"`）。
  luminanceToAlpha,
}

/// Precompiled `<feColorMatrix type="..." values="..." />` primitive.
///
/// 预编译的 `<feColorMatrix>` 颜色矩阵滤镜图元。
final class SvgFeColorMatrix extends SvgFilterPrimitive {
  /// Color matrix operation mode (`type`).
  ///
  /// 颜色矩阵运算模式（`type`）。
  final SvgFeColorMatrixType type;

  /// Numeric parameter list (`values`): 20 elements for [SvgFeColorMatrixType.matrix],
  /// or 1 scalar for `saturate` / `hueRotate`.
  ///
  /// 数值参数列表（`values`）：[SvgFeColorMatrixType.matrix] 为 20 个矩阵元素，`saturate` / `hueRotate` 为单个标量。
  final Float64List values;

  /// Creates an [SvgFeColorMatrix] with [type] and numeric [values].
  ///
  /// 创建 [SvgFeColorMatrix]，指定模式 [type] 与参数列表 [values]。
  const SvgFeColorMatrix({
    super.inSource,
    super.result,
    this.type = SvgFeColorMatrixType.matrix,
    required this.values,
  });
}

/// Precompiled `<feFlood flood-color="..." flood-opacity="..." />` primitive.
///
/// 预编译的 `<feFlood>` 纯色填充滤镜图元。
final class SvgFeFlood extends SvgFilterPrimitive {
  /// Fill color for the filter subregion (`flood-color`).
  ///
  /// 滤镜子区域的填充颜色（`flood-color`）。
  final ui.Color floodColor;

  /// Opacity multiplier in `[0.0, 1.0]` (`flood-opacity`).
  ///
  /// 填充不透明度系数（`flood-opacity`，范围 `[0.0, 1.0]`）。
  final double floodOpacity;

  /// Creates an [SvgFeFlood] with [floodColor] and [floodOpacity].
  ///
  /// 创建 [SvgFeFlood]，指定填充颜色 [floodColor] 与不透明度 [floodOpacity]。
  const SvgFeFlood({
    super.inSource,
    super.result,
    this.floodColor = const ui.Color(0xFF000000),
    this.floodOpacity = 1.0,
  });
}

/// Precompiled `<feBlend in="..." in2="..." mode="..." />` primitive.
///
/// 预编译的 `<feBlend>` 图层混合滤镜图元。
final class SvgFeBlend extends SvgFilterPrimitive {
  /// Optional second input source name (`in2`).
  ///
  /// 可选第二个输入源名称（`in2`）。
  final String? in2;

  /// Flutter [ui.BlendMode] mapped from the SVG `mode` attribute.
  ///
  /// 由 SVG `mode` 属性映射的 Flutter [ui.BlendMode] 混合模式。
  final ui.BlendMode mode;

  /// Creates an [SvgFeBlend] blending [inSource] over [in2] using [mode].
  ///
  /// 创建 [SvgFeBlend]，使用混合模式 [mode] 将 [inSource] 与 [in2] 混合。
  const SvgFeBlend({
    super.inSource,
    super.result,
    this.in2,
    this.mode = ui.BlendMode.srcOver,
  });
}

/// Precompiled `<feComposite in="..." in2="..." operator="over|in|out|atop|xor|lighter|arithmetic" />` primitive.
///
/// 预编译的 `<feComposite>` Porter-Duff / 算术合成滤镜图元。
final class SvgFeComposite extends SvgFilterPrimitive {
  /// Optional second input source name (`in2`).
  ///
  /// 可选第二个输入源名称（`in2`）。
  final String? in2;

  /// Porter-Duff [ui.BlendMode] used when [isArithmetic] is `false`.
  ///
  /// 当 [isArithmetic] 为 `false` 时使用的 Porter-Duff [ui.BlendMode]。
  final ui.BlendMode operatorMode;

  /// Whether `operator="arithmetic"` (`k1*i1*i2 + k2*i1 + k3*i2 + k4`) is used.
  ///
  /// 是否使用算术合成模式（`operator="arithmetic"`）。
  final bool isArithmetic;

  /// Arithmetic coefficient `k1` multiplying `in * in2`.
  ///
  /// 算术合成系数 `k1`（乘以 `in * in2`）。
  final double k1;

  /// Arithmetic coefficient `k2` multiplying `in`.
  ///
  /// 算术合成系数 `k2`（乘以 `in`）。
  final double k2;

  /// Arithmetic coefficient `k3` multiplying `in2`.
  ///
  /// 算术合成系数 `k3`（乘以 `in2`）。
  final double k3;

  /// Constant arithmetic offset `k4`.
  ///
  /// 算术合成常量偏移 `k4`。
  final double k4;

  /// Creates an [SvgFeComposite] with [in2], [operatorMode], or arithmetic
  /// coefficients ([isArithmetic], [k1], [k2], [k3], [k4]).
  ///
  /// 创建 [SvgFeComposite]，配置第二输入源 [in2]、合成模式 [operatorMode] 或算术系数（[isArithmetic]、[k1]、[k2]、[k3]、[k4]）。
  const SvgFeComposite({
    super.inSource,
    super.result,
    super.x,
    super.y,
    super.width,
    super.height,
    this.in2,
    this.operatorMode = ui.BlendMode.srcOver,
    this.isArithmetic = false,
    this.k1 = 0.0,
    this.k2 = 0.0,
    this.k3 = 0.0,
    this.k4 = 0.0,
  });
}

/// Precompiled `<feMerge>` primitive containing ordered `<feMergeNode in="..." />` inputs.
///
/// 预编译的 `<feMerge>` 图层合并滤镜图元，按顺序叠加多个 `<feMergeNode>` 输入。
final class SvgFeMerge extends SvgFilterPrimitive {
  /// Ordered list of `<feMergeNode in="...">` input source names painted bottom to top.
  ///
  /// 按自底向上顺序绘制的 `<feMergeNode in="...">` 输入源名称列表。
  final List<String?> inputs;

  /// Creates an [SvgFeMerge] with the ordered [inputs] list.
  ///
  /// 创建 [SvgFeMerge]，传入按顺序叠加的输入列表 [inputs]。
  const SvgFeMerge({super.inSource, super.result, required this.inputs});
}

/// Precompiled `<feMorphology operator="erode|dilate" radius="rx [ry]" />` primitive.
///
/// 预编译的 `<feMorphology>` 形态学腐蚀/膨胀滤镜图元。
final class SvgFeMorphology extends SvgFilterPrimitive {
  /// `true` for `operator="dilate"` (thicken); `false` for `operator="erode"` (thin).
  ///
  /// 为 `true` 表示膨胀（`dilate`），为 `false` 表示腐蚀（`erode`）。
  final bool isDilate;

  /// Horizontal morphology radius (`radius` X).
  ///
  /// 水平形态学半径（`radius` X 分量）。
  final double radiusX;

  /// Vertical morphology radius (`radius` Y).
  ///
  /// 垂直形态学半径（`radius` Y 分量）。
  final double radiusY;

  /// Creates an [SvgFeMorphology] with [isDilate], [radiusX], and [radiusY].
  ///
  /// 创建 [SvgFeMorphology]，指定模式 [isDilate] 及半径 [radiusX]、[radiusY]。
  const SvgFeMorphology({
    super.inSource,
    super.result,
    this.isDilate = false,
    this.radiusX = 0.0,
    this.radiusY = 0.0,
  });
}

/// Transfer function type for `<feFuncR|G|B|A type="...">`.
///
/// `<feFuncR|G|B|A type="...">` 的单通道映射函数类型。
enum SvgFeTransferFuncType {
  /// Leaves the channel unchanged (`C' = C`).
  ///
  /// 恒等映射，通道保持不变（`C' = C`）。
  identity,

  /// Linear affine mapping (`C' = slope * C + intercept`).
  ///
  /// 线性仿射映射（`C' = slope * C + intercept`）。
  linear,

  /// Gamma power curve (`C' = amplitude * pow(C, exponent) + offset`).
  ///
  /// Gamma 幂函数映射（`C' = amplitude * pow(C, exponent) + offset`）。
  gamma,

  /// Piecewise linear lookup table interpolation (`tableValues`).
  ///
  /// 分段线性查找表插值（`tableValues`）。
  table,

  /// Step-function discrete lookup table (`tableValues`).
  ///
  /// 阶梯式离散查找表映射（`tableValues`）。
  discrete,
}

/// Precompiled channel transfer function inside `<feComponentTransfer>`.
///
/// `<feComponentTransfer>` 内单个通道（R/G/B/A）的预编译传递函数。
class SvgFeTransferFunc {
  /// Transfer function type (`type`).
  ///
  /// 传递函数类型（`type`）。
  final SvgFeTransferFuncType type;

  /// Linear multiplier for [SvgFeTransferFuncType.linear] (`slope`).
  ///
  /// [SvgFeTransferFuncType.linear] 模式的斜率（`slope`）。
  final double slope;

  /// Linear additive offset for [SvgFeTransferFuncType.linear] (`intercept`).
  ///
  /// [SvgFeTransferFuncType.linear] 模式的截距（`intercept`）。
  final double intercept;

  /// Amplitude multiplier for [SvgFeTransferFuncType.gamma] (`amplitude`).
  ///
  /// [SvgFeTransferFuncType.gamma] 模式的振幅（`amplitude`）。
  final double amplitude;

  /// Power exponent for [SvgFeTransferFuncType.gamma] (`exponent`).
  ///
  /// [SvgFeTransferFuncType.gamma] 模式的指数（`exponent`）。
  final double exponent;

  /// Additive offset for [SvgFeTransferFuncType.gamma] (`offset`).
  ///
  /// [SvgFeTransferFuncType.gamma] 模式的偏移量（`offset`）。
  final double offset;

  /// Lookup table values for `table` and `discrete` modes (`tableValues`).
  ///
  /// `table` 与 `discrete` 模式使用的查找表数值（`tableValues`）。
  final Float64List tableValues;

  /// Creates an [SvgFeTransferFunc] with [type] and optional curve parameters
  /// ([slope], [intercept], [amplitude], [exponent], [offset], [tableValues]).
  ///
  /// 创建 [SvgFeTransferFunc]，配置函数类型 [type] 及可选曲线参数（[slope]、[intercept]、[amplitude]、[exponent]、[offset]、[tableValues]）。
  SvgFeTransferFunc({
    this.type = SvgFeTransferFuncType.identity,
    this.slope = 1.0,
    this.intercept = 0.0,
    this.amplitude = 1.0,
    this.exponent = 1.0,
    this.offset = 0.0,
    Float64List? tableValues,
  }) : tableValues = tableValues ?? Float64List(0);

  /// Approximates this channel transfer as `(scale, bias255)` for `ColorFilter.matrix`.
  ///
  /// 将当前通道传递函数近似为适用于 `ColorFilter.matrix` 的 `(scale, bias255)` 仿射行参数。
  (double, double) toAffineRow() {
    switch (type) {
      case SvgFeTransferFuncType.identity:
        return (1.0, 0.0);
      case SvgFeTransferFuncType.linear:
        return (slope, intercept * 255.0);
      case SvgFeTransferFuncType.gamma:
        // First-order affine approximation around mid-tone for GPU ColorFilter
        final s = amplitude * exponent;
        final b = (offset + amplitude * (1.0 - exponent) * 0.5) * 255.0;
        return (s, b);
      case SvgFeTransferFuncType.table:
      case SvgFeTransferFuncType.discrete:
        if (tableValues.length >= 2) {
          final v0 = tableValues.first;
          final v1 = tableValues.last;
          return (v1 - v0, v0 * 255.0);
        }
        if (tableValues.length == 1) {
          return (0.0, tableValues.first * 255.0);
        }
        return (1.0, 0.0);
    }
  }
}

/// Precompiled `<feComponentTransfer>` with optional `<feFuncR>`, `<feFuncG>`,
/// `<feFuncB>`, and `<feFuncA>` channel functions.
///
/// 预编译的 `<feComponentTransfer>` 通道分量重映射滤镜图元。
final class SvgFeComponentTransfer extends SvgFilterPrimitive {
  /// Optional red channel transfer function (`<feFuncR>`).
  ///
  /// 可选红通道传递函数（`<feFuncR>`）。
  final SvgFeTransferFunc? funcR;

  /// Optional green channel transfer function (`<feFuncG>`).
  ///
  /// 可选绿通道传递函数（`<feFuncG>`）。
  final SvgFeTransferFunc? funcG;

  /// Optional blue channel transfer function (`<feFuncB>`).
  ///
  /// 可选蓝通道传递函数（`<feFuncB>`）。
  final SvgFeTransferFunc? funcB;

  /// Optional alpha channel transfer function (`<feFuncA>`).
  ///
  /// 可选透明通道传递函数（`<feFuncA>`）。
  final SvgFeTransferFunc? funcA;

  /// Creates an [SvgFeComponentTransfer] with optional per-channel functions
  /// ([funcR], [funcG], [funcB], [funcA]).
  ///
  /// 创建 [SvgFeComponentTransfer]，配置可选的 RGBA 通道函数（[funcR]、[funcG]、[funcB]、[funcA]）。
  const SvgFeComponentTransfer({
    super.inSource,
    super.result,
    this.funcR,
    this.funcG,
    this.funcB,
    this.funcA,
  });
}

/// Precompiled `<feTurbulence type="fractalNoise|turbulence" baseFrequency="..." numOctaves="..." seed="..." stitchTiles="..." />` primitive.
///
/// 预编译的 `<feTurbulence>` 程序化 Perlin 噪声滤镜图元。
final class SvgFeTurbulence extends SvgFilterPrimitive {
  /// `true` for `type="fractalNoise"`; `false` for `type="turbulence"`.
  ///
  /// 为 `true` 表示分形噪声（`fractalNoise`），为 `false` 表示湍流噪声（`turbulence`）。
  final bool isFractalNoise;

  /// Horizontal base spatial frequency (`baseFrequency` X).
  ///
  /// 水平基础空间频率（`baseFrequency` X 分量）。
  final double baseFreqX;

  /// Vertical base spatial frequency (`baseFrequency` Y).
  ///
  /// 垂直基础空间频率（`baseFrequency` Y 分量）。
  final double baseFreqY;

  /// Number of noise octaves (`numOctaves`).
  ///
  /// 噪声倍频层数（`numOctaves`）。
  final int numOctaves;

  /// Pseudo-random generator seed (`seed`).
  ///
  /// 伪随机数种子（`seed`）。
  final int seed;

  /// Whether tile boundaries are seamlessly stitched (`stitchTiles="stitch"`).
  ///
  /// 是否开启无缝平铺拼接（`stitchTiles="stitch"`）。
  final bool stitchTiles;

  ui.Rect? _cachedRegion;
  SvgFilterPixelField? _cachedField;
  ui.Picture? _cachedPicture;

  /// Creates an [SvgFeTurbulence] with [isFractalNoise], [baseFreqX],
  /// [baseFreqY], [numOctaves], [seed], and [stitchTiles].
  ///
  /// 创建 [SvgFeTurbulence]，配置噪声类型 [isFractalNoise]、频率（[baseFreqX]、[baseFreqY]）、倍频数 [numOctaves]、种子 [seed] 与拼接选项 [stitchTiles]。
  SvgFeTurbulence({
    super.inSource,
    super.result,
    this.isFractalNoise = false,
    this.baseFreqX = 0.0,
    this.baseFreqY = 0.0,
    this.numOctaves = 1,
    this.seed = 0,
    this.stitchTiles = false,
  });

  /// Returns or builds the cached [SvgFilterPixelField] for [region].
  ///
  /// 返回或生成并缓存对应 [region] 的 [SvgFilterPixelField] 噪声像素场。
  SvgFilterPixelField resolveField(ui.Rect region) {
    if (_cachedField != null && _cachedRegion == region) {
      return _cachedField!;
    }
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedRegion = region;
    _cachedField = SvgFilterNoiseEngine.generateTurbulenceField(
      region: region,
      isFractalNoise: isFractalNoise,
      baseFreqX: baseFreqX,
      baseFreqY: baseFreqY,
      numOctaves: numOctaves,
      seed: seed,
      stitchTiles: stitchTiles,
    );
    return _cachedField!;
  }

  /// Returns or records the cached [ui.Picture] mesh for [region].
  ///
  /// 返回或录制并缓存对应 [region] 的噪声顶点网格 [ui.Picture]。
  ui.Picture resolvePicture(ui.Rect region) {
    final field = resolveField(region);
    if (_cachedPicture != null) return _cachedPicture!;
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec, region);
    SvgFilterNoiseEngine.paintFieldMesh(c, field);
    _cachedPicture = rec.endRecording();
    return _cachedPicture!;
  }

  /// Disposes the cached GPU [ui.Picture] and clears cached noise data.
  ///
  /// 释放缓存的 GPU [ui.Picture] 并清空噪声场缓存。
  void dispose() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedField = null;
    _cachedRegion = null;
  }
}

/// Precompiled `<feDisplacementMap in="..." in2="..." scale="..." xChannelSelector="..." yChannelSelector="..." />` primitive.
///
/// 预编译的 `<feDisplacementMap>` 像素置换映射滤镜图元。
final class SvgFeDisplacementMap extends SvgFilterPrimitive {
  /// Optional displacement map input source name (`in2`).
  ///
  /// 可选置换贴图输入源名称（`in2`）。
  final String? in2;

  /// Displacement scale factor in user units (`scale`).
  ///
  /// 用户坐标系下的置换缩放因子（`scale`）。
  final double scale;

  /// Color channel of [in2] driving horizontal displacement (`xChannelSelector`).
  ///
  /// 驱动水平方向位移的 [in2] 颜色通道（`xChannelSelector`）。
  final SvgChannelSelector xChannel;

  /// Color channel of [in2] driving vertical displacement (`yChannelSelector`).
  ///
  /// 驱动垂直方向位移的 [in2] 颜色通道（`yChannelSelector`）。
  final SvgChannelSelector yChannel;

  /// Creates an [SvgFeDisplacementMap] with [in2], [scale], [xChannel], and
  /// [yChannel].
  ///
  /// 创建 [SvgFeDisplacementMap]，指定置换源 [in2]、缩放系数 [scale] 及 X/Y 通道选择器（[xChannel]、[yChannel]）。
  const SvgFeDisplacementMap({
    super.inSource,
    super.result,
    this.in2,
    this.scale = 0.0,
    this.xChannel = SvgChannelSelector.a,
    this.yChannel = SvgChannelSelector.a,
  });
}

/// Precompiled `<filter>` graph definition (W3C Filter Effects Level 1).
///
/// 预编译的 `<filter>` 滤镜图定义（符合 W3C Filter Effects Level 1 规范）。
class SvgFilterNode {
  /// Unique `id` referenced by `filter="url(#id)"`.
  ///
  /// 供 `filter="url(#id)"` 引用的唯一标识 `id`。
  final String id;

  /// Coordinate space for the filter region (`filterUnits`).
  ///
  /// 滤镜区域的坐标空间单位（`filterUnits`）。
  final SvgGradientUnits filterUnits;

  /// Coordinate space for child primitive subregions (`primitiveUnits`).
  ///
  /// 子滤镜图元子区域的坐标空间单位（`primitiveUnits`）。
  final SvgGradientUnits primitiveUnits;

  /// Filter region X origin (`x`, defaults to `-0.1`).
  ///
  /// 滤镜区域 X 起点（`x`，默认 `-0.1`）。
  final double x;

  /// Filter region Y origin (`y`, defaults to `-0.1`).
  ///
  /// 滤镜区域 Y 起点（`y`，默认 `-0.1`）。
  final double y;

  /// Filter region width (`width`, defaults to `1.2`).
  ///
  /// 滤镜区域宽度（`width`，默认 `1.2`）。
  final double width;

  /// Filter region height (`height`, defaults to `1.2`).
  ///
  /// 滤镜区域高度（`height`，默认 `1.2`）。
  final double height;

  /// Ordered list of filter primitives executed in sequence.
  ///
  /// 按顺序执行的滤镜图元列表。
  final List<SvgFilterPrimitive> primitives;

  /// Creates an [SvgFilterNode] with [id], region parameters ([filterUnits],
  /// [primitiveUnits], [x], [y], [width], [height]), and [primitives].
  ///
  /// 创建 [SvgFilterNode]，配置唯一标识 [id]、区域参数（[filterUnits]、[primitiveUnits]、[x]、[y]、[width]、[height]）及图元列表 [primitives]。
  const SvgFilterNode({
    required this.id,
    this.filterUnits = SvgGradientUnits.objectBoundingBox,
    this.primitiveUnits = SvgGradientUnits.userSpaceOnUse,
    this.x = -0.1,
    this.y = -0.1,
    this.width = 1.2,
    this.height = 1.2,
    required this.primitives,
  });

  /// Resolves the filter region in user-space coordinates for [targetBounds].
  ///
  /// 根据目标包围盒 [targetBounds] 解析用户坐标系下的滤镜作用区域。
  ui.Rect resolveFilterRegion(ui.Rect targetBounds) {
    if (filterUnits == SvgGradientUnits.objectBoundingBox) {
      final w = targetBounds.width == 0.0 ? 100.0 : targetBounds.width;
      final h = targetBounds.height == 0.0 ? 100.0 : targetBounds.height;
      return ui.Rect.fromLTWH(
        targetBounds.left + x * w,
        targetBounds.top + y * h,
        width * w,
        height * h,
      );
    }
    return ui.Rect.fromLTWH(x, y, width, height);
  }

  /// Releases any cached procedural noise `ui.Picture` resources.
  ///
  /// 释放所有缓存的程序化噪声 `ui.Picture` GPU 资源。
  void dispose() {
    for (final prim in primitives) {
      if (prim is SvgFeTurbulence) {
        prim.dispose();
      }
    }
  }
}
