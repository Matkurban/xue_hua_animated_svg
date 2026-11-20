## 1.3.0

* **Full W3C SVG 1.1 / SVG 2 Text Engine (`<text>`, `<tspan>`, `<textPath>`)**:
  * Upgraded `SvgXmlTokenizer` with ordered mixed-content `contentNodes` (`SvgXmlNode`, `SvgXmlTextContent`) and numeric/named XML entity decoding (`&#...;`, `&#x...;`, `&nbsp;`).
  * Added `SvgTextNode`, `SvgTextSpanNode`, `SvgTextPathNode`, and `SvgTextLayoutEngine` supporting `font` shorthand, `font-family` cross-platform fallback chains, `font-size` (`px`/`pt`/`em`/`rem`/`%`/keywords), `font-weight`, `font-style`, `font-variant` (`small-caps`), `text-anchor` (`start`/`middle`/`end`), `dominant-baseline`, `alignment-baseline`, `baseline-shift`, `letter-spacing`, `word-spacing`, `text-decoration`, `direction` (`ltr`/`rtl`), `xml:space`/`white-space` collapsing, `text-transform` (`uppercase`/`lowercase`/`capitalize`), vertical `writing-mode` (`vertical-rl`/`vertical-lr`/`tb`/`tb-rl`), per-glyph `x`/`y`/`dx`/`dy`/`rotate` lists, `textLength`/`lengthAdjust` (`spacing` & `spacingAndGlyphs`), `<textPath>` tangent placement, solid/gradient/pattern fill & stroke, `paint-order`, static `ui.Picture` caching, and SMIL/CSS text animations.
* **Structural Containers, Viewport Clipping & Embedded Assets**:
  * Added graphic-level `<a>` (`SvgAnchorNode`), conditional `<switch>` (`SvgSwitchNode` evaluating `requiredExtensions` and `systemLanguage`), nested `<svg>` (`SvgNestedSvgNode`), non-directly-rendered `<symbol>` (`SvgSymbolNode`), and `<view>` (`SvgViewNode` + optional `viewId` parameter on `SvgDocument.paint`, `AnimatedSvgPainter`, and all `AnimatedSvgPicture` constructors).
  * Enforced W3C SVG root `<svg>` default `overflow: hidden` viewport clipping (unless `overflow="visible"`), preventing geometry overflow outside `viewBox`.
  * Upgraded `<use>` (`SvgUseNode`) with `width`/`height` single-dimension aspect sizing, deep style & `cachedPicture` isolation, global `elementsById` lookup, and recursion cycle protection.
  * Added `<image>` (`SvgImageNode`) supporting embedded `data:image/png|jpeg|webp|gif;base64,...` raster decoding with automatic `ui.Picture` cache invalidation (`SvgDocument.notifyAsyncAssetLoaded()`) and recursive `data:image/svg+xml,...` rendering.
* **Masking, Pattern Shaders, Path Markers, ClipPath & Geometry Paint**:
  * Added `<mask>` (`SvgMaskNode`, `luminance` & `alpha`), `<pattern>` (`SvgPatternNode` with cached `ui.ImageShader` tiling & `href` inheritance), `<marker>` (`SvgMarkerNode` with `marker-start`/`mid`/`end`, `orient="auto"`/`"auto-start-reverse"`), and `<clipPath>` (`userSpaceOnUse` & `objectBoundingBox` + `<use>` children).
  * Added CSS `clip-path` basic shapes (`inset()`, `circle()`, `ellipse()`, `polygon()`, `path()` in `svg_css_clip_shape.dart`).
  * Added SVG 2 `<radialGradient fr>` focal radius, chained gradient `href` template inheritance (`SvgGradientNode.resolveTemplate`), `url(#id) <fallback>` paint servers, `currentColor`, `vector-effect="non-scaling-stroke"`, full 3-layer `paint-order` (`fill`, `stroke`, `markers`), `shape-rendering`, and `mix-blend-mode` / `isolation`.
