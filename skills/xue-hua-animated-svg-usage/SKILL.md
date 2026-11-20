---
name: xue-hua-animated-svg-usage
description: >-
  Use when the user works with xue_hua_animated_svg: AnimatedSvgPicture
  (string/asset/file/network/compiled, fit, alignment, colorFilter, viewId),
  AnimatedSvgController playback, SvgParser.compile, or authoring W3C SVG 2 /
  SMIL / CSS animated SVGs for this pure-Dart engine. Enforces supported SVG/CSS
  capabilities and non-JS/non-DOM Out-of-Scope boundaries.
---

# xue_hua_animated_svg usage

Authoritative guidance for the pure-Dart animated SVG rendering engine (`v1.3.0`). Prefer this skill over guessing APIs or authoring unsupported JS/DOM-dependent SVG features.

## Guidelines

* Import only `package:xue_hua_animated_svg/xue_hua_animated_svg.dart` (single public library entry).
* Prefer `AnimatedSvgPicture.string` / `.asset` / `.network` / `.file` / `.compiled` — do not invent alternate constructors.
* Use widget `fit` (`BoxFit`, default `contain`), `alignment` (`AlignmentGeometry`, default `center`), `colorFilter` (`ColorFilter?`, Flutter whole-picture tint), and `viewId` (`String?`, selects a named `<view id="...">`).
* Always dispose or stop owning `AnimatedSvgController` when the widget tree no longer needs it; pair `SvgParser.compile` with `CompiledSvgScene.dispose()` when precompiling.
* Use `AnimatedSvgPicture.file` only on `dart:io` platforms; never on web (use `.asset`, `.network`, or `.string`).
* Drive playback only through `AnimatedSvgController`: `play`, `pause`, `reset`, `seek`, `setSpeed` — do not wrap the painter in a custom `AnimationController` to scrub the scene.
* Author SVGs within the Supported W3C SVG 2 / CSS surface below. Unknown tags are silently dropped (`null`).
* **Never implement or propose** Out-of-Scope features that require a JS engine, interactive browser DOM, or HTML layout engine (`<script>`, `onclick` / event triggers, `:hover` / `:active` / `:focus`, `<foreignObject>`, remote `@import` / `@font-face`, `@media`).
* Keep SMIL path morphing (`attributeName="d"`) isomorphic (matching command sequences across keyframes).

## Layout, Tint & Named Views

| Parameter | Type | Default | Semantics |
|-----------|------|---------|-----------|
| `fit` | `BoxFit` | `BoxFit.contain` | `applyBoxFit` of intrinsic size into widget layout size. |
| `alignment` | `AlignmentGeometry` | `Alignment.center` | Places fitted rect via `alignment.inscribe`; `AlignmentDirectional` resolves with `Directionality`. |
| `colorFilter` | `ColorFilter?` | `null` | Wraps paint in Flutter `ColorFiltered` for whole-picture tint (independent of SVG `<filter>`). |
| `viewId` | `String?` | `null` | Activates a named `<view id="...">` `viewBox` and `preserveAspectRatio`. |

All named constructors (`string` / `asset` / `file` / `network` / `compiled`) forward these parameters.

## Supported SVG 2 & CSS Surface

