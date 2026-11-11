import 'catalog_core_items.dart';
import 'catalog_nature_space_items.dart';
import 'catalog_tech_ui_life_items.dart';
import 'catalog_transport_animal_sport_art_items.dart';
import 'svg_catalog_item.dart';

export 'svg_catalog_item.dart';

/// Curated showcase catalog (Chinese UI copy).
abstract final class SvgCatalog {
  static final List<SvgCatalogItem> items = [
    ...coreCatalogItems,
    ...natureSpaceCatalogItems,
    ...techUiLifeCatalogItems,
    ...transportAnimalSportArtCatalogItems,
  ];

  static SvgCatalogItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}
