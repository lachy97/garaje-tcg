import '../../../core/db/enums.dart';

/// Un match de la temporada visto desde la BD (sin BYE, ya reportado).
class DeckMatchRow {
  const DeckMatchRow({
    required this.deck1Id,
    required this.deck2Id,
    required this.result,
    required this.isTopCut,
  });

  final String? deck1Id;
  final String? deck2Id;
  final MatchResult result;
  final bool isTopCut;
}

/// Una inscripción (jugador + mazo) en un torneo terminado de la temporada.
class DeckEntryRow {
  const DeckEntryRow({
    required this.deckId,
    required this.deckName,
    required this.playerId,
    required this.topCutSize,
    this.finalPosition,
    this.imagePath,
  });

  final String deckId;
  final String deckName;
  final String? imagePath;
  final String playerId;

  /// Top Cut de ese torneo (0 = sin Top).
  final int topCutSize;
  final int? finalPosition;

  /// Hasta qué puesto se considera "Top" en ese torneo: el Top Cut o, si el
  /// torneo no tuvo Top Cut, los 4 primeros.
  int get topLimit => topCutSize > 0 ? topCutSize : 4;

  bool get madeTop => finalPosition != null && finalPosition! <= topLimit;

  /// Puntos de Power por el resultado en el Top (fuera del Top: 0).
  int get placementPoints {
    final pos = finalPosition;
    if (!madeTop || pos == null) return 0;
    if (pos == 1) return 8;
    if (pos == 2) return 6;
    if (pos <= 4) return 4;
    if (pos <= 8) return 2;
    return 1; // Top 16 / Top 32
  }
}

/// [rogue] = mazos que no entraron a ningún Top en la temporada (Power 0).
enum DeckTier { s, a, b, c, rogue }

extension DeckTierLabel on DeckTier {
  String get label => switch (this) {
        DeckTier.s => 'S',
        DeckTier.a => 'A',
        DeckTier.b => 'B',
        DeckTier.c => 'C',
        DeckTier.rogue => 'R',
      };
}

/// Estadísticas de un mazo en la temporada + puntuación para la tier list.
///
/// Fórmula (estilo Konami / comunidad, ver docs/DECISIONES.md):
///   Power      = Σ puntos de cada piloto que entró al Top
///                (Campeón 8 · Finalista 6 · 3º-4º 4 · Top 8 2 · Top 16+ 1)
///   Presencia  = inscripciones con el mazo ÷ inscripciones de la temporada
///   Conversión = entradas al Top ÷ inscripciones con el mazo
///   Tier relativo al mejor Power: S ≥ 70 % · A ≥ 40 % · B ≥ 15 % · C > 0 ·
///   Rogue/Local = sin Top.
///   Orden: Power → Conversión → Presencia → nombre.
class DeckSeasonStats {
  DeckSeasonStats(this.deckId, this.name, {this.imagePath});

  final String deckId;
  final String name;
  final String? imagePath;

  int entries = 0; // inscripciones (veces jugado en un torneo)
  final Set<String> pilots = {};
  int swissWins = 0;
  int swissLosses = 0;
  int swissDraws = 0;
  int topWins = 0;
  int topLosses = 0;
  int topEntries = 0;
  int titles = 0;
  int? bestPosition;

  /// Suma de puntos por resultados en el Top.
  int power = 0;

  /// Fracción del total de inscripciones de la temporada (0-1). Se asigna en
  /// [DeckStats.compute].
  double presence = 0;

  /// Puesto en la tabla (1 = mejor) y tier. Se asignan en [DeckStats.rank].
  int rank = 0;
  DeckTier tier = DeckTier.rogue;

  /// Fracción de pilotos que entraron al Top (0-1).
  double get conversion => entries == 0 ? 0 : topEntries / entries;

  /// Valor que ordena la tier list (= Power).
  double get score => power.toDouble();

  int get swissPlayed => swissWins + swissLosses + swissDraws;
  int get topPlayed => topWins + topLosses;
  int get played => swissPlayed + topPlayed;
  int get wins => swissWins + topWins;
  int get losses => swissLosses + topLosses;

  /// Winrate real (todas las partidas, sin ponderar).
  double get winrate => played == 0 ? 0 : wins / played;
}

class DeckStats {
  const DeckStats._();

  /// Umbrales de tier respecto al mejor Power de la temporada.
  /// S ≥ 70 % · A ≥ 40 % · B ≥ 15 % · C > 0 · Rogue/Local = 0.
  static const tierThresholds = {DeckTier.s: 0.70, DeckTier.a: 0.40, DeckTier.b: 0.15};

  static List<DeckSeasonStats> compute({
    required List<DeckEntryRow> entries,
    required List<DeckMatchRow> matches,
  }) {
    final byId = <String, DeckSeasonStats>{};
    for (final e in entries) {
      final s = byId[e.deckId] ??= DeckSeasonStats(e.deckId, e.deckName, imagePath: e.imagePath);
      s.entries++;
      s.pilots.add(e.playerId);
      if (e.madeTop) s.topEntries++;
      s.power += e.placementPoints;
      final pos = e.finalPosition;
      if (pos != null) {
        if (pos == 1) s.titles++;
        if (s.bestPosition == null || pos < s.bestPosition!) s.bestPosition = pos;
      }
    }

    void win(String? id, bool top) {
      final s = id == null ? null : byId[id];
      if (s == null) return;
      top ? s.topWins++ : s.swissWins++;
    }

    void loss(String? id, bool top) {
      final s = id == null ? null : byId[id];
      if (s == null) return;
      top ? s.topLosses++ : s.swissLosses++;
    }

    void draw(String? id) {
      final s = id == null ? null : byId[id];
      if (s != null) s.swissDraws++;
    }

    for (final m in matches) {
      switch (m.result) {
        case MatchResult.p1Win:
          win(m.deck1Id, m.isTopCut);
          loss(m.deck2Id, m.isTopCut);
        case MatchResult.p2Win:
          win(m.deck2Id, m.isTopCut);
          loss(m.deck1Id, m.isTopCut);
        case MatchResult.draw:
          draw(m.deck1Id);
          draw(m.deck2Id);
        case MatchResult.doubleLoss:
          loss(m.deck1Id, m.isTopCut);
          loss(m.deck2Id, m.isTopCut);
        case MatchResult.pending:
          break;
      }
    }
    final total = entries.length;
    for (final s in byId.values) {
      s.presence = total == 0 ? 0 : s.entries / total;
    }
    return rank(byId.values.toList());
  }

  /// Ordena por Power y desempata: Conversión → Presencia → nombre.
  /// Asigna puesto y tier.
  static List<DeckSeasonStats> rank(List<DeckSeasonStats> list) {
    list.sort((a, b) {
      var c = b.power.compareTo(a.power);
      if (c != 0) return c;
      c = b.conversion.compareTo(a.conversion);
      if (c != 0) return c;
      c = b.presence.compareTo(a.presence);
      if (c != 0) return c;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    final top = list.isEmpty ? 0.0 : list.first.score;
    for (var i = 0; i < list.length; i++) {
      list[i]
        ..rank = i + 1
        ..tier = tierFor(list[i].score, top);
    }
    return list;
  }

  static DeckTier tierFor(double power, double best) {
    if (power <= 0 || best <= 0) return DeckTier.rogue;
    final r = power / best;
    for (final MapEntry(key: tier, value: min) in tierThresholds.entries) {
      if (r >= min) return tier;
    }
    return DeckTier.c;
  }
}
