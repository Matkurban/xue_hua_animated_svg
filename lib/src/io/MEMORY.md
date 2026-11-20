# `lib/src/io` — 跨平台本地文件读取记忆（AI Context）

> 所属包：`xue_hua_animated_svg` (v1.3.0，纯 Dart / Flutter 零第三方依赖)
> 目录职责：通过 Dart 条件导出（Conditional Export）隔离 `dart:io`，确保 `AnimatedSvgPicture.file(...)` 在原生平台（iOS/Android/macOS/Windows/Linux）正常工作，同时保证 Web 平台编译零报错。

## 1. 文件清单与核心符号

| 文件 | 核心符号 | 职责说明 |
| :--- | :--- | :--- |
| `svg_file_reader.dart` | 条件导出入口 | 根据 `dart.library.io` 存在与否，自动导出 `svg_file_reader_io.dart` 或 `svg_file_reader_stub.dart`。 |
| `svg_file_reader_io.dart` | `svgFilePath(Object file)`, `readSvgFileAsString(Object file)` | 原生平台实现：将传入对象转为 `dart:io.File` 获取路径并异步读取 UTF-8 字符串内容。 |
| `svg_file_reader_stub.dart` | `svgFilePath(Object file)`, `readSvgFileAsString(Object file)` | Web/无 `dart:io` 平台桩实现：显式抛出 `UnsupportedError`，避免 Web 编译失败。 |

## 2. 关键架构约束与避坑指南

- **禁止在 `lib/src/widget/` 直接 `import 'dart:io'`**：所有与本地 `File` 交互的逻辑必须收敛在 `lib/src/io/` 内并通过 `Object` 参数桥接，否则会破坏 Flutter Web 构建。
- **签名严格对称**：`svg_file_reader_io.dart` 与 `svg_file_reader_stub.dart` 导出的顶层函数名、参数类型及返回值类型必须完全一致。
- **无多余依赖**：本目录不引入 `path_provider` 或任何第三方插件。

## 3. 上下游依赖

- **上游依赖**：`svg_file_reader_io.dart` 仅依赖 `dart:io`；`svg_file_reader_stub.dart` 无外部依赖。
- **下游调用方**：`../widget/animated_svg_picture.dart`（支撑 `AnimatedSvgPicture.file` 构造器）。

## 4. 变更检查与关联测试

- 任何改动均需确保 `dart:io` 不泄漏到 Web 编译路径，且所有公共函数具备中英双文 Effective Dart (`///`) 注释。
- 关联测试：`test/animated_svg_picture_sources_test.dart`。
