# `lib/src/animation` — 动画求值与时间轴引擎记忆（AI Context）

> 所属包：`xue_hua_animated_svg` (v1.3.0，纯 Dart / Flutter 零第三方依赖)
> 目录职责：负责所有 SMIL 与 CSS `@keyframes` 动画轨道的预编译数据结构、时间映射（Timing / Easing / `steps()` / 负延迟 / 暂停态）、属性插值与逐帧驱动。

## 1. 文件清单与核心符号

| 文件 | 核心符号 | 职责说明 |
| :--- | :--- | :--- |
| `svg_animation_timing.dart` | `SvgAnimationFillMode`, `SvgCalcMode`, `SvgAdditiveMode`, `SvgAnimationDirection`, `SvgAnimationTiming`, `SvgAnimationTrack` | 动画时间模型与抽象轨道基类；处理 `beginSec`（含负延迟）、`durSec`、`repeatCount`、`fillMode`、`direction`、`paused`、`calcMode`、`keyTimes`、`keySplines`、`stepEasing` 及 `additive`/`accumulate`。 |
| `svg_step_easing.dart` | `SvgStepPosition`, `SvgStepEasing` | W3C CSS Easing Level 1 `steps(n, jump-start\|jump-end\|jump-none\|jump-both\|start\|end)` 离散阶梯缓动函数解析与求值。 |
| `svg_property_tracks.dart` | `SvgScalarTarget`, `SvgScalarAnimationTrack`, `SvgColorTarget`, `SvgColorAnimationTrack`, `SvgDashArrayAnimationTrack`, `SvgSetTargetKind`, `SvgSetAnimationTrack` | 标量属性（`opacity`、`stroke-dashoffset`、`r`、`x`/`y`、`font-size` 等）、颜色（`fill`/`stroke`/`stop-color`）、虚线数组（`stroke-dasharray`）及离散 `<set>` 动画轨道。 |
| `svg_transform_tracks.dart` | `SvgTransformAnimationTrack`, `SvgCssMultiTransformTrack` | SMIL `<animateTransform>` 单类型变换轨道与 CSS `@keyframes` 多函数复合变换轨道（支持 `additive="sum"` 与 `accumulate="sum"`）。 |
| `svg_motion_morph.dart` | `SvgMotionRotateMode`, `SvgMotionAnimationTrack`, `SvgPathMorphAnimationTrack` | `<animateMotion>` 沿路径运动（含 `rotate="auto\|auto-reverse\|<angle>"` 与 `keyPoints`）及 `<animate attributeName="d">` 路径形变插值轨道。 |
| `svg_timeline.dart` | `SvgTimelineEngine` | 顶层时间轴驱动器；维护轨道列表、解析有效周期 `naturalDurationSec`，每帧先重置所有目标节点状态再按顺序求值各轨道。 |

## 2. 关键架构约束与避坑指南

- **每帧必须先 Reset 再 Evaluate**：`SvgTimelineEngine.evaluate(timeSec)` 必须先对涉及的 `SvgElement` 调用 `resetFrameState()`（清空 `animatedTransformOps`、`animatedX/Y` 及样式覆盖），再按声明顺序求值每条轨道，确保 `additive="sum"` 和多轨道叠加不会跨帧累积脏状态。
- **线性贝塞尔精度陷阱**：`Curves.linear` 应直接返回 `t`；当 `keySplines` 为 `0 0 1 1`（或等效线性 Cubic）时，切勿退化给近似求解导致 `~0.0002` 误差（`svg_animation_timing.dart` 已针对线性 `Cubic(0, 0, 1, 1)` 做了精确短路，勿回退）。
- **负延迟与 `animation-play-state: paused`**：负的 `beginSec`（CSS 负 `animation-delay`）在 `t = 0` 时即处于活动周期中段；当 `paused == true` 时，`SvgAnimationTiming` 锁定在 `t = 0` 的初始态（含负延迟推进后的静态进度），不随播放时间前进。
- **SMIL `additive` 与 `accumulate`**：标量与变换轨道均支持 `additive="sum"`（在基础值/前序轨道值上累加）与 `accumulate="sum"`（每次重复迭代叠加末帧增量 `(cycleIndex * lastValue)`）。
- **零每帧堆分配原则**：轨道求值在 `paint()` / `Ticker` 高频调用，禁止在 `evaluate` 内执行正则、字符串解析或重建静态列表。

## 3. 上下游依赖

- **上游依赖**：`../model/`（`SvgElement`、`SvgGeometryNode`、`SvgStyle`、`SvgTransformOp`、`PrecompiledSvgPath` 等）。
- **下游调用方**：`../parser/svg_smil_compiler.dart`、`../parser/svg_css_keyframe_compiler.dart`、`../parser/svg_xml_parser.dart`（编译期生成轨道）；`../widget/animated_svg_painter.dart` 与 `../widget/animated_svg_picture.dart`（运行时逐帧求值）。

## 4. 变更检查与关联测试

- 所有公共类、枚举值、属性、方法和入参均须保持中英双文 Effective Dart (`///`) 注释。
- 修改后优先运行：
  - `test/svg_w3c_stage4_anim_text_test.dart`（`steps()`、负延迟、`paused`、`additive`/`accumulate`）
  - `test/xue_hua_animated_svg_test.dart`（基础 SMIL/CSS 动画与时间轴回归）
