import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

/// How a catalog entry loads its SVG content.
enum SvgCatalogSourceKind {
  /// Load from `example/assets/svgs/...`.
  asset,

  /// Use an in-memory SVG string (e.g. CyberCore preset).
  string,

  /// Download SVG XML over HTTP(S).
  network,
}

/// One showcase item shown on the home list.
class SvgCatalogItem {
  const SvgCatalogItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.kind,
    this.assetPath,
    this.svgString,
    this.networkUrl,
    this.iconName = 'auto_awesome',
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> tags;
  final SvgCatalogSourceKind kind;
  final String? assetPath;
  final String? svgString;
  final String? networkUrl;

  /// Logical icon key used by the home list (mapped to Material Icons).
  final String iconName;
}

/// Curated showcase catalog (Chinese UI copy).
abstract final class SvgCatalog {
  static final List<SvgCatalogItem> items = [
    const SvgCatalogItem(
      id: 'elephant',
      title: '大象描边',
      subtitle: '资源文件：缩放 + 旋转卡片（animateTransform）',
      tags: ['asset', 'animateTransform'],
      kind: SvgCatalogSourceKind.asset,
      assetPath: 'assets/svgs/elephant.svg',
      iconName: 'pets',
    ),
    SvgCatalogItem(
      id: 'cyber_core',
      title: 'CyberCore 合成演示',
      subtitle: '内存预设：3D CSS、渐变、描边生长、形变、轨道运动',
      tags: ['preset', 'composite', '3D', 'morph', 'motion'],
      kind: SvgCatalogSourceKind.string,
      svgString: AnimatedSvgShowcasePresets.cyberCoreCompositeSvg,
      iconName: 'auto_awesome',
    ),
    const SvgCatalogItem(
      id: 'network_elephant',
      title: '网络大象',
      subtitle: 'AnimatedSvgPicture.network：从 GitHub raw 拉取 elephant.svg',
      tags: ['network', 'http'],
      kind: SvgCatalogSourceKind.network,
      networkUrl:
          'https://raw.githubusercontent.com/Matkurban/xue_hua_animated_svg/main/example/assets/svgs/elephant.svg',
      iconName: 'cloud_download',
    ),
    const SvgCatalogItem(
      id: 'pulse_circle',
      title: '呼吸圆',
      subtitle: 'SMIL animate：半径与透明度脉冲',
      tags: ['animate', 'opacity'],
      kind: SvgCatalogSourceKind.asset,
      assetPath: 'assets/svgs/pulse_circle.svg',
      iconName: 'radio_button_checked',
    ),
    const SvgCatalogItem(
      id: 'spin_card',
      title: '旋转卡片',
      subtitle: 'animateTransform：旋转 + 叠加缩放',
      tags: ['animateTransform', 'scale'],
      kind: SvgCatalogSourceKind.asset,
      assetPath: 'assets/svgs/spin_card.svg',
      iconName: 'crop_square',
    ),
    const SvgCatalogItem(
      id: 'orbit_probe',
      title: '轨道探测器',
      subtitle: 'animateMotion + mpath，自动切线朝向',
      tags: ['animateMotion', 'mpath'],
      kind: SvgCatalogSourceKind.asset,
      assetPath: 'assets/svgs/orbit_probe.svg',
      iconName: 'rocket_launch',
    ),
    const SvgCatalogItem(
      id: 'css_spinner',
      title: 'CSS 旋转环',
      subtitle: 'CSS @keyframes + transform-origin',
      tags: ['css', 'keyframes'],
      kind: SvgCatalogSourceKind.asset,
      assetPath: 'assets/svgs/css_spinner.svg',
      iconName: 'sync',
    ),
    const SvgCatalogItem(
      id: 'path_morph',
      title: '路径形变',
      subtitle: '同构 path d 插值（星形 ↔ 多边形）',
      tags: ['morph', 'path'],
      kind: SvgCatalogSourceKind.asset,
      assetPath: 'assets/svgs/path_morph.svg',
      iconName: 'change_history',
    ),
    const SvgCatalogItem(
      id: 'dash_draw',
      title: '描边绘制',
      subtitle: 'stroke-dashoffset + pathLength 生长动画',
      tags: ['dash', 'pathLength'],
      kind: SvgCatalogSourceKind.asset,
      assetPath: 'assets/svgs/dash_draw.svg',
      iconName: 'timeline',
    ),
    const SvgCatalogItem(
      id: 'discrete_steps',
      title: '离散步进',
      subtitle: 'calcMode="discrete" 颜色与位置跳变',
      tags: ['discrete', 'animate'],
      kind: SvgCatalogSourceKind.asset,
      assetPath: 'assets/svgs/discrete_steps.svg',
      iconName: 'stairs',
    ),
    const SvgCatalogItem(
      id: 'solar_orbit',
      title: '星系轨道',
      subtitle: '径向渐变焦点动画 + clipPath + use 星空 + keyPoints 切线轨道',
      tags: ['radialGradient', 'clipPath', 'use', 'animateMotion'],
      kind: SvgCatalogSourceKind.asset,
      assetPath: 'assets/svgs/solar_orbit.svg',
      iconName: 'public',
    ),
    const SvgCatalogItem(
      id: 'neon_equalizer',
      title: '霓虹均衡器',
      subtitle: 'CSS @keyframes alternate + transform-origin 底部锚点 + 折线变色',
      tags: ['css', 'transform-origin', 'polyline'],
      kind: SvgCatalogSourceKind.asset,
      assetPath: 'assets/svgs/neon_equalizer.svg',
      iconName: 'equalizer',
    ),
  ];

  static SvgCatalogItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}
