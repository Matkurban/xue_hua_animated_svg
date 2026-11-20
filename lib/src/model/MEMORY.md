# `lib/src/model` — SVG 场景图与渲染模型记忆（AI Context）

> 所属包：`xue_hua_animated_svg` (v1.3.0，纯 Dart / Flutter 零第三方依赖)
> 目录职责：定义编译后的全量 SVG 场景图节点（AST/DOM 渲染模型）、样式系统、变换矩阵、预编译路径、渐变/遮罩/图案/标记、W3C 滤镜管线及文本排版引擎。

## 1. 文件清单与核心符号

| 分组 | 文件 | 核心符号 | 职责说明 |
| :--- | :--- | :--- | :--- |
| **场景与基类** | `svg_node.dart` | 统一导出桶（barrel） | 聚合导出 `model/` 下所有核心场景节点文件。 |
| | `svg_document.dart` | `SvgDocument` | 顶层 `<svg>` 场景容器，保存 `viewBox`、`defsById`、`elementsById`、`geometryById`、`gradientsById`、`filtersById`、`masksById`、`patternsById`、`markersById` 与资源释放 `dispose()`。 |
| | `svg_element.dart` | `SvgElement` | 所有可渲染节点的抽象基类：管理 `id`、`classes`、`style`、`transform`、`clipPath`、`cssClipShape`、`mask`、`filter`、静态 `ui.Picture` 缓存与 `paint()` 通用管线。 |
| **容器与视口** | `svg_container_nodes.dart` | `SvgGroupNode`, `SvgDefsNode`, `SvgClipPathNode`, `SvgUseNode` | `<g>`、`<defs>`、`<clipPath>`、`<use>` 节点及引用复用绘制。 |
| | `svg_viewport_nodes.dart` | `SvgAnchorNode`, `SvgConditionalAttrs`, `SvgSwitchNode`, `SvgNestedSvgNode`, `SvgSymbolNode`, `SvgViewNode` | `<a>`、`<switch>`（条件特性匹配）、嵌套 `<svg>`、`<symbol>`、`<view>`。 |
| **几何与路径** | `svg_geometry_node.dart` | `SvgGeometryNode` | 几何图形基类：管理预编译 `basePath`、描边/虚线绘制、路径度量 `cachedMetrics` 与首尾/中点 `<marker>` 绘制。 |
| | `svg_shape_nodes.dart` | `SvgPathNode`, `SvgRectNode`, `SvgCircleNode`, `SvgEllipseNode`, `SvgLineNode`, `SvgPolyNode` | `<path>`、`<rect>`、`<circle>`、`<ellipse>`、`<line>`、`<polyline>`、`<polygon>` 具体几何节点及顶点切线角计算。 |
| | `svg_precompiled_path.dart` | `SvgPathCmdType`, `PrecompiledSvgPath` | 零正则预编译路径命令数组（支持 `buildUiPath` 与路径形变插值）。 |
| | `svg_preserve_aspect_ratio.dart` | `SvgAspectRatioAlign`, `SvgMeetOrSlice`, `SvgPreserveAspectRatio` | W3C `preserveAspectRatio` 对齐与 `meet`/`slice` 缩放矩阵计算。 |
| **样式与变换** | `svg_style.dart` | `SvgTransformBox`, `SvgOriginUnit`, `SvgTransformOrigin`, `SvgPaintLayer`, `SvgPaintType`, `SvgPaintServer`, `SvgStyle` | 继承/动画样式、Paint Server、填充/描边、`mix-blend-mode`、`paint-order`、`transform-origin`/`transform-box`。 |
| | `svg_transform.dart` | `SvgTransformType`, `SvgTransformOp`, `SvgMatrixMath` | 2D 仿射变换操作（`translate`/`scale`/`rotate`/`skewX`/`skewY`/`matrix`）与 4x4 矩阵乘法工具。 |
| | `svg_css_clip_shape.dart` | `SvgCssClipShape`, `SvgClipLength`, `SvgCssClipInset`, `SvgCssClipCircle`, `SvgCssClipEllipse`, `SvgCssClipPolygon`, `SvgCssClipPathShape` | CSS Shapes Level 1 `clip-path`（`inset`/`circle`/`ellipse`/`polygon`/`path`）解析模型与裁剪路径生成。 |
| **资源与特效** | `svg_gradient.dart` | `SvgGradientUnits`, `SvgGradientStop`, `SvgGradientNode`, `SvgLinearGradientNode`, `SvgRadialGradientNode` | 线性与径向渐变定义、`href` 继承及 `ui.Gradient` 着色器构建。 |
| | `svg_mask_node.dart` | `SvgMaskType`, `SvgMaskNode` | `<mask>` 亮度（luminance）与透明通道（alpha）遮罩。 |
| | `svg_pattern_node.dart` | `SvgPatternNode` | `<pattern>` 平铺纹理着色器（`ui.ImageShader`）。 |
| | `svg_marker_node.dart` | `SvgMarkerUnits`, `SvgMarkerOrientMode`, `SvgMarkerVertex`, `SvgMarkerNode` | `<marker>` 路径箭头/标记节点与自动朝向旋转。 |
| | `svg_image_node.dart` | `SvgImageNode` | `<image>` 位图（Base64 Data URI / 内嵌资源）解码与异步/缓存绘制。 |
| **滤镜子系统** | `svg_filter_node.dart` | `SvgFilterPrimitive` 及 `SvgFeGaussianBlur`, `SvgFeDropShadow`, `SvgFeOffset`, `SvgFeColorMatrix`, `SvgFeFlood`, `SvgFeBlend`, `SvgFeComposite`, `SvgFeMerge`, `SvgFeMorphology`, `SvgFeComponentTransfer`, `SvgFeTurbulence`, `SvgFeDisplacementMap`, `SvgFilterNode` | `<filter>` 图定义与基础/噪声滤镜图元（通过 `part 'svg_filter_advanced.dart'` 关联高级图元）。 |
| | `svg_filter_advanced.dart` | `SvgFeImage`, `SvgFeTile`, `SvgFeConvolveMatrix`, `SvgLightSource`（`Distant`/`Point`/`Spot`）, `SvgFeDiffuseLighting`, `SvgFeSpecularLighting`, `SvgFilterAdvancedEngine` | `part of 'svg_filter_node.dart'`；高级滤镜图元与平铺/算术合成/卷积/光照纯 Dart 计算引擎。 |
| | `svg_filter_noise.dart` | `SvgChannelSelector`, `SvgFilterPixelField`, `SvgFilterNoiseEngine` | W3C Perlin 噪声场生成、高斯模糊场与顶点网格位移绘制。 |
| | `svg_filter_executor.dart` | `SvgFilterExecutor` | 滤镜管线 GPU 执行器：单图元 `saveLayer` 快路径 + 多图元命名 `ui.Picture` 缓冲图执行。 |
| **文本子系统** | `svg_text_style.dart` | `SvgTextAnchor`, `SvgDominantBaseline`, `SvgLengthAdjust`, `SvgWhiteSpace`, `SvgPaintOrder`, `SvgTextTransform`, `SvgWritingMode`, `SvgBaselineShift`, `SvgTextLength` | SVG 文本排版与样式枚举及长度单位模型（含 `text-transform` 与竖排 `writing-mode`）。 |
| | `svg_text_node.dart` | `SvgTextContentItem`, `SvgTextLiteral`, `SvgTextSpanNode`, `SvgTextPathNode`, `SvgTextNode` | `<text>`、`<tspan>`、`<textPath>` 节点模型与路径度量缓存。 |
| | `svg_text_layout.dart` | `SvgTextLayoutEngine` | 文本分段测量、基线对齐、`text-anchor`、`textLength`、`text-transform`、竖排 `writing-mode`、路径文字排布及描边/填充绘制引擎。 |

