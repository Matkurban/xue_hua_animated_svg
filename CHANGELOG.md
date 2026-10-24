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
