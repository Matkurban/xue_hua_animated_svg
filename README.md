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
  xue_hua_animated_svg: ^1.2.0
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

### Layout tint: `fit`, `alignment` & `colorFilter`

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `fit` | `BoxFit` | `BoxFit.contain` | How the SVG intrinsic box is inscribed into the widget size (`applyBoxFit`). |
| `alignment` | `AlignmentGeometry` | `Alignment.center` | Places the fitted rect in leftover / cropped space (`alignment.inscribe`). |
| `colorFilter` | `ColorFilter?` | `null` | Whole-picture Flutter tint (e.g. `ColorFilter.mode(color, BlendMode.srcIn)`). **Not** SVG `<filter>`. |

```dart
AnimatedSvgPicture.asset(
  'assets/svgs/elephant.svg',
  width: 280,
  height: 160,
  fit: BoxFit.cover,
  alignment: Alignment.topLeft,
  colorFilter: const ColorFilter.mode(Color(0xFF22C55E), BlendMode.srcIn),
);
```

## Supported SVG surface

Tags and features the parser builds into the scene graph:

| Area | Supported |
|------|-----------|
| Structure & Views | `<svg>` (root & nested viewports), `<g>`, `<defs>`, `<symbol>`, `<use>` (with `width`/`height` & cycle guard), `<a>`, `<switch>`, `<view>` (selectable via `viewId`) |
| Geometry | `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>` |
| Text | `<text>`, `<tspan>`, `<textPath>` (with `font`, `font-family`, `font-size`, `font-weight`, `font-style`, `font-variant`, `text-anchor`, `dominant-baseline`, `alignment-baseline`, `baseline-shift`, `x`/`y`/`dx`/`dy`/`rotate` lists, `textLength`/`lengthAdjust`, `xml:space`/`white-space`, `paint-order`) |
| Paint, Clipping & Masks | `<linearGradient>`, `<radialGradient>` (with SVG 2 `fr`), `<stop>`, `<pattern>`, `<clipPath>` (`userSpaceOnUse` & `objectBoundingBox`), `<mask>` (`luminance` & `alpha`), `<marker>` (`marker-start`/`mid`/`end`) |
| Raster / Embedded | `<image>` (`data:image/png|jpeg|webp|gif;base64,...` and `data:image/svg+xml,...`) |
| Filters | `<filter>`, `<feGaussianBlur>`, `<feDropShadow>`, `<feOffset>`, `<feColorMatrix>`, `<feFlood>`, `<feBlend>`, `<feComposite>`, `<feMerge>`, `<feMergeNode>`, `<feMorphology>`, `<feComponentTransfer>` (`<feFuncR/G/B/A>`) |
| SMIL | `<animate>`, `<animateColor>`, `<animateTransform>`, `<animateMotion>`, `<mpath>`, `<set>` |
| CSS | `<style>`, `@keyframes`; selectors `#id`, `.class`, `tagName`; inline `style="..."`; CSS `filter: blur(...)` & `url(#filterId)` |

Skipped metadata (no render): `<style>` text is parsed; `<title>`, `<desc>`, `<metadata>` are ignored.

## Out-of-Scope

The following remain intentionally out-of-scope for a pure-Dart vector engine:

| Unsupported | Why |
|-------------|-----|
| `<script>` | No JavaScript DOM execution |
| `<foreignObject>` | No HTML/CSS DOM subtree embedding |
| Deprecated SVG 1.1 font/ref tags | `<font>`, `<glyph>`, `<missing-glyph>`, `<hkern>`, `<vkern>`, `<tref>` |
| Complex CSS selectors | No descendant/child/sibling (` `, `>`, `+`, `~`), attribute, or pseudo selectors; no `@media` / `@import` |
| Procedural lighting/turbulence filters | `<feTurbulence>`, `<feDisplacementMap>`, `<feConvolveMatrix>`, `<feDiffuseLighting>`, `<feSpecularLighting>`, `<feDistantLight>`, `<fePointLight>`, `<feSpotLight>`, `<feTile>`, `<feImage>` |

## License

See [LICENSE](LICENSE).
