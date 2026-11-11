import 'package:flutter/widgets.dart' show BoxFit;

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
    this.initialFit = BoxFit.contain,
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

  /// Initial [BoxFit] mode selected when opening `PreviewPage`.
  final BoxFit initialFit;
}