* **Complete W3C Filter Effects Level 1 Pipeline (All 17 `fe*` Primitives + 10 CSS `filter` Functions)**:
  * Added `SvgFilterNode`, `SvgFilterExecutor`, `SvgFilterNoiseEngine` (`svg_filter_noise.dart`), and `SvgFilterAdvancedEngine` (`svg_filter_advanced.dart`) covering `<feGaussianBlur>` (with `edgeMode`), `<feDropShadow>`, `<feOffset>`, `<feColorMatrix>`, `<feFlood>`, `<feBlend>`, `<feComposite>` (including `operator="arithmetic"`), `<feMerge>`/`<feMergeNode>`, `<feMorphology>`, `<feComponentTransfer>` (`<feFuncR/G/B/A>`), `<feTurbulence>`, `<feDisplacementMap>`, `<feImage>`, `<feTile>`, `<feConvolveMatrix>`, `<feDiffuseLighting>`, and `<feSpecularLighting>` (`<feDistantLight>`, `<fePointLight>`, `<feSpotLight>`), plus `primitiveUnits` and per-primitive `x`/`y`/`width`/`height` subregions.
  * Added all 10 CSS `filter:` functions (`blur`, `drop-shadow`, `brightness`, `contrast`, `grayscale`, `saturate`, `sepia`, `hue-rotate`, `invert`, `opacity`).
* **W3C CSS Selectors Level 4, Custom Properties, Color 4 & Math Functions**:
  * Added `SvgCssSelectorParser` (`svg_css_selector.dart`) supporting static combinators (` `, `>`, `+`, `~`), attribute selectors (`[attr]`, `=`, `~=`, `|=`, `^=`, `$=`, `*=`), structural pseudo-classes (`:first-child`, `:last-child`, `:only-child`, `:nth-child(An+B)`, `:nth-last-child`, `:first-of-type`, `:last-of-type`, `:nth-of-type`, `:empty`, `:root`), and `:not()`/`:is()`/`:where()`.
  * Added `SvgCssVariables` (`svg_css_variables.dart`) for `--*` custom properties and `var(--name, fallback)`, 6-pass `!important` cascade precedence, SVG 2 CSS geometry properties (`x`, `y`, `width`, `height`, `cx`, `cy`, `r`, `rx`, `ry`, `d: path(...)`), `transform-box`, and standalone `translate`/`rotate`/`scale`.
  * Added `SvgCssColor4` (`svg_css_color4.dart`) for `hsl()`/`hsla()`/`hwb()`/`oklab()`/`oklch()`/`lab()`/`lch()`/`color-mix()`, and `SvgCssMath` (`svg_css_math.dart`) for `calc()`/`min()`/`max()`/`clamp()`.
* **SMIL & CSS Animation Completeness**:
  * Added SMIL `<set>`, `<animateColor>`, `additive="sum"`, `accumulate="sum"`, and compile-time SMIL Syncbase timing chains (`SvgSmilSyncbaseResolver` in `svg_smil_syncbase.dart`, e.g. `begin="anim1.end+0.5s"`).
  * Added `SvgStepEasing` (`svg_step_easing.dart`) for W3C CSS `steps(N, jump-start|jump-end|jump-none|jump-both|start|end)` / `step-start` / `step-end`, negative `animation-delay`, `animation-play-state: paused | running`, and exact identity fast-path for `linear` timing curves.
* **Bug Fixes**:
  * Fixed `<linearGradient>`/`<radialGradient>` `href` template inheritance to share live animated `SvgGradientStop` instances.
  * Fixed `<animateMotion keyPoints="...">` semicolon-delimited parsing per W3C SMIL spec.
  * Fixed `SvgFeComposite` / `SvgFeBlend` layer isolation so transparent pixels are not polluted by underlying canvas content.
* **Example App & Tests**:
  * Added 22 v1.3.0 showcase SVGs (`catalog_v130_element_items.dart`), bottom `NavigationBar` (`MainTabPage`) with a 42-asset `FullSvgGalleryPage` & fullscreen `FullSvgPreviewPage`, and comprehensive unit & offscreen pixel test suites (`svg_text_rendering_test.dart`, `svg_phase1_elements_test.dart`–`svg_phase4_filters_test.dart`, `svg_full_svg_assets_test.dart`, `svg_w3c_stage1_css_test.dart`–`svg_w3c_stage4_anim_text_test.dart`).

## 1.2.0

