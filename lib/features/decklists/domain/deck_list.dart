import 'card_db.dart';

/// Parte de una lista de mazo.
enum DeckSection {
  main('Main Deck', 'MAIN'),
  extra('Extra Deck', 'EXTRA'),
  side('Side Deck', 'SIDE');

  const DeckSection(this.label, this.short);
  final String label;
  final String short;
}

/// Cartas de una lista: un código por copia, en el orden en que se añadieron.
/// Dart puro.
class DeckCards {
  DeckCards({List<int>? main, List<int>? extra, List<int>? side})
      : main = main ?? [],
        extra = extra ?? [],
        side = side ?? [];

  final List<int> main;
  final List<int> extra;
  final List<int> side;

  List<int> of(DeckSection s) => switch (s) {
        DeckSection.main => main,
        DeckSection.extra => extra,
        DeckSection.side => side,
      };

  bool get isEmpty => main.isEmpty && extra.isEmpty && side.isEmpty;

  int count(DeckSection s, int id) => of(s).where((c) => c == id).length;

  /// Copias de una carta en toda la lista (Main + Extra + Side).
  int total(int id) =>
      count(DeckSection.main, id) + count(DeckSection.extra, id) + count(DeckSection.side, id);

  void add(DeckSection s, int id) => of(s).add(id);

  /// Quita una copia (la última). true si había.
  bool remove(DeckSection s, int id) {
    final list = of(s);
    final i = list.lastIndexOf(id);
    if (i < 0) return false;
    list.removeAt(i);
    return true;
  }

  DeckCards copy() => DeckCards(main: [...main], extra: [...extra], side: [...side]);

  /// Para guardar en la BD: "123,123,456".
  static String joinCodes(List<int> codes) => codes.join(',');

  static List<int> parseCodes(String s) => [
        for (final p in s.split(','))
          if (int.tryParse(p.trim()) case final v?) v,
      ];

  /// Texto .ydk (lo leen YGOPro, EDOPro, etc.).
  String toYdk() => [
        '#created by Garage TCG',
        '#main',
        ...main.map((c) => '$c'),
        '#extra',
        ...extra.map((c) => '$c'),
        '!side',
        ...side.map((c) => '$c'),
        '',
      ].join('\n');
}

/// Resultado de leer un .ydk.
class YdkResult {
  const YdkResult(this.cards, this.unknown);
  final DeckCards cards;

  /// Códigos que no están en la base de Edison (no se añaden).
  final List<int> unknown;
}

/// Lee un archivo .ydk: secciones "#main", "#extra" y "!side", un código por
/// línea. Las ilustraciones alternativas se convierten al código principal.
YdkResult parseYdk(String text, CardDb db) {
  final cards = DeckCards();
  final unknown = <int>[];
  var section = DeckSection.main;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();
    if (lower.startsWith('#main')) {
      section = DeckSection.main;
    } else if (lower.startsWith('#extra')) {
      section = DeckSection.extra;
    } else if (lower.startsWith('!side')) {
      section = DeckSection.side;
    } else if (line.startsWith('#') || line.startsWith('!')) {
      continue; // comentario ("#created by …")
    } else if (int.tryParse(line.split(RegExp(r'\s')).first) case final code?) {
      final card = db.byId(code);
      if (card == null) {
        unknown.add(code);
      } else {
        cards.add(section, card.id);
      }
    }
  }
  return YdkResult(cards, unknown);
}

/// Avisos de una lista (no impiden guardarla).
List<String> validateDeck(DeckCards d, CardDb db) {
  final out = <String>[];
  if (d.main.length < 40) out.add('El Main tiene ${d.main.length} cartas (mínimo 40).');
  if (d.main.length > 60) out.add('El Main tiene ${d.main.length} cartas (máximo 60).');
  if (d.extra.length > 15) out.add('El Extra tiene ${d.extra.length} cartas (máximo 15).');
  if (d.side.length > 15) out.add('El Side tiene ${d.side.length} cartas (máximo 15).');

  final ids = {...d.main, ...d.extra, ...d.side};
  final named = [for (final id in ids) if (db.byId(id) case final c?) c]
    ..sort((a, b) => a.name.compareTo(b.name));
  for (final c in named) {
    final n = d.total(c.id);
    if (c.limit == 0) {
      out.add('${c.name} está prohibida en Edison.');
    } else if (c.limit < 3 && n > c.limit) {
      final kind = c.limit == 1 ? 'limitada (1 copia)' : 'semilimitada (2 copias)';
      out.add('${c.name}: $n copias, está $kind.');
    } else if (n > 3) {
      out.add('${c.name}: $n copias (máximo 3).');
    }
    if (c.isExtra && d.count(DeckSection.main, c.id) > 0) {
      out.add('${c.name} es del Extra Deck y está en el Main.');
    }
    if (!c.isExtra && d.count(DeckSection.extra, c.id) > 0) {
      out.add('${c.name} no es del Extra Deck y está en el Extra.');
    }
  }
  return out;
}

/// Cartas de una sección agrupadas (carta, copias), en el orden de la imagen:
/// monstruos, mágicas, trampas (Extra: fusión, sincronía…) y por nombre.
List<(YgoCard, int)> groupedSection(DeckCards d, DeckSection s, CardDb db) {
  final counts = <int, int>{};
  for (final id in d.of(s)) {
    counts[id] = (counts[id] ?? 0) + 1;
  }
  final out = [
    for (final MapEntry(:key, :value) in counts.entries)
      (db.byId(key) ?? YgoCard(id: key, name: '#$key', frame: ''), value),
  ]..sort((a, b) {
      final g = a.$1.group.index.compareTo(b.$1.group.index);
      if (g != 0) return g;
      if (s == DeckSection.extra) {
        final f = a.$1.frame.compareTo(b.$1.frame);
        if (f != 0) return f;
      }
      return a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase());
    });
  return out;
}
