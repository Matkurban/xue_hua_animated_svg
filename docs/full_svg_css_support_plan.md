# `example/assets/full_svg` 诊断报告与纯 Dart SVG/CSS 能力补齐计划

> 本文档基于对 `example/assets/full_svg/` 下全部 **42 个真实 SVG 素材** 与当前 `lib/src/` 渲染引擎的逐项代码审计生成。  
> 结论：**全部 42 个素材均不包含 `<script>`，100% 为纯 SVG + CSS 声明式图形，不依赖 JS 引擎，均可在纯 Dart + Flutter `dart:ui` 中完整实现。**

---

## 一、现状根因诊断（为什么 42 个素材大多不显示或颜色异常）

通过扫描全部 42 个 `.svg` 文件并对照 `lib/src/parser/` 与 `lib/src/model/` 源码，定位到以下 **5 类核心问题**：

| 序号 | 根因 | 受影响素材数量 / 示例 | 当前引擎行为 |
|---|---|---|---|
| **1** | **不支持 `hsl()` / `hsla()` 颜色语法** | **39 / 42 个文件**（1,177 处 `fill`、6 处 `stroke`、58 处 `stop-color`），如 `bbblurry`、`ccchaos`、`cccircular`、`ffflurry`、`nnneon`、`ssscales` 等 | `SvgCssValueParser.parseColor()` 仅支持 `#hex`、`rgb()`/`rgba()` 与命名颜色，遇到 `hsl(...)` 返回 `null`，导致填充和渐变停靠点全部退化为黑色 `#000000` 或透明 |
| **2** | **`<use>` 实例化 `<symbol>` 存在三处缺陷** | `bbburst.svg`（111 处单边 `width` 的 `<use>`）、`iiisometric.svg`（60+ 处多色 `<use>`） | ① `SvgUseNode` 仅同步了 `<symbol>` 自身样式，未递归同步到子图形；② 子图形 `shouldCacheStaticPicture` 缓存了首个 `<use>` 的颜色，导致后续不同颜色的 `<use>` 全部画成同色；③ `<use width="...">` 省略 `height` 时，未按 `<symbol viewBox>` 宽高比推算 `height`，导致尺寸错位与 `objectBoundingBox` 滤镜区域偏移 |
| **3** | **缺少 `<feTurbulence>` 与 `<feDisplacementMap>` 滤镜原语，且 `feGaussianBlur` 未处理 `edgeMode`** | `ffflux.svg`、`gggrain.svg`、`ssspot.svg` | `_buildFilterPrimitive` 忽略了 `feTurbulence` 与 `feDisplacementMap`，导致以噪点为起点的滤镜管线直接对透明 `SourceGraphic` 求值（整图空白或失去纹理/扭曲效果）；`feGaussianBlur` 的 `edgeMode="duplicate"` 未映射到 `ui.TileMode.clamp` |
| **4** | **缺少 CSS `mix-blend-mode` 混合模式** | `gggrain.svg`（`style="mix-blend-mode: soft-light"`）及通用现代 SVG | `SvgCssParser` 与 `SvgStyle` 未解析 `mix-blend-mode`，`SvgElement._paintInternal` 未通过 `saveLayer(Paint()..blendMode)` 合成 |
| **5** | **部分 CSS / SVG 视觉属性与边界行为未补齐** | `iiisometric.svg`（`shape-rendering="crispEdges"`）、`sssplatter.svg`（`fill="undefined"` 容错）、以及通用 SVG 中的 `currentColor`、CSS `filter` 函数链、`<rect>` 单边 `rx`/`ry` 等 | 缺少对应属性解析或渲染分支，影响还原度与通用兼容性 |

---

## 二、纯 Dart 可实现的 SVG / CSS 效果清单与明确边界

### A. 可在纯 Dart (`dart:ui`) 中完整实现的能力

1. **CSS Color Level 4 颜色系统**
   - `hsl(h, s%, l%)` / `hsla(h, s%, l%, a)` 与现代空格语法 `hsl(h s% l% / a)`
   - 色相角度单位：`deg`、`rad`、`grad`、`turn` 及负角度/超过 360° 归一化
   - `hwb(h w% b% / a)`
   - `color` 属性继承与 `currentColor` 关键字（支持 `fill`、`stroke`、`stop-color`、`flood-color`）
   - 无效颜色值（如 `fill="undefined"`）按 W3C 规范安全回退

2. **`<use>` 与 `<symbol>` 完整实例化语义**
   - `<use>` 向 `<symbol>` / `<g>` 子树深度继承 `fill`、`stroke`、`fill-opacity`、`stroke-opacity`、`stroke-width` 等可继承属性，且实例之间互不污染
   - `<defs>` / `<symbol>` 内部子树在 `<use>` 实例化时正确隔离 `ui.Picture` 缓存
   - `<use>` 仅声明 `width` 或仅声明 `height` 时，按目标 `<symbol>` 的 `viewBox` 宽高比自动推导另一维度，并正确更新 `cachedBounds` 以保证 `filterUnits="objectBoundingBox"` 区域精确