* Refactored internal architecture into modular, single-responsibility Dart files following standard Dart and Flutter package conventions without any breaking changes to public APIs or runtime behavior:
  * **Model (`lib/src/model/`)**: Split monolithic `svg_node.dart` into `svg_preserve_aspect_ratio.dart`, `svg_precompiled_path.dart`, `svg_element.dart`, `svg_container_nodes.dart`, `svg_geometry_node.dart`, `svg_shape_nodes.dart`, and `svg_document.dart`.
  * **Animation (`lib/src/animation/`)**: Extracted `svg_animation_timing.dart`, `svg_property_tracks.dart`, and `svg_transform_tracks.dart` from `svg_timeline.dart`.
  * **Parser (`lib/src/parser/`)**: Modularized `svg_xml_parser.dart` and `svg_css_parser.dart` into `svg_xml_tokenizer.dart`, `svg_smil_compiler.dart`, `svg_css_models.dart`, `svg_named_colors.dart`, `svg_css_value_parser.dart`, and `svg_css_keyframe_compiler.dart`.
  * **Widget (`lib/src/widget/`)**: Separated `animated_svg_painter.dart` and `animated_svg_showcase_presets.dart` from `animated_svg_picture.dart`.
  * **Example (`example/lib/data/`)**: Split `svg_catalog.dart` into categorized catalog modules (`svg_catalog_item.dart`, `catalog_core_items.dart`, `catalog_nature_space_items.dart`, `catalog_tech_ui_life_items.dart`, and `catalog_transport_animal_sport_art_items.dart`).

## 1.1.1

* Fixed `SvgGroupNode.initializeGeometry`: When aggregating the `cachedBounds` of child nodes, 
  the implementation now filters out non-visible elements—specifically `<defs>`, `<clipPath>`, 
  and nodes with `display: none`. It uses `_transformRectByMatrix` to map each child's local bounding box into the parent container's coordinate system based on the child's `baseTransformMatrix`. 
  Additionally, it now correctly handles horizontal or vertical `<line>` elements (which are non-empty line segments with zero width or height), ensuring more precise alignment for percentage-based or keyword-based `transform-origin` values ​​on container nodes.

## 1.1.0

* Add `fit` (`BoxFit`, default `BoxFit.contain`), `colorFilter` (`ColorFilter?`),
  and `alignment` (`AlignmentGeometry`, default `Alignment.center`) to every
  `AnimatedSvgPicture` constructor.
* `fit` maps the SVG intrinsic paint box into the widget layout size via
  `applyBoxFit`. SVG `preserveAspectRatio` still applies for viewBox → intrinsic.
* After `applyBoxFit`, leftover / cropped space is placed with
  `alignment.inscribe`. Default `Alignment.center` matches the prior centered
  layout; `AlignmentDirectional` resolves via ambient `Directionality`.
* `colorFilter` is a Flutter post-process whole-picture tint (`ColorFiltered`);
  it is **not** SVG `<filter>` / `fe*` support. Orthogonal to `fit` / `alignment`
  and to SVG `preserveAspectRatio`.
* Example preview page: interactive Fit / alignment chips and tint controls.
* Package skill and bilingual README document the new parameters.

## 1.0.0

* Initial public release of the pure-Dart animated SVG engine.
* Precompiles SMIL (`animate`, `animateTransform`, `animateMotion`) and CSS
  `@keyframes` into a typed AST with zero string parsing on the paint path.
* Static subtree `ui.Picture` caching, cached `PathMetrics`, and in-place
  paint/transform buffers for 60/120fps rendering.
* Public API: `AnimatedSvgPicture` (`.string` / `.asset` / `.file` / `.network` / `.compiled`),
  `AnimatedSvgController` (`play` / `pause` / `seek` / `reset` / `setSpeed`),
  and `AnimatedSvgShowcasePresets.cyberCoreCompositeSvg`.
* `AnimatedSvgPicture.file` (dart:io; unsupported on web) and
  `AnimatedSvgPicture.network` (via `package:http`, optional headers).
* Example app redesigned as a Chinese catalog list → preview flow, themed with
  FlexColorScheme `shadGreen` via `material_ui`.
* GitHub Pages workflow builds the web example for live demos on version tags /
  releases / pubspec version bumps on `main`.
* Package metadata: repository, topics, and screenshots for pub.dev.
