# `lib/src/parser` — SVG / XML / CSS / SMIL 编译管线记忆（AI Context）

> 所属包：`xue_hua_animated_svg` (v1.3.0，纯 Dart / Flutter 零第三方依赖)
> 目录职责：将原始 SVG 字符串一次性零依赖词法分析、XML 树构建、CSS 样式级联与变量展开、Color 4 / 数学函数求值、路径预编译、SMIL/CSS 动画轨道编译为 `CompiledSvgScene`（`SvgDocument` + `SvgTimelineEngine`）。

## 1. 文件清单与核心符号

| 分组 | 文件 | 核心符号 | 职责说明 |
| :--- | :--- | :--- | :--- |
| **XML 与总编译** | `svg_xml_tokenizer.dart` | `SvgXmlNode`, `SvgXmlTextContent`, `SvgXmlElement`, `SvgXmlTokenizer` | 零依赖流式 XML 词法/树解析器（处理注释、CDATA、实体转义、`xml:space` 空白保留）。 |
| | `svg_xml_parser.dart` | `CompiledSvgScene`, `SvgXmlParser` | 编译管线总入口：`parse(String svg)` 输出可直接渲染的 `CompiledSvgScene`，串联 `<style>`、`defs`、节点树、SMIL 与 CSS 动画编译。 |
| | `svg_path_parser.dart` | `SvgPathParser` | 符合 W3C SVG Path 语法的 `d` 属性零正则扫描器，输出 `PrecompiledSvgPath`（含椭圆弧 `A/a` 展开为三次贝塞尔）。 |
| **SMIL 编译** | `svg_smil_compiler.dart` | `SvgPendingMotionTrack`, `SvgSmilCompiler` | 将 `<animate>`、`<animateTransform>`、`<animateMotion>`、`<set>` 编译为 `animation/` 轨道，并支持 `<mpath>` 延迟绑定。 |
| | `svg_smil_syncbase.dart` | `SvgSyncbaseEdge`, `SvgSmilSyncbaseRef`, `SvgSmilSyncbaseResolver` | SMIL Syncbase 时间依赖（`id.begin+1s` / `id.end-0.5s`）的多轮拓扑解析器。 |
| **CSS 解析与级联** | `svg_css_models.dart` | `SvgCssAnimationConfig`, `SvgCssRule`, `SvgCssKeyframeStop`, `SvgStyleSheet` | CSS 样式表、`@keyframes` 停靠点与 `animation` 简写配置数据模型。 |
| | `svg_css_parser.dart` | `SvgCssParser` | 解析 `<style>` 中的规则、媒体查询/忽略块、`@keyframes`、选择器优先级与内联 `style="..."` 声明。 |
| | `svg_css_selector.dart` | `SvgCssCombinator`, `SvgCssAttrOp`, `SvgCssAttrSelector`, `SvgCssPseudoClass`（`:root`, `:first-child`, `:last-child`, `:only-child`, `:empty`, `:nth-child`, `:not`）, `SvgCssMatchContext`, `SvgCssCompoundSelector`, `SvgCssComplexSelector` | W3C Selectors Level 4 复合/组合选择器解析、特异性计算与祖先链匹配。 |
| | `svg_css_value_parser.dart` | `SvgCssValueParser` | 通用 CSS/SVG 属性值解析（长度、角度、时间、颜色、变换列表、`clip-path` 函数、`steps()` 等）。 |
| | `svg_css_keyframe_compiler.dart` | `SvgCssKeyframeCompiler` | 将匹配元素的 `animation` 配置与 `@keyframes` 规则编译为标量/颜色/多变换动画轨道。 |
| | `svg_css_variables.dart` | `SvgCssVariables` | CSS 自定义属性（`--var`）作用域继承与 `var(--name, fallback)` 递归展开（带循环引用防护）。 |
| | `svg_css_color4.dart` | `SvgCssColor4` | W3C CSS Color 4 颜色解析：`rgb()`/`rgba()`/`hsl()`/`hsla()`（含空格与 `/` 现代语法）、`hwb()`、`oklch()`、`oklab()`、`lab()`、`lch()`、`color-mix()`。 |
| | `svg_css_math.dart` | `SvgCssMath` | CSS Values 4 数学表达式求值：`calc()`、`min()`、`max()`、`clamp()` 及嵌套算术。 |
| | `svg_named_colors.dart` | `kSvgNamedColors` | 完整 148 个 W3C SVG/CSS 命名颜色映射表（全小写键）。 |

## 2. 关键架构约束与避坑指南

- **一次性编译原则**：所有字符串扫描、CSS 级联、`var()` 替换、Syncbase 拓扑求值、路径弧线展开都必须在 `SvgXmlParser.parse()` 编译阶段完成，渲染帧阶段严禁再回调 `parser/`（仅 `SvgTextPathNode` 首次初始化几何时解析内联 `path`）。
- **级联优先级**：严格遵循 W3C 顺序：继承属性 < 演示属性（Presentation Attributes）< `<style>` 选择器（按 Specificity + 声明顺序）< 内联 `style="..."` < `!important`（如支持）< 运行时动画覆盖。
- **Syncbase 拓扑顺序**：`SvgSmilSyncbaseResolver` 在所有元素和动画节点遍历完成后统一执行拓扑解析，支持前向引用与环路保护，避免死循环。
- **容错降级**：面对非标准/残缺 SVG 属性（如缺省单位、非法颜色、未闭合路径、未知滤镜原语），解析器应安全忽略并回退默认值，绝不抛出未捕获异常崩溃 UI。

## 3. 上下游依赖

- **上游依赖**：`../model/`、`../animation/`、`dart:math`、`dart:typed_data`、`dart:ui`。
- **下游调用方**：`../widget/animated_svg_picture.dart`、`lib/xue_hua_animated_svg.dart`。

## 4. 变更检查与关联测试

- 所有公共类、枚举值、属性、方法和入参均须保持中英双文 Effective Dart (`///`) 注释。
- 关联测试：
  - `test/svg_w3c_stage1_css_test.dart`（选择器、变量、级联）
  - `test/svg_w3c_stage2_color_math_clip_test.dart`（Color 4、`calc/min/max/clamp`、`clip-path`）
  - `test/svg_w3c_stage4_anim_text_test.dart`（SMIL Syncbase、`steps()`、负延迟、文本属性）
  - `test/all_example_svgs_compile_test.dart` / `test/svg_full_assets_regression_test.dart`（全量样例 SVG 编译回归）
