# xue_hua_animated_svg

[English](README.md) | [中文](README_zh.md)

High-performance, **zero-native-dependency**, 100% pure Dart animated SVG rendering engine for Flutter.
Precompiles SMIL and CSS animations into a strongly typed AST and paints at **60fps / 120fps** with
static subtree `Picture` caching and a zero-allocation paint loop.

**Live demo (GitHub Pages):** https://matkurban.github.io/xue_hua_animated_svg/

> Pages are published automatically when a `v*` tag is pushed, a GitHub Release is published,
> `pubspec.yaml` changes on `main`, or via **Actions → Deploy example to GitHub Pages → Run workflow**.
> If the link 404s, enable **Settings → Pages → Source: GitHub Actions** once for the repository.

## Features

1. **Parse-time precompilation** — XML, CSS, colors, path `d`, and clock units are resolved once in
   `SvgParser.compile()` into typed `double` / `Color` / `Float64List` / spline data. Runtime paint
   never re-parses strings.
2. **Static subtree Picture caching** — nodes with `isAnimated == false` are recorded into
   `ui.Picture` on first paint and replayed with `canvas.drawPicture()`.
3. **Cached PathMetrics** — dash and motion paths keep precomputed `PathMetric` lists; frames only
   call `extractPath` / `getTangentForOffset`.
4. **Zero-allocation paint loop** — paints, layer opacity, and 4×4 column-major matrices are reused
   in place every tick.
5. **SMIL + CSS** — `<animate>`, `<animateTransform>`, `<animateMotion>` / `<mpath>`, isomorphic
   path morphing (`d`), stroke dash growth (`pathLength`), and CSS `@keyframes` with
   `transform-origin`.

## Install

```yaml
dependencies:
  xue_hua_animated_svg: ^1.0.0
```

```bash
flutter pub get
```

## Quick start

```dart
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

final controller = AnimatedSvgController(autoPlay: true, speed: 1.0);

// From a raw SVG string (includes the built-in CyberCore composite preset)
AnimatedSvgPicture.string(
  AnimatedSvgShowcasePresets.cyberCoreCompositeSvg,
  controller: controller,
  width: 280,
  height: 280,
);

// Or from a Flutter asset
AnimatedSvgPicture.asset(
  'assets/svgs/elephant.svg',
  controller: controller,
  width: 280,
  height: 280,
);

// From a network URL (web + IO)
AnimatedSvgPicture.network(
  'https://example.com/motion.svg',
  headers: {'Authorization': 'Bearer …'}, // optional
  controller: controller,
  width: 280,
  height: 280,
);

// From a local file (requires dart:io — not available on web)
AnimatedSvgPicture.file(
  File('/path/to/motion.svg'), // dart:io File; unsupported on web
  controller: controller,
  width: 280,
  height: 280,
);
```

### Playback control

```dart
controller.play();
controller.pause();
controller.reset();
controller.seek(const Duration(milliseconds: 500));
controller.setSpeed(2.0);

final progress = controller.cycleProgress; // 0.0 .. 1.0
final elapsed = controller.elapsed;
```

### Precompile once

```dart
final scene = SvgParser.compile(svgXml);
AnimatedSvgPicture.compiled(scene, controller: controller);
// later:
scene.dispose();
```

## Public API surface

| API                                                                         | Role                                             |
|-----------------------------------------------------------------------------|--------------------------------------------------|
| `AnimatedSvgPicture.string` / `.asset` / `.file` / `.network` / `.compiled` | Widget entry points                              |
| `AnimatedSvgController`                                                     | `play` / `pause` / `seek` / `reset` / `setSpeed` |
| `SvgParser.compile`                                                         | Precompile SVG XML → `CompiledSvgScene`          |
| `AnimatedSvgShowcasePresets.cyberCoreCompositeSvg`                          | Composite showcase SVG string                    |


## Supported SVG surface

Tags and features the parser builds into the scene graph (others are dropped):

| Area | Supported |
|------|-----------|
| Structure | `<svg>`, `<g>`, `<defs>`, `<symbol>`, `<use>` |
| Geometry | `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>` |
| Paint | `<linearGradient>`, `<radialGradient>`, `<stop>`, `<clipPath>` |
| SMIL | `<animate>`, `<animateTransform>`, `<animateMotion>`, `<mpath>` |
| CSS | `<style>`, `@keyframes`; selectors **only** `#id`, `.class`, `tagName`; CSS `filter: blur(...)` (sigma → `MaskFilter`, not SVG filter graphs) |

Skipped metadata (no render): `<style>` text is parsed; `<title>`, `<desc>`, `<metadata>` are ignored.

## Out-of-Scope (do not implement)

These are **explicitly unsupported**. Unknown tags return `null` and are omitted. Do **not** grow the engine toward them (no full CSS selector engine, no text layout stack):

| Forbidden | Why |
|-----------|-----|
| `<filter>` and all `fe*` primitives (`feGaussianBlur`, `feBlend`, …) | Not a filter graph engine; only optional CSS `blur()` sigma |
| `<text>`, `<tspan>`, `<textPath>`, `<tref>` | No glyph / text shaping |
| `<foreignObject>` | No HTML/Flutter subtree embedding |
| Complex CSS selectors | No descendant/child/sibling (` `, `>`, `+`, `~`), attribute, or pseudo (`:hover`, `:nth-child`, …) selectors; no `@media` / `@import` stylesheet rules |
| Also dropped today | `<image>`, `<mask>`, `<marker>`, `<pattern>`, `<switch>`, `<a>`, `<script>`, `<view>`, `<set>`, and any other tag not listed under Supported |

Author SVG for geometry + SMIL/CSS motion within the Supported table. Treat Out-of-Scope as a hard product boundary.

## License

See [LICENSE](LICENSE).
