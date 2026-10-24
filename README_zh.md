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
  xue_hua_animated_svg: ^1.0.0
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

## 许可证

见 [LICENSE](LICENSE)。
