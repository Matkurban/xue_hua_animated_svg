import 'package:example/data/svg_catalog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

/// Shared widget rendering an [SvgCatalogItem] across multiple example pages
/// (home thumbnails and full preview).
class CatalogSvgPicture extends StatelessWidget {
  const CatalogSvgPicture({
    super.key,
    required this.item,
    this.controller,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.colorFilter,
  });

  final SvgCatalogItem item;
  final AnimatedSvgController? controller;
  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final ColorFilter? colorFilter;

  @override
  Widget build(BuildContext context) {
    switch (item.kind) {
      case SvgCatalogSourceKind.asset:
        return AnimatedSvgPicture.asset(
          item.assetPath!,
          controller: controller,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          colorFilter: colorFilter,
        );
      case SvgCatalogSourceKind.string:
        return AnimatedSvgPicture.string(
          item.svgString!,
          controller: controller,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          colorFilter: colorFilter,
        );
      case SvgCatalogSourceKind.network:
        return AnimatedSvgPicture.network(
          item.networkUrl!,
          controller: controller,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          colorFilter: colorFilter,
        );
    }
  }
}
