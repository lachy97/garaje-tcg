import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/features/decks/domain/deck_catalog.dart';

void main() {
  test('Catálogo de Edison Format completo y sin duplicados', () {
    expect(kDeckCatalog.length, 55);
    expect(kDeckCatalog.map((e) => e.name.toLowerCase()).toSet().length, 55);
    expect(kDeckCatalog.map((e) => e.slug).toSet().length, 55);
    expect(kDeckCatalog.where((e) => e.category == DeckCategory.competitive).length, 11);
    expect(kDeckCatalogByName['blackwing']?.asset, 'assets/decks/blackwing.webp');
    expect(kDeckCatalogByName["koa'ki meiru"]?.slug, 'koaki_meiru');
  });
}
