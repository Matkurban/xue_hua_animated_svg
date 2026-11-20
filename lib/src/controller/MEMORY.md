# `lib/src/controller` — 播放控制器记忆（AI Context）

> 所属包：`xue_hua_animated_svg` (v1.3.0，纯 Dart / Flutter 零第三方依赖)
> 目录职责：对外暴露命令式动画播放控制器，桥接业务层调用与 `AnimatedSvgPicture` 内部的 `Ticker` 渲染循环。

## 1. 文件清单与核心符号

| 文件 | 核心符号 | 职责说明 |
| :--- | :--- | :--- |
| `animated_svg_controller.dart` | `AnimatedSvgController` | 继承自 `ChangeNotifier` 的播放状态控制器，提供 `play()`、`pause()`、`stop()`、`restart()`、`seek(Duration)`、`seekToProgress(double)`、`setSpeed(double)`、`setLoop(bool)`，以及只读状态 `isPlaying`、`currentTime`、`duration`、`progress`、`speed`、`loop` 和 `hasTimeline`。 |

## 2. 关键架构约束与避坑指南

- **单向内部绑定契约**：控制器通过内部方法（供 `AnimatedSvgPicture` 的 State 调用）同步场景的 `naturalDuration` 与逐帧 `currentTime`，业务方只应调用公开的播放控制 API。
- **空时间轴 / 静态 SVG 安全**：当 SVG 无动画轨道（`hasTimeline == false` 或 `duration == Duration.zero`）时，`seekToProgress` 和 `progress` 必须安全兜底，避免除以零或 `NaN`。
- **生命周期管理**：若业务方手动创建并传入 `AnimatedSvgController` 给 `AnimatedSvgPicture`，由业务方负责 `dispose()`；若未传入，则由 `AnimatedSvgPicture` 内部创建并在 `State.dispose()` 中释放。
- **通知频率控制**：仅在播放状态、进度、速度或循环配置实际变更时触发 `notifyListeners()`，避免无意义的重绘。

## 3. 上下游依赖

- **上游依赖**：仅依赖 `package:flutter/foundation.dart`。
- **下游调用方**：`../widget/animated_svg_picture.dart`、`lib/xue_hua_animated_svg.dart`（对外导出）。

## 4. 变更检查与关联测试

- 保持 `AnimatedSvgController` 为面向最终开发者的稳定公共 API，任何签名变更需同步更新 `README.md`、`README_zh.md` 与 `skills/xue-hua-animated-svg-usage/SKILL.md`。
- 所有公共成员须保持中英双文 Effective Dart (`///`) 注释。
- 关联测试：`test/xue_hua_animated_svg_test.dart`。
