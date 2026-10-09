import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/features/decks/domain/deck_catalog.dart';

void main() {
  test('Catálogo de Edison Format completo y sin duplicados', () {
    expect(kDeckCatalog.length, 162);
    expect(kDeckCatalog.map((e) => e.name.toLowerCase()).toSet().length, 162);
    expect(kDeckCatalog.map((e) => e.slug).toSet().length, 162);
    expect(kDeckCatalog.where((e) => e.category == DeckCategory.competitive).length, 11);
    expect(kDeckCatalogByName['blackwing']?.asset, 'assets/decks/blackwing.webp');
    expect(kDeckCatalogByName["koa'ki meiru"]?.slug, 'koaki_meiru');
    expect(kDeckCatalogByName['jinzo otk']?.asset, 'assets/decks/jinzo_otk.webp');
    expect(kDeckCatalogByName['x-insects']?.asset, 'assets/decks/x_insects.webp');
  });
}
