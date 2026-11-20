# xue_hua_animated_svg

[English](README.md) | [中文](README_zh.md)

High-performance, **zero-native-dependency**, 100% pure Dart animated SVG rendering engine for Flutter.
Precompiles W3C SVG 2, SMIL, and CSS into a strongly typed AST and paints at **60fps / 120fps** with
static subtree `Picture` caching and a zero-allocation paint loop.

**Live demo (GitHub Pages):** https://matkurban.github.io/xue_hua_animated_svg/

> Pages are published automatically when a `v*` tag is pushed, a GitHub Release is published,
> `pubspec.yaml` changes on `main`, or via **Actions → Deploy example to GitHub Pages → Run workflow**.
> If the link 404s, enable **Settings → Pages → Source: GitHub Actions** once for the repository.

## Features

1. **Parse-time precompilation** — XML, CSS selectors, `var()` custom properties, CSS Color 4,
   `calc()`/`min()`/`max()`/`clamp()`, path `d`, and SMIL/CSS clocks are resolved once in
   `SvgParser.compile()` into typed `double` / `Color` / `Float64List` / spline data. Runtime paint
   never re-parses strings.
2. **Static subtree Picture caching** — nodes with `isAnimated == false` are recorded into
   `ui.Picture` on first paint and replayed with `canvas.drawPicture()`, with automatic invalidation
   when embedded async `<image>` assets finish decoding.
3. **Cached PathMetrics** — dash and motion paths keep precomputed `PathMetric` lists; frames only
   call `extractPath` / `getTangentForOffset`.
4. **Zero-allocation paint loop** — paints, layer opacity, and 4×4 column-major matrices are reused
   in place every tick.
5. **Complete non-JS W3C SVG 2 + Filter Effects + SMIL + CSS** — all 17 W3C Filter Effects Level 1
   primitives + 10 CSS `filter` functions, W3C Selectors Level 4 static selectors, `--*`/`var()`,
   `!important` cascade, CSS Color 4 (`oklch`/`oklab`/`lab`/`lch`/`hsl`/`hwb`/`color-mix`),
   CSS `clip-path` shapes, full `<text>`/`<tspan>`/`<textPath>` layout, SMIL `additive`/`accumulate`
   & Syncbase timing, and CSS `@keyframes` (`steps()`, negative delay, `animation-play-state`).

## Install

