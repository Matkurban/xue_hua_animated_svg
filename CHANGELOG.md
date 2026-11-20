## 1.3.0

* **Full W3C SVG 1.1 / SVG 2 Text Engine (`<text>`, `<tspan>`, `<textPath>`)**:
  * Upgraded `SvgXmlTokenizer` with ordered mixed-content `contentNodes` (`SvgXmlNode`, `SvgXmlTextContent`) and numeric/named XML entity decoding (`&#...;`, `&#x...;`, `&nbsp;`).
  * Added `SvgTextNode`, `SvgTextSpanNode`, `SvgTextPathNode`, and `SvgTextLayoutEngine` supporting `font` shorthand, `font-family` cross-platform fallback chains, `font-size` (`px`/`pt`/`em`/`rem`/`%`/keywords), `font-weight`, `font-style`, `font-variant` (`small-caps`), `text-anchor` (`start`/`middle`/`end`), `dominant-baseline`, `alignment-baseline`, `baseline-shift`, `letter-spacing`, `word-spacing`, `text-decoration`, `direction` (`ltr`/`rtl`), `xml:space`/`white-space` collapsing, per-glyph `x`/`y`/`dx`/`dy`/`rotate` lists, `textLength`/`lengthAdjust` (`spacing` & `spacingAndGlyphs`), `<textPath>` tangent placement, solid/gradient/pattern fill & stroke, `paint-order`, static `ui.Picture` caching, and SMIL/CSS text animations.
* **Phase 1 — Structural Containers, Viewport Spec & SMIL Additions**:
  * Added graphic-level `<a>` (`SvgAnchorNode`), conditional `<switch>` (`SvgSwitchNode` evaluating `requiredExtensions` and `systemLanguage`), nested `<svg>` (`SvgNestedSvgNode` with `viewBox` & `overflow: hidden` clipping), and non-directly-rendered `<symbol>` (`SvgSymbolNode`).
  * Upgraded `<use>` (`SvgUseNode`) with `width`/`height` viewport scaling (including animations), global `elementsById` lookup, and recursion cycle protection.
  * Added SMIL `<set>` (`SvgSetAnimationTrack` supporting `visibility`, `display`, `fill`, `stroke`, and scalar properties, including omitted/indefinite `dur`) and `<animateColor>`.
* **Phase 2 — Masking, Pattern Shaders, Path Markers & ClipPath Upgrade**:
  * Added `<mask>` (`SvgMaskNode`) supporting `luminance` (Rec.709 matrix) and `alpha` compositing via `BlendMode.dstIn`, `maskUnits`, and `maskContentUnits`.
  * Added `<pattern>` (`SvgPatternNode`) with cached offscreen `ui.Image` tile rasterization, `ui.ImageShader(TileMode.repeated)`, `patternTransform`, and `href` template inheritance for both geometry and text.
  * Added `<marker>` (`SvgMarkerNode`) supporting `marker-start`, `marker-mid`, `marker-end`, shorthand `marker`, `orient="auto"` / `"auto-start-reverse"`, and `markerUnits` across `<path>`, `<line>`, `<polyline>`, and `<polygon>`.
  * Upgraded `<clipPath>` (`SvgClipPathNode`) to support `clipPathUnits="objectBoundingBox"`, `<use>` children, and dynamically animated clipping paths.
* **Phase 3 — Embedded Images, Named Views & SVG 2 Radial Gradient**:
  * Added `<image>` (`SvgImageNode`) supporting embedded `data:image/png|jpeg|webp|gif;base64,...` raster decoding with automatic repaint notification (`precacheImages()` helper) and recursive `data:image/svg+xml,...` rendering.
  * Added `<view>` (`SvgViewNode`) and optional `viewId` parameter on `SvgDocument.paint`, `AnimatedSvgPainter`, and all `AnimatedSvgPicture` constructors.
  * Added SVG 2 `<radialGradient fr>` focal radius support (including SMIL animation).
* **Phase 4 — GPU-Accelerated `<filter>` Pipeline (10 `fe*` Primitives)**:
  * Added `SvgFilterNode` and `SvgFilterExecutor` supporting `<filter>` with single-primitive `saveLayer` fast paths and multi-step named-buffer `ui.Picture` graphs across `<feGaussianBlur>`, `<feDropShadow>`, `<feOffset>`, `<feColorMatrix>`, `<feFlood>`, `<feBlend>`, `<feComposite>`, `<feMerge>`/`<feMergeNode>`, `<feMorphology>`, and `<feComponentTransfer>` (`<feFuncR/G/B/A>`).
* **Bug Fixes**:
  * Fixed `<linearGradient>`/`<radialGradient>` `href` template inheritance to share live animated `SvgGradientStop` instances.
  * Fixed `<animateMotion keyPoints="...">` semicolon-delimited parsing per W3C SMIL spec.
* **Example App & Tests**:
  * Added 22 showcase SVGs covering every newly supported element at the front of the example catalog (`catalog_v130_element_items.dart`), extracted shared `CatalogSvgPicture` widget into `example/lib/widgets/`, and added comprehensive unit & offscreen pixel test suites (`svg_text_rendering_test.dart`, `svg_phase1_elements_test.dart`, `svg_phase2_elements_test.dart`, `svg_phase3_elements_test.dart`, `svg_phase4_filters_test.dart`).

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
