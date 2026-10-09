/// Mazos de Edison Format con su imagen, tomados de https://edisonformat.net/decks
/// (las imágenes están en assets/decks/). Se cargan en la BD al abrir la app;
/// los mazos que no están aquí se pueden añadir a mano.
library;

enum DeckCategory { competitive, rogue, casual, custom }

extension DeckCategoryLabel on DeckCategory {
  String get label => switch (this) {
        DeckCategory.competitive => 'Competitivo',
        DeckCategory.rogue => 'Rogue',
        DeckCategory.casual => 'Casual',
        DeckCategory.custom => 'Añadidos',
      };
}

class DeckCatalogEntry {
  const DeckCatalogEntry(this.name, this.category, this.slug);

  final String name;
  final DeckCategory category;
  final String slug;

  String get asset => 'assets/decks/$slug.webp';
}

const kDeckCatalog = <DeckCatalogEntry>[
  DeckCatalogEntry('Blackwing', DeckCategory.competitive, 'blackwing'),
  DeckCatalogEntry('Vayu Turbo', DeckCategory.competitive, 'vayu_turbo'),
  DeckCatalogEntry('Hybrid', DeckCategory.competitive, 'hybrid'),
  DeckCatalogEntry('Hero Frog', DeckCategory.competitive, 'hero_frog'),
  DeckCatalogEntry('Junk Frog', DeckCategory.competitive, 'junk_frog'),
  DeckCatalogEntry('Diva Zombie', DeckCategory.competitive, 'diva_zombie'),
  DeckCatalogEntry('Diva Hero', DeckCategory.competitive, 'diva_hero'),
  DeckCatalogEntry('Diva Hero Beat', DeckCategory.competitive, 'diva_hero_beat'),
  DeckCatalogEntry('Dragon Turbo', DeckCategory.competitive, 'dragon_turbo'),
  DeckCatalogEntry('Lightsworn', DeckCategory.competitive, 'lightsworn'),
  DeckCatalogEntry('Machina', DeckCategory.competitive, 'machina'),
  DeckCatalogEntry('Amaryllis', DeckCategory.rogue, 'amaryllis'),
  DeckCatalogEntry('Cat', DeckCategory.rogue, 'cat'),
  DeckCatalogEntry('Dragon Aggro', DeckCategory.rogue, 'dragon_aggro'),
  DeckCatalogEntry('Fairy', DeckCategory.rogue, 'fairy'),
  DeckCatalogEntry('Fish OTK', DeckCategory.rogue, 'fish_otk'),
  DeckCatalogEntry('Flamvell', DeckCategory.rogue, 'flamvell'),
  DeckCatalogEntry('Gladiator Beast', DeckCategory.rogue, 'gladiator_beast'),
  DeckCatalogEntry('Hero Beat', DeckCategory.rogue, 'hero_beat'),
  DeckCatalogEntry('Norleras', DeckCategory.rogue, 'norleras'),
  DeckCatalogEntry('Quickdraw Plant', DeckCategory.rogue, 'quickdraw_plant'),
  DeckCatalogEntry('Ancient Gear', DeckCategory.rogue, 'ancient_gear'),
  DeckCatalogEntry('Diva FLIP', DeckCategory.rogue, 'diva_flip'),
  DeckCatalogEntry('Gemini', DeckCategory.rogue, 'gemini'),
  DeckCatalogEntry('Gravekeeper', DeckCategory.rogue, 'gravekeeper'),
  DeckCatalogEntry('Hopeless Dragon', DeckCategory.rogue, 'hopeless_dragon'),
  DeckCatalogEntry('Kuraz', DeckCategory.rogue, 'kuraz'),
  DeckCatalogEntry('Machina Gadget', DeckCategory.rogue, 'machina_gadget'),
  DeckCatalogEntry('Machina Roid', DeckCategory.rogue, 'machina_roid'),
  DeckCatalogEntry('Quickdraw Volcanic', DeckCategory.rogue, 'quickdraw_volcanic'),
  DeckCatalogEntry('TeleDAD', DeckCategory.rogue, 'teledad'),
  DeckCatalogEntry('Alien', DeckCategory.casual, 'alien'),
  DeckCatalogEntry('Anti-Meta', DeckCategory.casual, 'anti_meta'),
  DeckCatalogEntry('Assault Mode', DeckCategory.casual, 'assault_mode'),
  DeckCatalogEntry('Batteryman', DeckCategory.casual, 'batteryman'),
  DeckCatalogEntry('Black Salvo', DeckCategory.casual, 'black_salvo'),
  DeckCatalogEntry('Bushi', DeckCategory.casual, 'bushi'),
  DeckCatalogEntry('Cloudian', DeckCategory.casual, 'cloudian'),
  DeckCatalogEntry('Codarus', DeckCategory.casual, 'codarus'),
  DeckCatalogEntry('Crystal Beast', DeckCategory.casual, 'crystal_beast'),
  DeckCatalogEntry('Dark Gaia', DeckCategory.casual, 'dark_gaia'),
  DeckCatalogEntry('Earthbound Immortal', DeckCategory.casual, 'earthbound_immortal'),
  DeckCatalogEntry('Fortune Lady', DeckCategory.casual, 'fortune_lady'),
  DeckCatalogEntry('Insect', DeckCategory.casual, 'insect'),
  DeckCatalogEntry('Koa\'ki Meiru', DeckCategory.casual, 'koaki_meiru'),
  DeckCatalogEntry('Neo-Spacian', DeckCategory.casual, 'neo_spacian'),
  DeckCatalogEntry('Monster Mash', DeckCategory.casual, 'monster_mash'),
  DeckCatalogEntry('Morphtronic', DeckCategory.casual, 'morphtronic'),
  DeckCatalogEntry('Ojama', DeckCategory.casual, 'ojama'),
  DeckCatalogEntry('Psychic', DeckCategory.casual, 'psychic'),
  DeckCatalogEntry('Relinquished', DeckCategory.casual, 'relinquished'),
  DeckCatalogEntry('Six Samurai', DeckCategory.casual, 'six_samurai'),
  DeckCatalogEntry('Spaceship', DeckCategory.casual, 'spaceship'),
  DeckCatalogEntry('Uria', DeckCategory.casual, 'uria'),
  DeckCatalogEntry('X-Saber', DeckCategory.casual, 'x_saber'),
];

/// Entrada del catálogo por nombre normalizado (minúsculas, espacios simples).
final Map<String, DeckCatalogEntry> kDeckCatalogByName = {
  for (final e in kDeckCatalog) e.name.toLowerCase(): e,
};
