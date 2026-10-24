# xue_hua_animated_svg

[English](README.md) | [中文](README_zh.md)

面向 Flutter 的高性能、**零原生依赖**、100% 纯 Dart 动态 SVG 渲染引擎。
在解析期将 SMIL / CSS 动效预编译为强类型 AST，并以 **60fps / 120fps** 绘制；
支持静态子树 `Picture` 缓存与零堆分配渲染循环。

**在线演示（GitHub Pages）：** https://matkurban.github.io/xue_hua_animated_svg/

## 特性

1. **解析期指令预编译** — XML、CSS、颜色、Path `d`、时间单位在 `SvgParser.compile()` 一次性完成，
   运行时绘制不再解析字符串。
2. **静态子树 Picture 缓存** — `isAnimated == false` 的节点首次绘制录制成 `ui.Picture`，后续
   `drawPicture` 复用。
3. **PathMetrics 预计算** — 虚线描边与运动路径缓存 `PathMetric`，每帧只做轻量切片/切线查询。
4. **零分配渲染循环** — Paint、图层透明度与 4×4 列主序矩阵在每帧原地更新。
5. **SMIL + CSS** — `<animate>`、`<animateTransform>`、`<animateMotion>` / `<mpath>`、
   同构 path 形变、`pathLength` 描边生长、CSS `@keyframes` 与 `transform-origin`。

## 安装

```yaml
dependencies:
  xue_hua_animated_svg: ^1.1.0
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

### 布局与着色：`fit` / `colorFilter`

与 `flutter_svg` / `SvgPicture` 对齐：

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `fit` | `BoxFit` | `BoxFit.contain` | 将 SVG 固有尺寸铭刻进组件布局框（`applyBoxFit`，居中）。 |
| `colorFilter` | `ColorFilter?` | `null` | Flutter 整图后处理着色（如 `ColorFilter.mode(color, BlendMode.srcIn)`）。**不是** SVG `<filter>`。 |

```dart
AnimatedSvgPicture.asset(
  'assets/svgs/elephant.svg',
  width: 280,
  height: 160,
  fit: BoxFit.cover,
  colorFilter: const ColorFilter.mode(Color(0xFF22C55E), BlendMode.srcIn),
);
```

## 支持的 SVG 表面

解析器会编入场景图的标签与能力（其余标签直接丢弃）：

| 类别 | 支持 |
|------|------|
| 结构 | `<svg>`、`<g>`、`<defs>`、`<symbol>`、`<use>` |
| 几何 | `<path>`、`<rect>`、`<circle>`、`<ellipse>`、`<line>`、`<polyline>`、`<polygon>` |
| 填充 | `<linearGradient>`、`<radialGradient>`、`<stop>`、`<clipPath>` |
| SMIL | `<animate>`、`<animateTransform>`、`<animateMotion>`、`<mpath>` |
| CSS | `<style>`、`@keyframes`；选择器**仅** `#id`、`.class`、`tagName`；CSS `filter: blur(...)`（模糊半径 → `MaskFilter`，不是 SVG 滤镜图） |

元数据：`<style>` 正文会解析；`<title>`、`<desc>`、`<metadata>` 忽略不绘制。

## Out-of-Scope（明确不做）

下列能力**明确不支持**。未知标签在解析期返回 `null` 并省略。**禁止**为它们扩展引擎（不要写完整 CSS 选择器词法/分析器，不要做半吊子文字排版）：

| 禁止项 | 原因 |
|--------|------|
| `<filter>` 及全部 `fe*` 图元（`feGaussianBlur`、`feBlend` 等） | 不做滤镜图；仅可选 CSS `blur()` 半径 |
| `<text>`、`<tspan>`、`<textPath>`、`<tref>` | 不做字形/文字排版 |
| `<foreignObject>` | 不嵌入 HTML / Flutter 子树 |
| 复杂 CSS 选择器 | 不做后代/子代/兄弟（` `、`>`、`+`、`~`）、属性选择器或伪类（`:hover`、`:nth-child` 等）；不做 `@media` / `@import` |
| 当前一并丢弃 | `<image>`、`<mask>`、`<marker>`、`<pattern>`、`<switch>`、`<a>`、`<script>`、`<view>`、`<set>`，以及一切未列入「支持」表的标签 |

请按「支持」表编写几何与 SMIL/CSS 动效 SVG。Out-of-Scope 为硬边界，不为它们补半吊子实现。

## 许可证

见 [LICENSE](LICENSE)。
