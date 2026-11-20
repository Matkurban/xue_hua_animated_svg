# SVG 元素完整支持现状审查与分阶段实现计划

> 本文档基于对 `xue_hua_animated_svg` 现有 AST、解析器、样式系统、动画管线与绘制引擎的逐文件审查，对照 [W3C SVG 2 规范](https://www.w3.org/TR/SVG2/) 与 [MDN SVG 元素参考](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element) 编写，明确列出**当前本应支持但尚未支持（或仅部分支持）的标准 SVG 元素**，并制定逐个完整落地的工程计划。

---

## 一、现状总览：已支持 vs 缺失元素

### 1.1 当前已完整支持的元素
- **结构与容器**：根 `<svg>`、`<g>`、`<defs>`、`<clipPath>`（`userSpaceOnUse`）
- **基础几何**：`<path>`、`<rect>`、`<circle>`、`<ellipse>`、`<line>`、`<polyline>`、`<polygon>`
- **渐变画刷**：`<linearGradient>`、`<radialGradient>`（不含 SVG 2 `fr`）、`<stop>`
- **文本系统**：`<text>`、`<tspan>`、`<textPath>`、文本内 `<a>`
- **动画与样式**：`<animate>`、`<animateTransform>`、`<animateMotion>`、`<mpath>`、`<style>`（`@keyframes` + `#id`/`.class`/`tag`）
- **元信息（按规范不绘制）**：`<title>`、`<desc>`、`<metadata>`

### 1.2 本应支持但当前未支持 / 仅部分支持的元素清单

| 序号 | 元素 | 分类 | 当前状态 | Flutter `dart:ui` 可行性 | 优先级 |
|---|---|---|---|---|---|
| 1 | `<a>`（图形/容器级） | 容器 | ✅ 已在 Phase 1 完成 | 作为容器分组绘制子节点，保留 `href`/`target` | P0 |
| 2 | `<switch>` | 容器 | ✅ 已在 Phase 1 完成 | 按 `systemLanguage` / `requiredExtensions` 选择首个匹配子节点渲染 | P0 |
| 3 | `<set>` | SMIL 动画 | ✅ 已在 Phase 1 完成 | 离散状态切换轨道（`visibility`、`display`、`fill`、`stroke`、数值等），复用现有时间轴 | P0 |
| 4 | `<animateColor>` | SMIL 动画 | ✅ 已在 Phase 1 完成 | SVG 1.1 颜色动画标签，直接复用 `SvgColorAnimationTrack` | P0 |
| 5 | 嵌套 `<svg>` / `<symbol>` / `<use>` 完整规范 | 结构完善 | ✅ 已在 Phase 1 完成 | 复用 `SvgPreserveAspectRatio` 计算子视口矩阵、裁剪、`<use>` 宽高缩放与防循环引用 | P0 |
| 6 | `<clipPath>` 完整规范 | 裁剪完善 | ✅ 已在 Phase 2 完成 | 支持 `objectBoundingBox`、`<use>` 子节点与动态动画裁剪路径 | P1 |
| 7 | `<mask>` | 遮罩 | ✅ 已在 Phase 2 完成 | `canvas.saveLayer` + `BlendMode.dstIn` + Rec.709 亮度转 Alpha 矩阵与 `alpha` 模式 | P1 |
| 8 | `<pattern>` | 图案画刷 | ✅ 已在 Phase 2 完成 | 离屏 `PictureRecorder` → 缓存 `ui.Image` + `ui.ImageShader(TileMode.repeated)` | P1 |
| 9 | `<marker>` | 路径端点标记 | ✅ 已在 Phase 2 完成 | 提取 `<path>`/`<line>`/`<polyline>`/`<polygon>` 顶点与切线，支持 `auto`/`auto-start-reverse` | P1 |
| 10 | `<image>` | 位图/嵌入图 | ✅ 已在 Phase 3 完成 | `ui.instantiateImageCodec` 解码内联 Base64 位图与嵌套 SVG Data URI，解码后自动重绘 | P2 |
| 11 | `<view>` | 命名视图 | ✅ 已在 Phase 3 完成 | 解析 `id` / `viewBox` / `preserveAspectRatio`，支持 `AnimatedSvgPicture(viewId: ...)` 切换视口 | P2 |
| 12 | `<radialGradient fr>` | 渐变完善 | ✅ 已在 Phase 3 完成 | 接入 `ui.Gradient.radial` 原生 `focalRadius` 参数并支持 SMIL `fr` 动画 | P2 |
| 13 | `<filter>` 容器 | 滤镜管线 | 未支持（仅支持 CSS `blur()`） | 基于 `saveLayer` 与 `ui.ImageFilter` / `ui.ColorFilter` / `ui.BlendMode` 构建滤镜图 | P3 |
| 14 | `<feGaussianBlur>` | 滤镜原语 | 未支持 | `ui.ImageFilter.blur(sigmaX, sigmaY)` | P3 |
| 15 | `<feDropShadow>` | 滤镜原语 | 未支持 | 偏移 + 高斯模糊 + 颜色着色合成 | P3 |
| 16 | `<feOffset>` | 滤镜原语 | 未支持 | `ui.ImageFilter.matrix` 平移矩阵 | P3 |
| 17 | `<feColorMatrix>` | 滤镜原语 | 未支持 | `ui.ColorFilter.matrix`（`matrix`/`saturate`/`hueRotate`/`luminanceToAlpha`） | P3 |
| 18 | `<feFlood>` | 滤镜原语 | 未支持 | `flood-color` / `flood-opacity` 纯色图元填充 | P3 |
| 19 | `<feBlend>` | 滤镜原语 | 未支持 | 映射 `ui.BlendMode`（`normal`/`multiply`/`screen`/`overlay`/`darken`/`lighten` 等） | P3 |
| 20 | `<feComposite>` | 滤镜原语 | 未支持 | 映射 `ui.BlendMode`（`over`/`in`/`out`/`atop`/`xor`/`lighter`） | P3 |
| 21 | `<feMerge>` / `<feMergeNode>` | 滤镜原语 | 未支持 | 多图层按序叠合 | P3 |
| 22 | `<feMorphology>` | 滤镜原语 | 未支持 | Flutter `dart:ui` 原生 `ui.ImageFilter.erode` / `ui.ImageFilter.dilate` | P3 |
| 23 | `<feComponentTransfer>` + `<feFuncR/G/B/A>` | 滤镜原语 | 未支持 | 线性/Gamma 映射转 `ColorFilter.matrix` 或 LUT 着色器 | P3 |

### 1.3 明确维持边界不实现的元素
以下元素超出纯 Dart 矢量动画引擎职责或已在 W3C SVG 2 中废弃，不纳入计划：
- `<script>`（JavaScript DOM 执行引擎）
- `<foreignObject>`（嵌入式 HTML/CSS 排版引擎）
- 已废弃的 SVG 1.1 字体/引用标签：`<font>`、`<glyph>`、`<missing-glyph>`、`<hkern>`、`<vkern>`、`<tref>`
- 重度像素级程序化着色滤镜（可作为远期 FragmentShader 可选扩展）：`<feTurbulence>`、`<feDisplacementMap>`、`<feConvolveMatrix>`、`<feDiffuseLighting>`、`<feSpecularLighting>`、`<feDistantLight>`、`<fePointLight>`、`<feSpotLight>`、`<feTile>`、`<feImage>`

---

## 二、逐项完整实现计划

### Phase 1（P0）：基础容器、SMIL 补齐与结构规范修复

#### 1. 图形级 `<a>` 元素
- **规范依据**：[MDN `<a>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/a)
- **实现方案**：
  - 在 `lib/src/model/svg_container_nodes.dart` 新增 `SvgAnchorNode extends SvgGroupNode`，保存 `href`、`target`。
  - 在 `lib/src/parser/svg_xml_parser.dart` 的 `_buildElementNode` 增加 `case 'a':`，递归构建子节点并继承样式、变换、SMIL/CSS 动画。
- **验收标准**：包裹在 `<a>` 内的图形、文字与动画正常绘制，变换与样式继承与 `<g>` 一致。

#### 2. `<switch>` 条件渲染容器
- **规范依据**：[MDN `<switch>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/switch)
- **实现方案**：
  - 新增 `SvgSwitchNode extends SvgGroupNode`，在构建阶段记录各子节点的 `systemLanguage`、`requiredExtensions`、`requiredFeatures`。
  - 在 `initializeGeometry` / `paintContent` 中按规范仅选择并渲染**第一个**条件匹配的子节点（无条件属性视为默认回退项）。
- **验收标准**：含多语言或回退分支的 `<switch>` 仅绘制首个命中分支，且静态子树可缓存。

#### 3. `<set>` 与 `<animateColor>` SMIL 元素
- **规范依据**：[MDN `<set>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/set)
- **实现方案**：
  - 在 `lib/src/animation/svg_property_tracks.dart` 新增 `SvgDiscreteSetTrack`（支持 `visibility`、`display`、`fill`、`stroke` 及全部标量属性），在 `[begin, begin + dur)` 区间内强制写入目标值，`fill="freeze"` 结束后保持。
  - 在 `lib/src/parser/svg_smil_compiler.dart` 新增 `compileSmilSetOnElement`，并将 `animateColor` 路由至现有颜色轨道编译逻辑。
  - 在 `svg_xml_parser.dart` 的容器节点、形状节点与文本子节点动画分支中统一接入 `case 'set':` 与 `case 'animateColor':`。
- **验收标准**：`<set attributeName="visibility" to="visible" begin="0.5s" dur="1s" />` 与 `<animateColor>` 在任意时间戳 `seekMicroseconds` 下状态精准切换。

#### 4. 嵌套 `<svg>`、`<symbol>` 与 `<use>` 完整规范修复
- **规范依据**：[MDN `<svg>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/svg)、[MDN `<symbol>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/symbol)、[MDN `<use>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/use)
- **现有缺陷**：
  - 嵌套 `<svg>` 忽略 `x`/`y`/`width`/`height`/`viewBox`/`preserveAspectRatio` 与默认 `overflow: hidden` 裁剪。
  - `<symbol>` 忽略自身 `viewBox`/`preserveAspectRatio`，且 `<use>` 忽略 `width`/`height` 缩放。
  - `<use>` 仅查询 `document.defsById`，无法引用不在 `<defs>` 中的常规图形 ID（W3C 允许引用任意 `elementsById`）。
- **实现方案**：
  - 新增 `SvgNestedSvgNode` 与 `SvgSymbolNode`（独立文件 `lib/src/model/svg_viewport_nodes.dart`），持有 `x`/`y`/`width`/`height`/`viewBox`/`preserveAspectRatio`/`overflowHidden`。
  - `SvgUseNode` 扩展 `baseWidth`/`baseHeight`（支持动画），查找顺序改为 `defsById[id] ?? elementsById[id]`，当目标为 `SvgSymbolNode` 或 `SvgNestedSvgNode` 时应用 `viewBox → (width, height)` 映射矩阵。
- **验收标准**：嵌套 `<svg viewBox>` 定位与裁剪准确；`<use href="#sym" width="80" height="40" />` 等比缩放正确；引用非 `<defs>` 节点不报错且无循环引用死循环（增加递归深度保护）。

---

### Phase 2（P1）：遮罩、图案画刷、路径标记与高级裁剪

#### 5. `<clipPath>` 完整规范补齐
- **规范依据**：[MDN `<clipPath>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/clipPath)
- **实现方案**：
  - 支持 `clipPathUnits="objectBoundingBox"`（绘制时将 `clipPath` 按宿主 `cachedBounds` 平移缩放后裁剪）。
  - 支持 `<clipPath>` 内包含 `<use>` 与动画子节点（动态刷新 `clipPath`）。
- **验收标准**：`clipPathUnits="objectBoundingBox"` 在不同尺寸矩形/圆形上精准生效，动画裁剪路径逐帧更新。

#### 6. `<mask>` 完整实现
- **规范依据**：[MDN `<mask>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/mask)
- **实现方案**：
  - 新建 `lib/src/model/svg_mask_node.dart` 定义 `SvgMaskNode`（含 `maskUnits`、`maskContentUnits`、`maskType: luminance | alpha`、`x`/`y`/`width`/`height`）。
  - 在 `SvgStyle` 与 `SvgCssParser` 增加 `mask` (`url(#id)`) 与 `mask-type` 属性。
  - 在 `SvgElement._paintInternal` 中集成遮罩合成管线：
    1. `canvas.saveLayer(maskBounds, layerPaint)` 绘制被遮罩内容；
    2. `canvas.saveLayer(maskBounds, dstInPaint)`（`BlendMode.dstIn`；若为 `luminance` 模式则附加标准 Rec.709 亮度转 Alpha 矩阵 `ColorFilter.matrix([0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0.2126,0.7152,0.0722,0,0])`）；
    3. 按 `maskContentUnits` 坐标变换后绘制 `<mask>` 子节点并逐层 `restore()`。
- **验收标准**：白显黑隐的亮度遮罩（含渐变淡出遮罩）与 `mask-type="alpha"` 透明度遮罩均与浏览器一致；遮罩内含动画时自动冒泡 `isAnimated`。

#### 7. `<pattern>` 图案画刷完整实现
- **规范依据**：[MDN `<pattern>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/pattern)
- **实现方案**：
  - 新建 `lib/src/model/svg_pattern_node.dart` 定义 `SvgPatternNode`（`patternUnits`、`patternContentUnits`、`patternTransform`、`x`/`y`/`width`/`height`/`viewBox`/`preserveAspectRatio`/`href` 模板继承）。
  - 在 `SvgPaintServer` 新增 `SvgPaintType.pattern`（或统一由 `url(#id)` 延迟解析为渐变或图案）。
  - 首次绘制时将单块 tile 渲染至离屏 `ui.PictureRecorder` → `toImageSync(tileW, tileH)`（或缓存 `ui.Image`），构造 `ui.ImageShader(image, TileMode.repeated, TileMode.repeated, patternMatrix)` 赋值给 `Paint.shader`，并在 `dispose()` 时释放 `ui.Image`。
- **验收标准**：支持网格、斜纹、波点等 `<pattern>` 填充与描边，支持 `patternTransform="rotate(45)"` 与静态纹理缓存零重复光栅化。

#### 8. `<marker>` 路径端点标记完整实现
- **规范依据**：[MDN `<marker>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/marker)
- **实现方案**：
  - 新建 `lib/src/model/svg_marker_node.dart` 定义 `SvgMarkerNode`（`refX`、`refY`、`markerWidth`、`markerHeight`、`markerUnits: strokeWidth | userSpaceOnUse`、`orient: auto | auto-start-reverse | angle`、`viewBox`、`preserveAspectRatio`）。
  - 在 `SvgStyle` 与 `SvgCssParser` 增加 `marker-start`、`marker-mid`、`marker-end` 及简写 `marker`。
  - 在 `SvgGeometryNode` 中为 `<path>`、`<line>`、`<polyline>`、`<polygon>` 提取顶点坐标及入/出切线角（`mid` 取角平分线方向，`start` 在 `auto-start-reverse` 下翻转 180°），在 `paintContent` 描边后绘制标记。
- **验收标准**：箭头、流程图连线、折线节点圆点在直线与贝塞尔曲线上朝向与缩放完全符合 W3C 规范。

---

### Phase 3（P2）：位图嵌入、命名视图与 SVG 2 渐变补齐

#### 9. `<image>` 嵌入位图与内联 SVG 支持
- **规范依据**：[MDN `<image>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/image)
- **实现方案**：
  - 新建 `lib/src/model/svg_image_node.dart` 定义 `SvgImageNode extends SvgElement`（`x`、`y`、`width`、`height`、`href`/`xlink:href`、`preserveAspectRatio`）。
  - 优先完整支持 `data:image/png;base64,...`、`data:image/jpeg;base64,...`、`data:image/webp;base64,...`（通过 `dart:convert` 解码 + `ui.instantiateImageCodec` 异步解码并缓存 `ui.Image`，解码完成后通知重绘），以及 `data:image/svg+xml` 递归编译为子 `SvgDocument` 绘制。
  - 在 `dispose()` 中统一释放缓存的 `ui.Image`。
- **验收标准**：含内联 Base64 PNG/JPEG 与嵌套 SVG Data URI 的 `<image>` 按 `preserveAspectRatio` 精准绘制，且无内存泄漏。

#### 10. `<view>` 命名视图与 `<radialGradient fr>`
- **规范依据**：[MDN `<view>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/view)、[MDN `fr`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Attribute/fr)
- **实现方案**：
  - 在 `SvgDocument` 新增 `Map<String, SvgViewNode> viewsById`，解析 `<view id="..." viewBox="..." preserveAspectRatio="..." />`，允许 `AnimatedSvgPicture` 通过可选 `viewId` 参数切换视口（常用于 SVG Sprite 精灵图）。
  - 在 `SvgRadialGradientNode` 增加 `baseFr` / `currentFr`（默认 `0.0`，支持 `<animate attributeName="fr">`），传入 `ui.Gradient.radial(..., currentFr)`。
- **验收标准**：指定 `viewId` 可准确裁切显示对应精灵图区域；带 `fr` 的径向渐变渲染与浏览器一致。

---

### Phase 4（P3）：`<filter>` 与 Flutter 原生可硬件加速 `fe*` 滤镜管线

#### 11. `<filter>` 与核心原语（10 个原语）
- **规范依据**：[MDN `<filter>`](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/filter)
- **实现方案**：
  - 新建 `lib/src/model/svg_filter_node.dart` 与 `lib/src/model/svg_filter_executor.dart`：
    - `SvgFilterNode` 解析 `filterUnits`、`primitiveUnits`、`x`/`y`/`width`/`height` 与有序原语列表 `List<SvgFilterPrimitive>`。
    - 优先实现可直接映射到 Flutter GPU `ui.ImageFilter` / `ui.ColorFilter` / `ui.BlendMode` 的高频原语：
      1. `<feGaussianBlur>` → `ui.ImageFilter.blur`
      2. `<feDropShadow>` → 偏移模糊着色合成
      3. `<feOffset>` → `ui.ImageFilter.matrix`
      4. `<feColorMatrix>` → `ui.ColorFilter.matrix`（`matrix` / `saturate` / `hueRotate` / `luminanceToAlpha`）
      5. `<feFlood>` → 滤镜区域纯色填充
      6. `<feBlend>` → `ui.BlendMode` 混合
      7. `<feComposite>` → `ui.BlendMode` Porter-Duff 合成
      8. `<feMerge>` + `<feMergeNode>` → 多命名结果（`SourceGraphic`/`SourceAlpha`/`result`）按序合成
      9. `<feMorphology>` → `ui.ImageFilter.erode` / `ui.ImageFilter.dilate`
      10. `<feComponentTransfer>` + `<feFuncR/G/B/A>` → 通道线性/Gamma 变换
    - 支持 `in` / `in2` / `result` 命名缓冲区，单原语（如纯模糊/纯阴影/纯色彩矩阵）走零离屏 `saveLayer(Paint()..imageFilter = ...)` 快路径；多步骤图走离屏 `Picture` / `Image` 缓冲合成。
- **验收标准**：常见图标投影（`<feDropShadow>`）、发光效果（`<feGaussianBlur>` + `<feMerge>`）、灰度/变色（`<feColorMatrix>`）与形态学描边（`<feMorphology>`）在 60fps 下流畅渲染。

---

## 三、配套规范与测试验证策略

1. **文档同步**：每个 Phase 完成后同步更新 `README.md`、`README_zh.md` 与 `CHANGELOG.md` 的支持矩阵（移除已实现项的 Out-of-Scope 说明）。
2. **示例资产**：为每个新增元素在 `example/assets/svgs/` 下添加对应示例 SVG，并在 `example/lib/data/` 注册，UI 严格遵循页面组件封装规范（禁止返回组件的方法，跨页复用放入 `example/lib/widgets/`）。
3. **测试覆盖**：每个 Phase 独立新增单元测试与离屏像素验证测试（`Picture.toImage` + `toByteData` 校验非空白/目标色值），并确保 `flutter analyze` 零告警与 `flutter test` 全量通过。
