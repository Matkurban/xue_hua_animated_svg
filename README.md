# Animated SVG Engine (`xue_hua_animated_svg`)

零原生依赖、100% 纯 Dart 编写的高性能动态 SVG 渲染引擎插件，专为 Flutter 60fps / 120fps 满帧矢量动效渲染设计。

## 核心架构特性

1. **解析期指令预编译（Zero-String Parsing at Runtime）**
   - 所有 XML 词法解析、`<style>` / 内联 `style` 解析、颜色 Hex/RGB/命名色解析、SVG Path `d` 指令归一化、时钟单位（`ms`/`s`）与百分比转换均在 `SvgParser.compile()` 构建 AST 阶段一次性完成，转化为强类型的 `double`、`Color`、`Float64List`、`Int64List` 与 `Cubic` 对象。
2. **静态子树脏标记与图层缓存（Static Subtree Picture Caching）**
   - AST 初始化时自底向上冒泡计算 `isAnimated`（包含自身动画、子孙动画、动态渐变引用及 `<use>` 引用）。
   - 对 `isAnimated == false` 的静态 `<g>` 容器或静态图元，首次绘制时通过 `ui.PictureRecorder` 录制为 `ui.Picture` 缓存，后续帧直接调用 `canvas.drawPicture()`。
3. **`Path` 与 `PathMetrics` 预计算缓存（Cached PathMetrics）**
   - 每个图形节点预分配并缓存 `basePath` 与 `dashedStrokePath`。
   - 涉及 `stroke-dasharray` / `stroke-dashoffset`（支持 `pathLength` 比例重映射与负数 `dashoffset` 回环）或 `<animateMotion>` 的节点在初始化时一次性计算并缓存 `List<ui.PathMetric>`，每帧仅调用轻量的 `extractPath()` 或 `getTangentForOffset()`。
4. **零内存分配渲染循环（Zero-Allocation Paint Loop）**
   - 每个 `SvgElement` 预分配并复用 `cachedFillPaint`、`cachedStrokePaint`、`cachedLayerPaint` 以及 16 元素列主序矩阵 `baseTransformMatrix`、`transformMatrix`、`motionMatrix`（`Float64List(16)`），在每帧 `tick` 中原地（In-Place）修改属性。

## 快速上手

```dart
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

final controller = AnimatedSvgController(autoPlay: true, speed: 1.0);

AnimatedSvgPicture.string(
  AnimatedSvgShowcasePresets.cyberCoreCompositeSvg,
  controller: controller,
  width: 280,
  height: 280,
);
```
