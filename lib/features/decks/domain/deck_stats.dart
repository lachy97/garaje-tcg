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
  });

  final String deckId;
  final String deckName;
  final String playerId;

  /// Top Cut de ese torneo (0 = sin Top).
  final int topCutSize;
  final int? finalPosition;

  bool get madeTop => topCutSize > 0 && finalPosition != null && finalPosition! <= topCutSize;
}

enum DeckTier { s, a, b, c }

extension DeckTierLabel on DeckTier {
  String get label => switch (this) {
        DeckTier.s => 'S',
        DeckTier.a => 'A',
        DeckTier.b => 'B',
        DeckTier.c => 'C',
      };
}

/// Estadísticas de un mazo en la temporada + puntuación para la tier list.
///
/// Fórmula (ver docs/DECISIONES.md):
///   PP    = 3·V_swiss + 1·E_swiss + 6·V_top + 3·Entradas_top + 5·Títulos
///   WRp   = (V_swiss + 2·V_top + 0.5·E + 5) / (PJ_swiss + 2·PJ_top + 10)
///   Score = PP × (0.5 + WRp)
///
/// PP premia rendimiento acumulado (uso + resultados); WRp es un winrate
/// "suavizado" (5 de 10 ficticios) para que un mazo con 1 partida ganada no
/// aparezca arriba, y donde una victoria en el Top vale doble.
class DeckSeasonStats {
  DeckSeasonStats(this.deckId, this.name);

  final String deckId;
  final String name;

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

  /// Puesto en la tabla (1 = mejor) y tier. Se asignan en [DeckStats.rank].
  int rank = 0;
  DeckTier tier = DeckTier.c;

  int get swissPlayed => swissWins + swissLosses + swissDraws;
  int get topPlayed => topWins + topLosses;
  int get played => swissPlayed + topPlayed;
  int get wins => swissWins + topWins;
  int get losses => swissLosses + topLosses;

  /// Winrate real (todas las partidas, sin ponderar).
  double get winrate => played == 0 ? 0 : wins / played;

  int get performancePoints =>
      3 * swissWins + swissDraws + 6 * topWins + 3 * topEntries + 5 * titles;

  double get weightedWinrate =>
      (swissWins + 2 * topWins + 0.5 * swissDraws + 5) / (swissPlayed + 2 * topPlayed + 10);

  double get score => performancePoints * (0.5 + weightedWinrate);
}

class DeckStats {
  const DeckStats._();

  /// Umbrales de tier respecto al mejor Score de la temporada.
  /// S ≥ 70 % · A ≥ 45 % · B ≥ 20 % · C resto.
  static const tierThresholds = {DeckTier.s: 0.70, DeckTier.a: 0.45, DeckTier.b: 0.20};

  static List<DeckSeasonStats> compute({
    required List<DeckEntryRow> entries,
    required List<DeckMatchRow> matches,
  }) {
    final byId = <String, DeckSeasonStats>{};
    for (final e in entries) {
      final s = byId[e.deckId] ??= DeckSeasonStats(e.deckId, e.deckName);
      s.entries++;
      s.pilots.add(e.playerId);
      if (e.madeTop) s.topEntries++;
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
    return rank(byId.values.toList());
  }

  /// Ordena por Score y desempata: títulos → V top → WRp → mejor resultado → nombre.
  /// Asigna puesto y tier.
  static List<DeckSeasonStats> rank(List<DeckSeasonStats> list) {
    list.sort((a, b) {
      var c = b.score.compareTo(a.score);
      if (c != 0) return c;
      c = b.titles.compareTo(a.titles);
      if (c != 0) return c;
      c = b.topWins.compareTo(a.topWins);
      if (c != 0) return c;
      c = b.weightedWinrate.compareTo(a.weightedWinrate);
      if (c != 0) return c;
      c = (a.bestPosition ?? 1 << 30).compareTo(b.bestPosition ?? 1 << 30);
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

  static DeckTier tierFor(double score, double best) {
    if (best <= 0) return DeckTier.c;
    final r = score / best;
    for (final MapEntry(key: tier, value: min) in tierThresholds.entries) {
      if (r >= min) return tier;
    }
    return DeckTier.c;
  }
}
