import 'dart:convert';

/// Grupo de una carta dentro de una lista (orden de la imagen exportada).
enum CardGroup { monster, spell, trap, extra }

/// Una carta de la base de Edison Format (nombre en inglés, de YGOPRODeck).
class YgoCard {
  const YgoCard({
    required this.id,
    required this.name,
    required this.frame,
    this.limit = 3,
    this.altIds = const [],
  });

  /// Código (passcode) principal; también es el nombre de su imagen.
  final int id;
  final String name;

  /// frameType de YGOPRODeck: normal, effect, ritual, fusion, synchro,
  /// spell, trap…
  final String frame;

  /// Copias permitidas por la banlist de Edison (0 = prohibida).
  final int limit;

  /// Códigos de las ilustraciones alternativas (un .ydk puede traer cualquiera).
  final List<int> altIds;

  bool get isExtra => const {'fusion', 'synchro', 'xyz', 'link'}.contains(frame);

  CardGroup get group => switch (frame) {
        'spell' => CardGroup.spell,
        'trap' => CardGroup.trap,
        _ when isExtra => CardGroup.extra,
        _ => CardGroup.monster,
      };

  factory YgoCard.fromJson(Map<String, dynamic> j) => YgoCard(
        id: j['i'] as int,
        name: j['n'] as String,
        frame: j['f'] as String? ?? '',
        limit: j['l'] as int? ?? 3,
        altIds: [for (final a in (j['a'] as List? ?? const [])) a as int],
      );

  @override
  String toString() => '$name ($id)';
}

/// Base de cartas de Edison Format empaquetada en la app
/// (assets/cards/edison_cards.json, generada con tools/cards/build_card_db.py).
/// Dart puro: búsquedas por código, por nombre y buscador.
class CardDb {
  CardDb(List<YgoCard> cards, {this.version = ''})
      : cards = List.unmodifiable(cards),
        _keys = List.unmodifiable(cards.map((c) => normalize(c.name))) {
    for (final c in this.cards) {
      _byId[c.id] = c;
      for (final a in c.altIds) {
        _byId.putIfAbsent(a, () => c);
      }
      _byName[normalize(c.name)] = c;
    }
  }

  factory CardDb.fromJsonString(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    return CardDb(
      [for (final c in (j['cards'] as List? ?? const [])) YgoCard.fromJson(c as Map<String, dynamic>)],
      version: j['version'] as String? ?? '',
    );
  }

  static final empty = CardDb(const []);

  /// Fecha en que se generó la base (vacía si aún es el marcador de posición).
  final String version;
  final List<YgoCard> cards;
  final List<String> _keys; // nombre normalizado de cada carta (mismo orden)
  final _byId = <int, YgoCard>{};
  final _byName = <String, YgoCard>{};

  bool get isEmpty => cards.isEmpty;
  int get length => cards.length;

  static const _accents = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n',
  };
  static final _notAlnum = RegExp(r'[^\p{L}\p{N}]', unicode: true);

  /// Clave de comparación de nombres: minúsculas, sin tildes, sin espacios
  /// ni signos ("Gravekeeper's Spy" = "gravekeepers spy" = "GRAVEKEEPERS-SPY").
  static String normalize(String name) {
    final lower = name.toLowerCase();
    final sb = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      sb.write(_accents[ch] ?? ch);
    }
    return sb.toString().replaceAll(_notAlnum, '');
  }

  /// Carta por código, también por el de una ilustración alternativa.
  YgoCard? byId(int id) => _byId[id];

  /// Carta por nombre exacto (sin importar mayúsculas, tildes ni signos).
  YgoCard? byName(String name) {
    final key = normalize(name);
    return key.isEmpty ? null : _byName[key];
  }

  /// Buscador: todas las palabras deben aparecer en el nombre. Primero el
  /// nombre exacto, luego los que empiezan por la búsqueda, luego el resto
  /// (alfabético dentro de cada grupo).
  List<YgoCard> search(String query, {int limit = 30}) {
    final words = query
        .split(RegExp(r'\s+'))
        .map(normalize)
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];
    final whole = normalize(query);
    final exact = <YgoCard>[], prefix = <YgoCard>[], rest = <YgoCard>[];
    for (var i = 0; i < cards.length; i++) {
      final c = cards[i], key = _keys[i];
      if (!words.every(key.contains)) continue;
      if (key == whole) {
        exact.add(c);
      } else if (key.startsWith(whole)) {
        prefix.add(c);
      } else {
        rest.add(c);
      }
    }
    return [...exact, ...prefix, ...rest].take(limit).toList();
  }
}