| Area | Supported |
|------|-----------|
| Structure & Views | `<svg>` (root & nested viewports, default `overflow: hidden` clipping), `<g>`, `<defs>`, `<symbol>`, `<use>` (with `width`/`height`, aspect scaling, deep style isolation & cycle guard), `<a>`, `<switch>`, `<view>` |
| Geometry & Styling | `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`; SVG 2 CSS geometry properties (`x`, `y`, `width`, `height`, `cx`, `cy`, `r`, `rx`, `ry`, `d: path(...)`); `vector-effect="non-scaling-stroke"`; 3-layer `paint-order` (`fill`, `stroke`, `markers`); `shape-rendering`; `mix-blend-mode` & `isolation` |
| Text | `<text>`, `<tspan>`, `<textPath>`; `font` shorthand, `font-family` fallback, `font-size`, `font-weight`, `font-style`, `font-variant`, `text-anchor`, `dominant-baseline`, `alignment-baseline`, `baseline-shift`, `letter-spacing`, `word-spacing`, `text-decoration`, `direction`, `xml:space`/`white-space`, `text-transform` (`uppercase`/`lowercase`/`capitalize`), vertical `writing-mode` (`vertical-rl`/`vertical-lr`/`tb`/`tb-rl`), per-glyph `x`/`y`/`dx`/`dy`/`rotate` lists, `textLength`/`lengthAdjust` |
| Paint, Clipping & Masks | `<linearGradient>`, `<radialGradient>` (with SVG 2 `fr` & chained `href` inheritance), `<stop>`, `<pattern>`, `<marker>` (`start`/`mid`/`end`, `orient="auto"`/`"auto-start-reverse"`), `<clipPath>` (`userSpaceOnUse` & `objectBoundingBox`), CSS `clip-path` shapes (`inset`/`circle`/`ellipse`/`polygon`/`path`), `<mask>` (`luminance` & `alpha`), `url(#id) <fallback>` & `currentColor` |
| Raster / Embedded | `<image>` (`data:image/png|jpeg|webp|gif;base64,...` and `data:image/svg+xml,...`) |
| Filters (All 17 W3C Level 1 Primitives + 10 CSS Functions) | `<filter>` (with `filterUnits`, `primitiveUnits` & per-primitive `x`/`y`/`width`/`height` subregions): `<feGaussianBlur>` (`edgeMode`), `<feDropShadow>`, `<feOffset>`, `<feColorMatrix>`, `<feFlood>`, `<feBlend>`, `<feComposite>` (including `operator="arithmetic"`), `<feMerge>`/`<feMergeNode>`, `<feMorphology>`, `<feComponentTransfer>` (`<feFuncR/G/B/A>`), `<feTurbulence>`, `<feDisplacementMap>`, `<feImage>`, `<feTile>`, `<feConvolveMatrix>`, `<feDiffuseLighting>`, `<feSpecularLighting>` (`<feDistantLight>`, `<fePointLight>`, `<feSpotLight>`); CSS `filter:` (`blur`, `drop-shadow`, `brightness`, `contrast`, `grayscale`, `saturate`, `sepia`, `hue-rotate`, `invert`, `opacity`) |
| CSS Selectors, Color & Math | `<style>`, inline `style="..."`, `!important` 6-pass cascade; W3C Selectors Level 4 static selectors (`*`, `#id`, `.class`, `tag`, ` `, `>`, `+`, `~`, `[attr]`, `[attr=val]`, `^=`, `$=`, `*=`, `~=`, `|=`, `:first-child`, `:last-child`, `:only-child`, `:nth-child(An+B)`, `:nth-last-child`, `:first-of-type`, `:last-of-type`, `:nth-of-type`, `:empty`, `:root`, `:not()`, `:is()`, `:where()`); CSS custom properties (`--*` & `var(--name, fallback)`); CSS Color 4 (`hex`, `rgb`/`rgba`, `hsl`/`hsla`, `hwb`, `oklab`, `oklch`, `lab`, `lch`, `color-mix()`); CSS Math (`calc()`, `min()`, `max()`, `clamp()`); `transform-origin`, `transform-box`, standalone `translate`/`rotate`/`scale` |
| SMIL & CSS Animations | `<animate>`, `<animateColor>`, `<animateTransform>`, `<animateMotion>`/`<mpath>`, `<set>`; `additive="sum"`, `accumulate="sum"`, SMIL Syncbase timing (`begin="anim1.end+0.5s"`); CSS `@keyframes`, `steps(N, jump-start|jump-end|jump-none|jump-both|start|end)`, `step-start`/`step-end`, negative `animation-delay`, `animation-play-state: paused|running` |

## Out-of-Scope (Hard Non-JS / Non-DOM Boundary)

| Unsupported | Why |
|-------------|-----|
| `<script>` & JS DOM APIs | No JavaScript engine |
| Interactive events & dynamic pseudos (`onclick`, `begin="btn.click"`, `:hover`, `:active`, `:focus`) | No browser event/hit-test DOM loop |
| `<foreignObject>` | No HTML/CSS layout engine |
| `@media`, `@import`, `@font-face` | No external stylesheet/font loader or media-query viewport engine |
| Deprecated SVG 1.1 font/ref tags (`<font>`, `<glyph>`, `<missing-glyph>`, `<hkern>`, `<vkern>`, `<tref>`) | Removed in W3C SVG 2 |

## Examples

### Widget + controller

```dart
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

final controller = AnimatedSvgController(autoPlay: true, speed: 1.0);

AnimatedSvgPicture.asset(
  'assets/svgs/elephant.svg',
  controller: controller,
  width: 280,
  height: 160,
  fit: BoxFit.cover,
  alignment: Alignment.topLeft,
  colorFilter: const ColorFilter.mode(Color(0xFF22C55E), BlendMode.srcIn),
  viewId: 'zoomedView', // optional <view id="zoomedView">
);

// Playback
controller.pause();
controller.seek(const Duration(milliseconds: 500));
controller.setSpeed(2.0);
```

### Network / string / precompile

```dart
AnimatedSvgPicture.network(
  'https://example.com/motion.svg',
  controller: controller,
);

AnimatedSvgPicture.string(
  AnimatedSvgShowcasePresets.cyberCoreCompositeSvg,
  controller: controller,
);

final scene = SvgParser.compile(svgXml);
AnimatedSvgPicture.compiled(scene, controller: controller);
// later:
scene.dispose();
```

### Declarative SVG 2 + CSS + SMIL example

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <style>
    :root { --accent: oklch(0.68 0.18 150); }
    g > circle.pulse {
      fill: var(--accent);
      filter: drop-shadow(0 4px 6px rgba(0, 0, 0, 0.25));
      animation: beat 1.2s steps(4, jump-none) infinite;
    }
    @keyframes beat {
      from { opacity: 0.4; }
      to   { opacity: 1.0; }
    }
  </style>
  <g>
    <circle class="pulse" cx="60" cy="60" r="24">
      <animate id="grow" attributeName="r" from="18" to="32" dur="1s" fill="freeze"/>
      <animate attributeName="stroke-width" from="1" to="6" begin="grow.end+0.2s" dur="0.6s" fill="freeze"/>
    </circle>
  </g>
</svg>
```
