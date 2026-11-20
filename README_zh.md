# xue_hua_animated_svg

[English](README.md) | [中文](README_zh.md)

面向 Flutter 的高性能、**零原生依赖**、100% 纯 Dart 动态 SVG 渲染引擎。
在解析期将 W3C SVG 2、SMIL 与 CSS 预编译为强类型 AST，并以 **60fps / 120fps** 绘制；
支持静态子树 `Picture` 缓存与零堆分配渲染循环。

**在线演示（GitHub Pages）：** https://matkurban.github.io/xue_hua_animated_svg/

## 特性

1. **解析期指令预编译** — XML、CSS 选择器、`var()` 自定义变量、CSS Color 4、`calc()`/`min()`/`max()`/`clamp()`、Path `d` 与 SMIL/CSS 时间值在 `SvgParser.compile()` 一次性解析，运行时绘制零字符串解析。
2. **静态子树 Picture 缓存** — `isAnimated == false` 的节点首次绘制录制成 `ui.Picture`，后续 `drawPicture` 复用；内嵌异步 `<image>` 解码完成后自动失效并重绘。
3. **PathMetrics 预计算** — 虚线描边与运动路径缓存 `PathMetric`，每帧只做轻量切片/切线查询。
4. **零分配渲染循环** — Paint、图层透明度与 4×4 列主序矩阵在每帧原地更新。
5. **完整无 JS 的 W3C SVG 2 + 滤镜 + SMIL + CSS 支持** — 覆盖 W3C Filter Effects Level 1 全部 17 个滤镜原语与 10 个 CSS `filter` 函数、W3C Selectors Level 4 静态选择器、`--*`/`var()`、`!important` 级联、CSS Color 4（`oklch`/`oklab`/`lab`/`lch`/`hsl`/`hwb`/`color-mix`）、CSS `clip-path` 几何裁剪、完整 `<text>`/`<tspan>`/`<textPath>` 排版、SMIL `additive`/`accumulate` 与 Syncbase 链式同步、CSS `@keyframes`（`steps()`、负延迟、`animation-play-state`）。

## 安装

```yaml
dependencies:
  xue_hua_animated_svg: ^1.3.0
```

```bash
flutter pub get
```

## 快速上手

```dart
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

final controller = AnimatedSvgController(autoPlay: true, speed: 1.0);

// 使用内置 CyberCore 合成演示字符串
AnimatedSvgPicture.string(
  AnimatedSvgShowcasePresets.cyberCoreCompositeSvg,
  controller: controller,
  width: 280,
  height: 280,
);

// 或从 Flutter asset 加载
AnimatedSvgPicture.asset(
  'assets/svgs/elephant.svg',
  controller: controller,
  width: 280,
  height: 280,
);

// 从网络 URL 加载（Web + IO）
AnimatedSvgPicture.network(
  'https://example.com/motion.svg',
  headers: {'Authorization': 'Bearer …'}, // 可选
  controller: controller,
  width: 280,
  height: 280,
);

// 从本地文件加载（需要 dart:io，Web 不可用）
AnimatedSvgPicture.file(
  File('/path/to/motion.svg'), // dart:io File；Web 不可用
  controller: controller,
  width: 280,
  height: 280,
);
```

### 播放控制

```dart
controller.play();
controller.pause();
controller.reset();
controller.seek(const Duration(milliseconds: 500));
controller.setSpeed(2.0);

final progress = controller.cycleProgress; // 0.0 .. 1.0
final elapsed = controller.elapsed;
```

### 提前编译

```dart
final scene = SvgParser.compile(svgXml);
AnimatedSvgPicture.compiled(scene, controller: controller);
// 用完后：
scene.dispose();
```

## 公开 API

| API                                                                         | 作用                                             |
|-----------------------------------------------------------------------------|--------------------------------------------------|
| `AnimatedSvgPicture.string` / `.asset` / `.file` / `.network` / `.compiled` | 组件入口                                         |
| `AnimatedSvgController`                                                     | `play` / `pause` / `seek` / `reset` / `setSpeed` |
| `SvgParser.compile`                                                         | 预编译 SVG → `CompiledSvgScene`                  |
| `AnimatedSvgShowcasePresets.cyberCoreCompositeSvg`                          | 合成演示 SVG 字符串                              |

### 布局、着色与视图：`fit` / `alignment` / `colorFilter` / `viewId`

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `fit` | `BoxFit` | `BoxFit.contain` | 将 SVG 固有尺寸铭刻进组件布局框（`applyBoxFit`）。 |
| `alignment` | `AlignmentGeometry` | `Alignment.center` | 将拟合后的矩形放入剩余 / 裁剪空间（`alignment.inscribe`）。 |
| `colorFilter` | `ColorFilter?` | `null` | Flutter 整图后处理着色（如 `ColorFilter.mode(color, BlendMode.srcIn)`），与 SVG `<filter>` 相互独立。 |
| `viewId` | `String?` | `null` | 可选指定 `<view id="...">` 以切换 `viewBox` 与 `preserveAspectRatio`。 |

```dart
AnimatedSvgPicture.asset(
  'assets/svgs/elephant.svg',
  width: 280,
  height: 160,
  fit: BoxFit.cover,
  alignment: Alignment.topLeft,
  colorFilter: const ColorFilter.mode(Color(0xFF22C55E), BlendMode.srcIn),
);
```

## 支持的 SVG 2 与 CSS 能力

解析器会编入场景图的标签与规范特性：