3. **W3C Filter Effects 程序化噪点与置换滤镜（纯 Dart 离线光栅化 + 结果缓存）**
   - `<feTurbulence>`：`type="fractalNoise" | "turbulence"`、`baseFrequency="fx [fy]"`、`numOctaves`、`seed`、`stitchTiles="stitch" | "noStitch"`（按 W3C Filter Effects Level 1 §9.22 标准 Perlin 梯度噪点算法生成并缓存 `ui.Image`）
   - `<feDisplacementMap>`：`in`、`in2`、`scale`、`xChannelSelector`、`yChannelSelector`（双线性采样位移映射并缓存 `ui.Image`）
   - `<feGaussianBlur>` 支持 `edgeMode="none" | "duplicate" | "wrap"`（映射 `ui.TileMode.decal` / `clamp` / `repeated`）
   - `<feComponentTransfer>` 在 `table` / `discrete` / `gamma` 模式下支持精确 LUT 或分段映射，完善 `linear`（`slope` + `intercept`）对噪点对比度的处理

4. **CSS 混合模式与合成属性**
   - `mix-blend-mode`：支持全部 16 种 W3C 混合模式（`normal`、`multiply`、`screen`、`overlay`、`darken`、`lighten`、`color-dodge`、`color-burn`、`hard-light`、`soft-light`、`difference`、`exclusion`、`hue`、`saturation`、`color`、`luminosity`），通过 `canvas.saveLayer` + `ui.BlendMode` GPU 硬件加速合成
   - `isolation: isolate`：创建独立合成层

5. **CSS 图形渲染与滤镜函数补充**
   - CSS `filter` 函数链：`blur()`、`brightness()`、`contrast()`、`grayscale()`、`saturate()`、`sepia()`、`hue-rotate()`、`invert()`、`opacity()`、`drop-shadow()`（通过 `ui.ImageFilter` / `ui.ColorFilter.matrix` 组合实现）
   - `shape-rendering`：`crispEdges` / `optimizeSpeed` 关闭抗锯齿（`isAntiAlias = false`），`auto` / `geometricPrecision` 开启抗锯齿
   - `paint-order` 扩展到所有几何图形节点（`SvgGeometryNode`，不仅限于 `<text>`）
   - `<rect>` 单边 `rx`/`ry` 规范补全（仅设 `rx` 时 `ry = rx`，反之亦然，并限制在 `width/2`、`height/2` 内）

### B. 明确不实现（涉及 JS 引擎或完整浏览器 DOM/HTML 引擎）

- `<script>` 脚本执行与动态 DOM 修改（`document.getElementById`、`setAttribute` 等）
- JS 事件回调属性（`onclick`、`onload`、`onmouseover` 等）
- 依赖浏览器 DOM 状态机的交互伪类（`:hover`、`:active`、`:focus`）
- `<foreignObject>` 内嵌 HTML/CSS 盒模型排版引擎

---

## 三、分阶段实现计划

### Phase 1（P0 — 立刻修复 39/42 个素材的颜色与 `<use>`/`<symbol>` 渲染）

**目标**：让绝大部分素材（含所有渐变、几何、图标、模糊、霓虹、等距、星爆类 SVG）恢复完全正确的颜色与位置。

1. **完善 CSS Color 4 颜色解析**（`lib/src/parser/svg_css_value_parser.dart`、`lib/src/model/svg_style.dart`、`lib/src/parser/svg_css_parser.dart`）
   - 实现 `hsl()` / `hsla()`（兼容逗号与空格 `/` 语法、色相角度单位与环绕）与 `hwb()` 解析。
   - 增加 `color` 继承属性与 `currentColor` 解析支持。
2. **修复 `<use>` + `<symbol>` 实例化渲染**（`lib/src/model/svg_container_nodes.dart`、`lib/src/model/svg_viewport_nodes.dart`、`lib/src/model/svg_element.dart`）
   - 为 `SvgElement` 增加递归样式同步辅助方法，使 `<use>` 的 `fill`/`stroke`/`opacity` 正确透传到 `<symbol>`/`<g>` 内部所有子图形，并在绘制完成后恢复，避免多实例串色。
   - 在 `<symbol>` 实例化链路中禁用/绕过子节点的静态 `cachedPicture` 复用，防止首个 `<use>` 锁死后续实例颜色。
   - 修复 `<use>` 单边 `width` 或 `height` 时的等比推导逻辑及 `cachedBounds` 计算。
