# SVG demo sources

All demo SVGs under this folder are **original assets authored for this package example**,
except where noted. They are intentionally small and focused so each one exercises a
specific animation path supported by `xue_hua_animated_svg`.

| File | Technique exercised | Origin |
|------|---------------------|--------|
| `elephant.svg` | SMIL `animateTransform` (scale/rotate), stroke styling | Existing package example asset (kept) |
| `pulse_circle.svg` | SMIL `<animate>` on `r` / `opacity` | Original for this showcase |
| `spin_card.svg` | SMIL `<animateTransform>` rotate + additive scale | Original for this showcase |
| `orbit_probe.svg` | `<animateMotion rotate="auto">` + `<mpath>` | Original for this showcase |
| `css_spinner.svg` | CSS `@keyframes` + `transform-origin` | Original for this showcase |
| `path_morph.svg` | Isomorphic path morph (`attributeName="d"`) | Original for this showcase |
| `dash_draw.svg` | `stroke-dasharray` / `stroke-dashoffset` + `pathLength` | Original for this showcase |
| `discrete_steps.svg` | SMIL `calcMode="discrete"` | Original for this showcase |

The in-memory **CyberCore** composite preset (`AnimatedSvgShowcasePresets.cyberCoreCompositeSvg`)
is defined in the package library (not an asset file). It combines 3D CSS transforms,
streaming gradients, dash growth, path morphing, and orbit motion in one scene.

## Network demo

The example catalog entry **网络大象** uses `AnimatedSvgPicture.network` with:

`https://raw.githubusercontent.com/Matkurban/xue_hua_animated_svg/main/example/assets/svgs/elephant.svg`

Local file loading (`AnimatedSvgPicture.file`) is documented in the README; the showcase app
does not ship a file-picker demo (web-incompatible).