| 类别 | 支持 |
|------|------|
| 结构与视图 | `<svg>`（根与嵌套视口，遵循 W3C 默认 `overflow: hidden` 视口裁剪）、`<g>`、`<defs>`、`<symbol>`、`<use>`（支持 `width`/`height`、单维度比例缩放、深层样式隔离与防循环引用）、`<a>`、`<switch>`、`<view>`（可通过 `viewId` 切换） |
| 几何与绘制规则 | `<path>`、`<rect>`、`<circle>`、`<ellipse>`、`<line>`、`<polyline>`、`<polygon>`；SVG 2 CSS 几何属性（`x`、`y`、`width`、`height`、`cx`、`cy`、`r`、`rx`、`ry`、`d: path(...)`）；`vector-effect="non-scaling-stroke"`；三层 `paint-order`（`fill` / `stroke` / `markers`）；`shape-rendering`；`mix-blend-mode` 与 `isolation` |
| 文本 | `<text>`、`<tspan>`、`<textPath>`（完整支持字体、基线、锚点、`letter-spacing`/`word-spacing`、`text-decoration`、`direction`、`xml:space`/`white-space`、`text-transform`、竖排 `writing-mode`（`vertical-rl`/`vertical-lr`/`tb`/`tb-rl`）、`x`/`y`/`dx`/`dy`/`rotate` 列表、`textLength`/`lengthAdjust` 与 `paint-order`） |
| 画刷、裁剪与遮罩 | `<linearGradient>`、`<radialGradient>`（含 SVG 2 `fr` 与多级 `href` 模板继承）、`<stop>`、`<pattern>`、`<marker>`（`marker-start`/`mid`/`end`、`orient="auto"`/`"auto-start-reverse"`）、`<clipPath>`（`userSpaceOnUse` 与 `objectBoundingBox`）、CSS `clip-path` 形状（`inset`/`circle`/`ellipse`/`polygon`/`path`）、`<mask>`（`luminance` 与 `alpha`）、`url(#id) <fallback>` 与 `currentColor` |
| 位图与内联图 | `<image>`（支持 `data:image/png|jpeg|webp|gif;base64,...` 与 `data:image/svg+xml,...`） |
| 滤镜管线（全部 17 个 W3C Level 1 原语 + 10 个 CSS 函数） | `<filter>`（支持 `filterUnits`、`primitiveUnits` 与原语级 `x`/`y`/`width`/`height` 子区域裁剪）：`<feGaussianBlur>`（含 `edgeMode`）、`<feDropShadow>`、`<feOffset>`、`<feColorMatrix>`、`<feFlood>`、`<feBlend>`、`<feComposite>`（含 `operator="arithmetic"`）、`<feMerge>`、`<feMergeNode>`、`<feMorphology>`、`<feComponentTransfer>`（`<feFuncR/G/B/A>`）、`<feTurbulence>`、`<feDisplacementMap>`、`<feImage>`、`<feTile>`、`<feConvolveMatrix>`、`<feDiffuseLighting>`、`<feSpecularLighting>`（`<feDistantLight>`、`<fePointLight>`、`<feSpotLight>`）；CSS `filter:`（`blur`、`drop-shadow`、`brightness`、`contrast`、`grayscale`、`saturate`、`sepia`、`hue-rotate`、`invert`、`opacity`） |
| CSS 选择器、色彩与数学函数 | `<style>`、内联 `style="..."`、`!important` 六阶段级联；W3C Selectors Level 4 静态选择器（组合器 ` ` / `>` / `+` / `~`、属性选择器 `[attr=val]` / `^=` / `$=` / `*=` / `~=` / `|=`、结构伪类 `:first-child` / `:last-child` / `:only-child` / `:nth-child(An+B)` / `:nth-last-child` / `:first-of-type` / `:last-of-type` / `:nth-of-type` / `:empty` / `:root`、`:not()` / `:is()` / `:where()`）；CSS 自定义变量（`--*` 与 `var()`）；CSS Color 4（`hsl`/`hsla`/`hwb`/`oklab`/`oklch`/`lab`/`lch`/`color-mix`）；CSS 数学函数（`calc`/`min`/`max`/`clamp`）；`transform-origin`、`transform-box`、独立 `translate`/`rotate`/`scale` |
| SMIL 与 CSS 动画 | `<animate>`、`<animateColor>`、`<animateTransform>`、`<animateMotion>`、`<mpath>`、`<set>`；`additive="sum"`、`accumulate="sum"`、SMIL Syncbase 链式同步（`begin="anim1.end+0.5s"`）；CSS `@keyframes`、`steps(N, jump-start|jump-end|jump-none|jump-both|start|end)`、`step-start`/`step-end`、负 `animation-delay`、`animation-play-state: paused|running` |

元数据：`<style>` 正文会解析；`<title>`、`<desc>`、`<metadata>` 忽略不绘制。

## Out-of-Scope（明确边界）

仅依赖 JavaScript 引擎、浏览器交互 DOM、外部网络样式/字体加载或 SVG 2 已废弃的规范不在本引擎范围内：

| 不支持项 | 原因 |
|----------|------|
| `<script>` 与 JS DOM API | 不含 JavaScript 执行引擎 |
| 交互事件与动态伪类（`onclick`、`begin="btn.click"`、`:hover`、`:active`、`:focus`） | 不含浏览器交互 DOM / 命中状态机 |
| `<foreignObject>` | 不嵌入 HTML / CSS 排版引擎 |
| `@media`、`@import`、`@font-face` | 不含外部网络样式/字体加载与媒体查询运行时 |
| 已废弃的 SVG 1.1 字体/引用标签 | `<font>`、`<glyph>`、`<missing-glyph>`、`<hkern>`、`<vkern>`、`<tref>`（SVG 2 已移除） |

## 许可证

见 [LICENSE](LICENSE)。