3. **补齐 `<rect>` 单边 `rx`/`ry` 与 `shape-rendering`**（`lib/src/model/svg_shape_nodes.dart`、`lib/src/model/svg_geometry_node.dart`）
   - `SvgRectNode` 支持仅声明 `rx` 或仅声明 `ry` 时的自动等值回退。
   - 支持 `shape-rendering="crispEdges"` 切换 `isAntiAlias`。
4. **单元测试**（`test/svg_full_assets_phase1_test.dart`）
   - 覆盖 `hsl()`/`hsla()`/`hwb()`/`currentColor`、多色 `<use>` + 单边 `width` `<symbol>`、以及 `bbblurry.svg`、`ccchaos.svg`、`bbburst.svg`、`iiisometric.svg` 的真实文件像素断言。

---

### Phase 2（P1 — 混合模式与滤镜引擎升级：`mix-blend-mode`、`feTurbulence`、`feDisplacementMap`）

**目标**：完整支持 `ffflux.svg`、`gggrain.svg`、`ssspot.svg` 等复杂滤镜纹理与混合模式效果。

1. **实现 CSS `mix-blend-mode` 与 `isolation`**（`lib/src/model/svg_style.dart`、`lib/src/parser/svg_css_parser.dart`、`lib/src/model/svg_element.dart`）
   - 解析全部 16 种 W3C 混合模式与 `isolation: isolate`。
   - 在 `SvgElement._paintInternal` 中，当 `mixBlendMode != srcOver` 或 `isolation == isolate` 时通过 `canvas.saveLayer` 正确合成。
2. **实现 `<feTurbulence>` 纯 Dart 标准噪点原语**（`lib/src/model/svg_filter_node.dart`、`lib/src/model/svg_filter_executor.dart`、`lib/src/parser/svg_xml_parser.dart`）
   - 按 W3C Filter Effects Level 1 规范实现 `fractalNoise` / `turbulence`、`baseFrequency`、`numOctaves`、`seed`、`stitchTiles`。
   - 使用固定分辨率上限（如最大 512px 等比缩放）光栅化并按参数+区域缓存 `ui.Image`，兼顾视觉精度与 60fps 性能。
   - 在 `SvgFilterNode.dispose()` / `SvgDocument.dispose()` 中统一释放缓存 `ui.Image`。
3. **实现 `<feDisplacementMap>` 与 `feGaussianBlur edgeMode`**（`lib/src/model/svg_filter_node.dart`、`lib/src/model/svg_filter_executor.dart`、`lib/src/parser/svg_xml_parser.dart`）
   - 实现 `feDisplacementMap` 的 `scale`、`xChannelSelector`、`yChannelSelector` 双线性置换并缓存结果。
   - `feGaussianBlur` 解析 `edgeMode`（`duplicate` → `ui.TileMode.clamp`，`wrap` → `ui.TileMode.repeated`，`none` → `ui.TileMode.decal`）。
   - 修复多步骤滤镜中 `in="SourceGraphic"` 与 `in2="blur"` 的混合顺序及透明背景起始管线（如 `gggrain.svg`）。
4. **单元测试**（`test/svg_full_assets_phase2_test.dart`）
   - 覆盖 `mix-blend-mode`、`feTurbulence`、`feDisplacementMap`、`edgeMode`，并对 `ffflux.svg`、`gggrain.svg`、`ssspot.svg` 进行真实文件渲染与像素断言。

---

### Phase 3（P2 — 通用 CSS 视觉增强与全部 42 个素材回归测试）

**目标**：补齐常见纯 CSS 滤镜函数与绘制顺序属性，并建立 42 个素材的全量回归测试套件。

1. **CSS `filter` 函数链支持**（`lib/src/parser/svg_css_value_parser.dart`、`lib/src/model/svg_style.dart`、`lib/src/model/svg_element.dart`）
   - 支持在 `filter` 属性中直接书写 `blur()`、`brightness()`、`contrast()`、`grayscale()`、`saturate()`、`sepia()`、`hue-rotate()`、`invert()`、`opacity()`、`drop-shadow()` 及多函数串联。
2. **几何节点 `paint-order` 支持**（`lib/src/model/svg_geometry_node.dart`）
   - 支持 `fill stroke markers` / `stroke fill markers` 等任意绘制顺序组合。
3. **全量 42 素材回归验证**（`test/svg_full_assets_regression_test.dart`）
   - 批量编译并离屏渲染 `example/assets/full_svg/` 下全部 42 个 SVG，验证零异常、非空白像素覆盖率以及关键视觉区域颜色正确性。

---

## 四、验收标准

- `flutter analyze` 在插件根目录与 `example/` 目录均为 **0 issues**。
- `flutter test` 全部既有测试与新增 Phase 1–3 测试全部通过。
- 在示例 App「全屏素材」Tab 中，42 个素材卡片与全屏沉浸页均能正确显示预期颜色、渐变、图案、滤镜模糊、颗粒噪点与混合效果。