```yaml
dependencies:
  xue_hua_animated_svg: ^1.3.0
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

### Layout, tint & views: `fit`, `alignment`, `colorFilter`, `viewId`

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `fit` | `BoxFit` | `BoxFit.contain` | How the SVG intrinsic box is inscribed into the widget size (`applyBoxFit`). |
| `alignment` | `AlignmentGeometry` | `Alignment.center` | Places the fitted rect in leftover / cropped space (`alignment.inscribe`). |
| `colorFilter` | `ColorFilter?` | `null` | Whole-picture Flutter tint (e.g. `ColorFilter.mode(color, BlendMode.srcIn)`). Independent of SVG `<filter>`. |
| `viewId` | `String?` | `null` | Optional `<view id="...">` selector to override `viewBox` and `preserveAspectRatio`. |

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

## Supported SVG 2 & CSS surface

Tags and specifications compiled into the scene graph:

| Area | Supported |
|------|-----------|
| Structure & Views | `<svg>` (root & nested viewports, W3C default `overflow: hidden` clipping), `<g>`, `<defs>`, `<symbol>`, `<use>` (with `width`/`height`, aspect sizing, deep style isolation & cycle guard), `<a>`, `<switch>`, `<view>` (selectable via `viewId`) |
| Geometry & Paint Rules | `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`; SVG 2 CSS geometry properties (`x`, `y`, `width`, `height`, `cx`, `cy`, `r`, `rx`, `ry`, `d: path(...)`); `vector-effect="non-scaling-stroke"`; 3-layer `paint-order` (`fill`, `stroke`, `markers`); `shape-rendering`; `mix-blend-mode` & `isolation` |
| Text | `<text>`, `<tspan>`, `<textPath>` (`font`, `font-family`, `font-size`, `font-weight`, `font-style`, `font-variant`, `text-anchor`, `dominant-baseline`, `alignment-baseline`, `baseline-shift`, `letter-spacing`, `word-spacing`, `text-decoration`, `direction`, `xml:space`/`white-space`, `text-transform`, vertical `writing-mode` (`vertical-rl`/`vertical-lr`/`tb`/`tb-rl`), `x`/`y`/`dx`/`dy`/`rotate` lists, `textLength`/`lengthAdjust`, `paint-order`) |
| Paint, Clipping & Masks | `<linearGradient>`, `<radialGradient>` (with SVG 2 `fr` & chained `href` inheritance), `<stop>`, `<pattern>`, `<marker>` (`marker-start`/`mid`/`end`, `orient="auto"`/`"auto-start-reverse"`), `<clipPath>` (`userSpaceOnUse` & `objectBoundingBox`), CSS `clip-path` shapes (`inset`/`circle`/`ellipse`/`polygon`/`path`), `<mask>` (`luminance` & `alpha`), `url(#id) <fallback>` & `currentColor` |
| Raster / Embedded | `<image>` (`data:image/png|jpeg|webp|gif;base64,...` and `data:image/svg+xml,...`) |
| Filters (All 17 W3C Level 1 Primitives + 10 CSS Functions) | `<filter>` (with `filterUnits`, `primitiveUnits` & per-primitive `x`/`y`/`width`/`height` subregions): `<feGaussianBlur>` (`edgeMode`), `<feDropShadow>`, `<feOffset>`, `<feColorMatrix>`, `<feFlood>`, `<feBlend>`, `<feComposite>` (including `operator="arithmetic"`), `<feMerge>`, `<feMergeNode>`, `<feMorphology>`, `<feComponentTransfer>` (`<feFuncR/G/B/A>`), `<feTurbulence>`, `<feDisplacementMap>`, `<feImage>`, `<feTile>`, `<feConvolveMatrix>`, `<feDiffuseLighting>`, `<feSpecularLighting>` (`<feDistantLight>`, `<fePointLight>`, `<feSpotLight>`); CSS `filter:` (`blur`, `drop-shadow`, `brightness`, `contrast`, `grayscale`, `saturate`, `sepia`, `hue-rotate`, `invert`, `opacity`) |
| CSS Selectors, Color & Math | `<style>`, inline `style="..."`, `!important` 6-pass cascade; W3C Selectors Level 4 static selectors (combinators ` ` / `>` / `+` / `~`, attribute selectors `[attr=val]` / `^=` / `$=` / `*=` / `~=` / `|=`, structural pseudos `:first-child` / `:last-child` / `:only-child` / `:nth-child(An+B)` / `:nth-last-child` / `:first-of-type` / `:last-of-type` / `:nth-of-type` / `:empty` / `:root`, `:not()` / `:is()` / `:where()`); CSS custom properties (`--*` & `var()`); CSS Color 4 (`hsl`/`hsla`/`hwb`/`oklab`/`oklch`/`lab`/`lch`/`color-mix`); CSS Math (`calc`/`min`/`max`/`clamp`); `transform-origin`, `transform-box`, standalone `translate`/`rotate`/`scale` |
| SMIL & CSS Animations | `<animate>`, `<animateColor>`, `<animateTransform>`, `<animateMotion>`, `<mpath>`, `<set>`; `additive="sum"`, `accumulate="sum"`, SMIL Syncbase timing (`begin="anim1.end+0.5s"`); CSS `@keyframes`, `steps(N, jump-start|jump-end|jump-none|jump-both|start|end)`, `step-start`/`step-end`, negative `animation-delay`, `animation-play-state: paused|running` |

Skipped metadata (no render): `<style>` text is parsed; `<title>`, `<desc>`, `<metadata>` are ignored.

## Out-of-Scope

Only capabilities requiring a JavaScript engine, interactive browser DOM, external stylesheet/font loader, or deprecated SVG 1.1 specs remain out of scope:

| Unsupported | Why |
|-------------|-----|
| `<script>` & JS DOM APIs | No JavaScript execution engine |
| Event triggers & interactive pseudos (`onclick`, `begin="btn.click"`, `:hover`, `:active`, `:focus`) | No interactive browser DOM / hit-test state machine |
| `<foreignObject>` | No HTML/CSS DOM subtree layout engine |
| `@media`, `@import`, `@font-face` | No external network CSS/font loader or media-query runtime |
| Deprecated SVG 1.1 font/ref tags | `<font>`, `<glyph>`, `<missing-glyph>`, `<hkern>`, `<vkern>`, `<tref>` (removed in SVG 2) |

## License

See [LICENSE](LICENSE).
