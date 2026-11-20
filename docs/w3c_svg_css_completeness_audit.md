# W3C SVG 1.1 / SVG 2 与 CSS 官方标准完整性核查报告（非 JS 引擎边界）

> 本文档对照 W3C 官方规范（[SVG 2](https://www.w3.org/TR/SVG2/)、[SVG 2 Document Structure](https://www.w3.org/TR/SVG2/struct.html)、[SVG 2 Styling](https://www.w3.org/TR/SVG2/styling.html)、[SVG 2 Paint Servers](https://www.w3.org/TR/SVG2/pservers.html)、[W3C Filter Effects Level 1](https://www.w3.org/TR/filter-effects-1/)、[MDN CSS Reference](https://developer.mozilla.org/en-US/docs/Web/CSS)）逐项核查 `lib/src/` 当前实现，列出所有**不涉及 JS 引擎、可在纯 Dart + `dart:ui` 中完整实现**的剩余漏项，并制定分阶段补齐计划。

---

## 一、已完整实现的核心标准能力（基线盘点）

- **结构与视口**：`<svg>`（含嵌套与根视口默认 `overflow: hidden`）、`<g>`、`<defs>`、`<symbol>`、`<use>`（深度样式继承、缓存隔离、单边尺寸等比推算、循环保护）、`<a>`、`<switch>`（`systemLanguage`/`requiredExtensions`）、`<view>`、`<title>`/`<desc>`/`<metadata>`。
- **基本图形与路径**：`<path>`（全命令 `M/L/H/V/C/S/Q/T/A/Z` 及路径变形）、`<rect>`（单边 `rx`/`ry` 回退）、`<circle>`、`<ellipse>`、`<line>`、`<polyline>`、`<polygon>`、`shape-rendering`、`paint-order`（`fill stroke` / `stroke fill`）。
- **文本系统**：`<text>`、`<tspan>`、`<textPath>`、混合内容、`x`/`y`/`dx`/`dy`/`rotate`、多基线、`text-anchor`、`textLength`/`lengthAdjust`、中英文排版与字体回退。
- **填充、描边与绘制服务器**：`<linearGradient>`、`<radialGradient>`（含 SVG 2 `fr`）、`<stop>`、`<pattern>`（`patternTransform`/`ImageShader`）、`<clipPath>`（`objectBoundingBox`）、`<mask>`（`luminance` Rec.709 & `alpha`）、`<marker>`（`start`/`mid`/`end`、`auto`/`auto-start-reverse`）、`<image>`（Base64 光栅 + 内嵌 SVG Data URI）。
- **颜色与混合**：`#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`、`rgb()`/`rgba()`、`hsl()`/`hsla()`（含 CSS Color 4 空格 `/` 与角度单位）、`hwb()`、147 种 SVG 命名色、`color` + `currentColor`、`mix-blend-mode`（16 种 W3C 混合模式）与 `isolation: isolate`。
- **滤镜引擎**：`<filter>` + 12 种 `fe*` 原语（`feGaussianBlur` + `edgeMode`、`feDropShadow`、`feOffset`、`feColorMatrix`、`feFlood`、`feBlend`、`feComposite` Porter-Duff、`feMerge`/`feMergeNode`、`feMorphology`、`feComponentTransfer` + `feFuncR/G/B/A`、`feTurbulence`、`feDisplacementMap`），以及 10 种 CSS `filter` 函数链。
- **声明式动画**：SMIL（`<animate>`、`<animateColor>`、`<animateTransform>`、`<animateMotion>` + `<mpath>`、`<set>`、`calcMode`/`keyTimes`/`keySplines`/`keyPoints`）与 CSS `@keyframes` / `animation`。

---

## 二、对照 W3C / CSS 官方标准的剩余可实现漏项（纯 Dart，不涉及 JS）

### 模块 A：CSS 选择器、层叠规则与变量（高优先级 — 现代 SVG 导出文件高频使用）

| 序号 | 标准特性 | 当前状态 | 纯 Dart 实现方案 |
|---|---|---|---|
| **A1** | **CSS 自定义属性 `--var` 与 `var(--name, fallback)`** | 未实现 | 在 `SvgStyle` 增加继承表 `customProperties`，在属性/声明解析阶段支持 `var()` 递归展开与回退值 |
| **A2** | **复合选择器、组合器、通配符与静态结构伪类** | `_parseSimpleSelector` 仅支持单一 `#id`/`.class`/`tag`，遇到空格、`>`、`+`、`~`、`:` 直接丢弃 | 扩展 `SvgCssSelector` 支持 `*`、复合选择器（`g.cls#id`）、后代 `A B`、子代 `A > B`、相邻兄弟 `A + B`、通用兄弟 `A ~ B`、属性选择器 `[attr]`/`[attr=val]`、以及静态伪类 `:root`、`:first-child`、`:last-child`、`:nth-child(an+b)`、`:not(...)`，按 W3C `(a, b, c)` 特异性排序 |
| **A3** | **CSS `!important` 优先级层叠** | 解析时直接截断丢弃 `!important`，未提升优先级 | 在声明与规则上标记 `important` 集合，按 W3C 层叠顺序覆盖普通声明 |
| **A4** | **SVG 2 几何属性作为 CSS 属性** | `x`/`y`/`width`/`height`/`cx`/`cy`/`r`/`rx`/`ry`/`d` 仅支持 XML 属性 | 在 `SvgCssParser` 解析几何 CSS 属性（含 `d: path("...")`），在构建各图形节点时优先取 CSS 声明值 |
| **A5** | **CSS `transform-box` 与独立变换属性** | 未支持 `transform-box` 及独立 `translate` / `rotate` / `scale` CSS 属性 | 支持 `transform-box: view-box \| fill-box` 决定 `transform-origin` 百分比参考框，支持 CSS Transforms Level 2 独立 `translate`/`rotate`/`scale` 属性 |

### 模块 B：CSS 颜色、数学函数与裁切/描边规范（中高优先级）

| 序号 | 标准特性 | 当前状态 | 纯 Dart 实现方案 |
|---|---|---|---|
| **B1** | **CSS Color 4 现代色域与混色函数** | 仅支持 sRGB（`hex`/`rgb`/`hsl`/`hwb`） | 纯数学实现 `oklch()`、`oklab()`、`lab()`、`lch()` 到 sRGB 转换与 `color-mix(in srgb\|oklch, ...)` |
| **B2** | **CSS 数学函数 `calc()` / `min()` / `max()` / `clamp()`** | 未实现 | 轻量表达式求值器，在长度、角度、百分比解析阶段求值 |
| **B3** | **CSS `clip-path` 基本形状函数** | `clip-path` 仅支持 `url(#id)` | 支持 `inset()`、`circle()`、`ellipse()`、`polygon()`、`path()` 直接编译为 `ui.Path` |
| **B4** | **Paint Server 回退色与完整渐变模板继承** | `fill="url(#g) red"` 未解析回退色；渐变 `href` 仅继承 `stops` | 支持 `url(#id) <fallback-color>`；`resolveTemplate` 递归链式继承 `x1/y1/x2/y2`、`cx/cy/r/fx/fy/fr`、`gradientUnits`、`spreadMethod`、`gradientTransform` |
| **B5** | **SVG 2 `vector-effect="non-scaling-stroke"` 与完整 `paint-order`** | 未支持 `non-scaling-stroke`；`paint-order` 仅支持 2 序（`markers` 固定最后） | `non-scaling-stroke` 根据当前总缩放系数反算描边宽；`paint-order` 支持 `fill`/`stroke`/`markers` 任意 3 层排列 |

### 模块 C：W3C Filter Effects Level 1 剩余 5 种原语与精细化规范（中优先级）

| 序号 | 标准特性 | 当前状态 | 纯 Dart 实现方案 |
|---|---|---|---|
| **C1** | **`<feImage>`** | 未实现 | 支持 Data URI 图像与文档内 `#id` 元素引用，按 `preserveAspectRatio` 渲染到滤镜缓冲 |
| **C2** | **`<feTile>`** | 未实现 | 将输入子区域光栅化为 `ui.Image` 并以 `ui.ImageShader(..., TileMode.repeated, TileMode.repeated)` 平铺填充滤镜区域 |
| **C3** | **`<feComposite operator="arithmetic">`** | 仅支持 Porter-Duff（`over/in/out/atop/xor/lighter`） | 实现 `result = k1*i1*i2 + k2*i1 + k3*i2 + k4` 像素合成缓冲 |
| **C4** | **`<feConvolveMatrix>`** | 未实现 | 纯 Dart 2D 卷积核（`order`、`kernelMatrix`、`divisor`、`bias`、`edgeMode`、`preserveAlpha`）+ 网格/图像缓存 |
| **C5** | **`<feDiffuseLighting>` & `<feSpecularLighting>`**（含 `<feDistantLight>` / `<fePointLight>` / `<feSpotLight>`） | 未实现 | 基于 Alpha 高度场梯度法线，纯 Dart 实现 Lambertian 漫反射与 Blinn-Phong 镜面高光（`surfaceScale`、`diffuseConstant`、`specularConstant`、`specularExponent`、`lighting-color`） |
| **C6** | **滤镜原语子区域（`x`/`y`/`width`/`height`）与 `primitiveUnits="objectBoundingBox"`** | 所有原语共享外层 `<filter>` 区域 | 每个 `SvgFilterPrimitive` 独立解析可选 `x`/`y`/`width`/`height`，并在 `objectBoundingBox` 下按目标包围盒缩放 `stdDeviation`/`dx`/`dy` |

### 模块 D：SMIL / CSS 声明式动画补全与文本细节（中优先级）

| 序号 | 标准特性 | 当前状态 | 纯 Dart 实现方案 |
|---|---|---|---|
| **D1** | **SMIL `additive="sum"` 与 `accumulate="sum"`** | 多个 `<animateTransform>` 会互相覆盖 | 支持叠加式变换与属性动画合成，以及跨循环周期的累积值计算 |
| **D2** | **SMIL Syncbase 链式定时（`begin="a1.end+0.5s"`）** | 仅支持绝对时钟偏移 | 在编译阶段构建动画依赖 DAG，解析 `id.begin±offset` 与 `id.end±offset` |
| **D3** | **CSS `steps(N, jump-*)` 精确步进曲线 + 负 `animation-delay` + `animation-play-state`** | `steps()` 仅作为离散布尔标志，未按 `N` 步量化 | 实现完整 W3C `steps(count, position)` 步进函数、负延迟从中间帧起播与 `paused` 冻结 |
| **D4** | **文本 `writing-mode`（竖排 `vertical-rl`/`vertical-lr`）与 `text-transform`** | 未实现 | 支持 `uppercase`/`lowercase`/`capitalize` 文本变换及基础竖排字形步进 |

---

## 三、明确不实现范围（涉及 JS 引擎或完整浏览器 DOM / HTML 引擎）

以下标准特性依赖 JavaScript 运行时、浏览器交互 DOM 或完整 HTML 排版引擎，**不纳入实现范围**：
1. `<script>` 脚本执行与 SVG DOM 编程接口（`getElementById`、`setAttribute`、`getTotalLength` 等）。
2. DOM 事件属性（`onclick`、`onload`、`onmouseover` 等）及 SMIL 事件触发定时（`begin="click"`、`begin="btn.mouseover"`）。
3. 动态交互伪类（`:hover`、`:active`、`:focus`、`:target`）。
4. `<foreignObject>` 内嵌 HTML/CSS 盒模型布局引擎。
5. 外部网络资源自动拉取（如 `<image href="https://...">`、`@import`、`@font-face` 远程字体下载）。

---

## 四、分阶段实施路线

1. **Stage 1（CSS 架构与选择/变量引擎）**：实现模块 A（`--var`/`var()`、完整 CSS 选择器与组合器、`!important`、SVG 2 CSS 几何属性、`transform-box` 与独立 `translate`/`rotate`/`scale`）。
2. **Stage 2（CSS Color 4 / Math / Clip / Paint Server）**：实现模块 B（`oklch`/`oklab`/`lab`/`lch`/`color-mix`、`calc/min/max/clamp`、CSS `clip-path` 基本形状、Paint Server 回退色与完整渐变模板继承、`non-scaling-stroke` 与完整 3 层 `paint-order`）。
3. **Stage 3（Filter Effects Level 1 全原语补齐）**：实现模块 C（`feImage`、`feTile`、`feComposite arithmetic`、`feConvolveMatrix`、`feDiffuseLighting`/`feSpecularLighting` + 3 种光源、原语子区域与 `primitiveUnits`）。
4. **Stage 4（SMIL / CSS 动画与文本高级特性）**：实现模块 D（`additive="sum"`/`accumulate="sum"`、Syncbase `id.end+offset` 链式定时、精确 `steps(N, ...)`、负延迟/`animation-play-state`、`text-transform` & 竖排 `writing-mode`）。
