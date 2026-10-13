import '../../../core/db/enums.dart';
import 'deck_stats.dart';

/// Resultado de un mazo contra otro (desde el mazo de la fila).
class MatchupRecord {
  int wins = 0;
  int losses = 0;
  int draws = 0;

  int get played => wins + losses + draws;

  /// Victorias ÷ partidas (los empates cuentan como partida no ganada).
  double get winrate => played == 0 ? 0 : wins / played;

  @override
  String toString() => draws == 0 ? '$wins-$losses' : '$wins-$losses-$draws';
}

/// Matriz de enfrentamientos mazo contra mazo. Dart puro.
///
/// `table[a][b]` = cómo le fue al mazo `a` contra el mazo `b`. Los espejos
/// (`a == b`) se cuentan una vez, desde el jugador 1. Partidas con un mazo
/// sin asignar se ignoran. Doble derrota = derrota para los dos.
class DeckMatchups {
  DeckMatchups._(this.table);

  final Map<String, Map<String, MatchupRecord>> table;

  factory DeckMatchups.compute(Iterable<DeckMatchRow> matches) {
    final t = <String, Map<String, MatchupRecord>>{};
    MatchupRecord cell(String a, String b) => (t[a] ??= {})[b] ??= MatchupRecord();
    for (final m in matches) {
      final d1 = m.deck1Id, d2 = m.deck2Id;
      if (d1 == null || d2 == null || !m.result.isReported) continue;
      final a = cell(d1, d2);
      final b = d1 == d2 ? null : cell(d2, d1);
      switch (m.result) {
        case MatchResult.p1Win:
          a.wins++;
          b?.losses++;
        case MatchResult.p2Win:
          a.losses++;
          b?.wins++;
        case MatchResult.draw:
          a.draws++;
          b?.draws++;
        case MatchResult.doubleLoss:
          a.losses++;
          b?.losses++;
        case MatchResult.pending:
          break;
      }
    }
    return DeckMatchups._(t);
  }

  MatchupRecord? of(String deck, String against) => table[deck]?[against];

  /// Enfrentamientos de [deck] ordenados por partidas jugadas (más primero).
  List<(String, MatchupRecord)> rowOf(String deck) {
    final row = table[deck];
    if (row == null) return const [];
    return row.entries.map((e) => (e.key, e.value)).toList()
      ..sort((x, y) => y.$2.played.compareTo(x.$2.played));
  }
}

/// Una inscripción con el mazo en un torneo de la temporada (ficha del mazo).
class DeckTournamentEntry {
  const DeckTournamentEntry({
    required this.tournamentId,
    required this.tournamentName,
    required this.date,
    required this.playerId,
    required this.playerName,
    required this.topCutSize,
    this.finalPosition,
  });

  final String tournamentId;
  final String tournamentName;
  final DateTime date;
  final String playerId;
  final String playerName;
  final int topCutSize;
  final int? finalPosition;

  DeckEntryRow get _row => DeckEntryRow(
        deckId: '',
        deckName: '',
        playerId: playerId,
        topCutSize: topCutSize,
        finalPosition: finalPosition,
      );

  bool get madeTop => _row.madeTop;

  /// Puntos de Power que aportó (0 fuera del Top).
  int get power => _row.placementPoints;
}
