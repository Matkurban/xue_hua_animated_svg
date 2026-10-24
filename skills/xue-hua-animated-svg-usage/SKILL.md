---
name: xue-hua-animated-svg-usage
description: >-
  Use when the user works with xue_hua_animated_svg: AnimatedSvgPicture
  (string/asset/file/network/compiled, fit, alignment, colorFilter), AnimatedSvgController
  playback, SvgParser.compile, or authoring SMIL/CSS animated SVGs for this engine.
  Enforces supported SVG tags and Out-of-Scope hard boundaries.
---

# xue_hua_animated_svg usage

Authoritative guidance for the pure-Dart animated SVG engine. Prefer this skill over guessing APIs or inventing unsupported SVG/CSS features.

## Guidelines

* Import only `package:xue_hua_animated_svg/xue_hua_animated_svg.dart` (single public library entry).
* Prefer `AnimatedSvgPicture.string` / `.asset` / `.network` / `.file` / `.compiled` — do not invent alternate constructors.
* Use widget `fit` (`BoxFit`, default `contain`), `alignment` (`AlignmentGeometry`, default `center`), and `colorFilter` (`ColorFilter?`). `colorFilter` is a Flutter tint layer, **not** SVG `<filter>` / `fe*`.
* Always dispose or stop owning `AnimatedSvgController` when the widget tree no longer needs it; pair with `SvgParser.compile` + `CompiledSvgScene.dispose()` when precompiling.
* Use `AnimatedSvgPicture.file` only on `dart:io` platforms; never on web (use `.asset`, `.network`, or `.string`).
* Drive playback only through `AnimatedSvgController`: `play`, `pause`, `reset`, `seek`, `setSpeed` — do not wrap the painter in a custom `AnimationController` to scrub the scene.
* Author SVGs strictly within the Supported surface below. Unknown tags are silently dropped (`null`).
* **Never implement or propose** Out-of-Scope features for this package (no `<filter>` graphs, no `<text>` layout, no `<foreignObject>`, no complex CSS selectors / `@media` / `@import`).
* CSS selectors allowed: `#id`, `.class`, `tagName` only. Reject descendant/child/sibling/pseudo/attribute selectors.
* CSS `filter: blur(...)` is the only blur path (sigma → `MaskFilter`). Do not add SVG `<filter>` / `fe*` support.
* Prefer SMIL (`<animate>`, `<animateTransform>`, `<animateMotion>` / `<mpath>`) and CSS `@keyframes` + `transform-origin` for motion; keep path morphs isomorphic (`d` command sequences match).
* Do not expand the engine with a full CSS lexer or text-shaping stack — Out-of-Scope is a hard product boundary.

## `fit`, `alignment`, and `colorFilter`

| Parameter | Type | Default | Semantics |
|-----------|------|---------|-----------|
| `fit` | `BoxFit` | `BoxFit.contain` | `applyBoxFit` of intrinsic → layout size. |
| `alignment` | `AlignmentGeometry` | `Alignment.center` | Places fitted rect via `alignment.inscribe`; `AlignmentDirectional` resolves with `Directionality`. |
| `colorFilter` | `ColorFilter?` | `null` | Wraps paint in `ColorFiltered` for whole-picture tint. Survives animation frames. |

Do **not** confuse `colorFilter` with Out-of-Scope SVG `<filter>` graphs. Prefer `ColorFilter.mode(color, BlendMode.srcIn)` for icon-style tinting.

All named constructors (`string` / `asset` / `file` / `network` / `compiled`) forward all three parameters.

## Supported SVG surface

| Area | Supported |
|------|-----------|
| Structure | `<svg>`, `<g>`, `<defs>`, `<symbol>`, `<use>` |
| Geometry | `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>` |
| Paint | `<linearGradient>`, `<radialGradient>`, `<stop>`, `<clipPath>` |
| SMIL | `<animate>`, `<animateTransform>`, `<animateMotion>`, `<mpath>` |
| CSS | `<style>`, `@keyframes`; selectors `#id` / `.class` / `tagName`; optional `filter: blur(...)` |

## Out-of-Scope (do not implement)

| Forbidden | Why |
|-----------|-----|
| `<filter>` and all `fe*` | Not a filter-graph engine |
| `<text>`, `<tspan>`, `<textPath>`, `<tref>` | No glyph / text shaping |
| `<foreignObject>` | No HTML/Flutter embedding |
| Complex CSS selectors / `@media` / `@import` | Only simple `#id` / `.class` / `tagName` |
| Also dropped | `<image>`, `<mask>`, `<marker>`, `<pattern>`, `<switch>`, `<a>`, `<script>`, `<view>`, `<set>`, and any tag not in Supported |

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

### Minimal in-scope animated SVG

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <circle cx="50" cy="50" r="20" fill="#22c55e">
    <animate attributeName="r" values="12;28;12" dur="1.8s" repeatCount="indefinite"/>
    <animate attributeName="opacity" values="0.35;1;0.35" dur="1.8s" repeatCount="indefinite"/>
  </circle>
</svg>
```

Do **not** author examples that rely on `<text>`, `<filter>`, `<foreignObject>`, or selectors like `g > circle:first-child`.