## 2. 关键架构约束与避坑指南

- **`part` 文件约束**：`svg_filter_advanced.dart` 是 `part of 'svg_filter_node.dart';`，文件顶部**禁止**添加独立 `import` 或放在 `part of` 之前的 `///` 库文档注释（会触发 `dangling_library_doc_comments`）。
- **GPU 资源释放**：`SvgDocument.dispose()` 必须级联释放所有节点的静态 `ui.Picture` 缓存、`SvgFeTurbulence` 的噪声 `ui.Picture` 及 `SvgImageNode` 的 `ui.Image`；在 `SvgFilterExecutor` 内部临时录制的 `ui.Picture` 与 `ui.Image` 必须在 `finally` 块中 `dispose()`。
- **混合与合成隔离**：`SvgFeBlend` 与 `SvgFeComposite` 在多步滤镜图中必须包裹独立 `saveLayer`，防止 Porter-Duff 混合模式（如 `srcIn`）泄漏并裁切主画布上的兄弟元素。
- **静态缓存失效条件**：`SvgElement.shouldCacheStaticPicture` 仅在非动画节点上启用；动态节点（`isAnimated == true`）每帧直接绘制并受 `resetFrameState()` 驱动。
- **单向零循环**：`model/` 仅在极少数必要处（如 `SvgTextPathNode` 解析内联 `path`）单向引用 `../parser/svg_path_parser.dart`，禁止反向依赖 `widget/` 或 `controller/`。

## 3. 上下游依赖

- **上游依赖**：`dart:ui`、`dart:math`、`dart:typed_data`、`../parser/svg_path_parser.dart`。
- **下游调用方**：`../parser/`（构建场景图）、`../animation/`（每帧驱动节点状态）、`../widget/animated_svg_painter.dart`（绘制 `SvgDocument`）。

## 4. 变更检查与关联测试

- 所有公共类、枚举、枚举值、属性、方法和入参均须保持中英双文 Effective Dart (`///`) 注释。
- 关联测试：
  - `test/svg_phase1_elements_test.dart` / `svg_phase2_elements_test.dart` / `svg_phase3_elements_test.dart`
  - `test/svg_phase4_filters_test.dart` / `svg_w3c_stage3_filters_test.dart`
  - `test/svg_text_rendering_test.dart` / `svg_w3c_stage4_anim_text_test.dart`
  - `test/svg_w3c_stage2_color_math_clip_test.dart`
