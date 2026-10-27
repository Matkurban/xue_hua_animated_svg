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
