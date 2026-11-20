# `lib/src/widget` — Flutter 渲染组件与画板记忆（AI Context）

> 所属包：`xue_hua_animated_svg` (v1.3.0，纯 Dart / Flutter 零第三方依赖)
> 目录职责：提供面向 Flutter 应用层的 `AnimatedSvgPicture` Widget、底层 `AnimatedSvgPainter`（`CustomPainter`）以及内置演示 SVG 预设集合。

## 1. 文件清单与核心符号

| 文件 | 核心符号 | 职责说明 |
| :--- | :--- | :--- |
| `animated_svg_picture.dart` | `AnimatedSvgPicture` | 对外主组件，提供 `.string`、`.asset`、`.memory`、`.file`、`.network` 五种数据源构造器，支持 `width`/`height`、`fit`、`alignment`、`colorFilter`、`controller`、`autoPlay`、`loop`、`speed`、`placeholderBuilder`、`errorBuilder`、`semanticsLabel` 及 `clipBehavior`。 |
| `animated_svg_painter.dart` | `AnimatedSvgPainter` | 继承自 `CustomPainter`；根据 `BoxFit`、`Alignment` 与 `viewBox` 计算缩放平移矩阵，应用可选 `colorFilter`，调用 `SvgDocument.paint()` 完成实际绘制。 |
| `animated_svg_showcase_presets.dart` | `AnimatedSvgShowcasePresets` | 内置演示与测试用动画 SVG 字符串预设集合（涵盖 SMIL、CSS 动画、渐变、滤镜与文本等典型场景）。 |

## 2. 关键架构约束与避坑指南

- **单 Ticker 高效驱动**：`_AnimatedSvgPictureState` 使用 `SingleTickerProviderStateMixin`，仅在存在有效动画时间轴且处于播放状态时启动 `Ticker`；对于纯静态 SVG 或暂停状态不空转 `Ticker`，零 CPU 唤醒。
- **资源释放与复用**：当数据源（`svgString` / `assetName` / `bytes` / `file` / `url`）变化或 Widget `dispose()` 时，必须调用旧 `CompiledSvgScene.document.dispose()` 释放 GPU `ui.Picture` / `ui.Image` 资源。
- **跨平台文件安全**：`.file` 构造器必须通过 `../io/svg_file_reader.dart` 间接读取，绝不直接导入 `dart:io`。
- **网络加载错误处理**：`.network` 在 HTTP 非 200 或网络异常时优先走 `errorBuilder`，未提供时回退为等尺寸占位 `SizedBox`，同时记录 `debugPrint` 日志而不抛出未捕获异常。
- **`shouldRepaint` 精确判定**：`AnimatedSvgPainter.shouldRepaint` 比较 `document`、`paintVersion`（帧版本号）、`fit`、`alignment`、`colorFilter` 与 `clipBehavior`，确保动画帧精确重绘且静态场景不抖动。

## 3. 上下游依赖

- **上游依赖**：`../controller/animated_svg_controller.dart`、`../io/svg_file_reader.dart`、`../model/`、`../parser/svg_xml_parser.dart`、`../animation/svg_timeline.dart`。
- **下游调用方**：`lib/xue_hua_animated_svg.dart`（包总入口对外导出）。

## 4. 变更检查与关联测试

- 任何公开 Widget 参数改动须同步更新 `README.md`、`README_zh.md` 与 `skills/xue-hua-animated-svg-usage/SKILL.md`。
- 所有公共类、构造器、属性和方法均须保持中英双文 Effective Dart (`///`) 注释。
- 关联测试：
  - `test/animated_svg_picture_sources_test.dart`（5 种数据源与错误回退）
  - `test/animated_svg_picture_fit_filter_test.dart`（`BoxFit`、`Alignment`、`colorFilter`、裁剪）
  - `test/xue_hua_animated_svg_test.dart`（播放控制与渲染生命周期）
