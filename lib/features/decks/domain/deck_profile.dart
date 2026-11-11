import '../../../core/db/enums.dart';
import 'deck_matchups.dart';

/// Una partida en la que se jugó el mazo, vista desde el lado del mazo.
/// En un espejo hay dos filas (una por cada piloto).
class DeckGameRow {
  const DeckGameRow({
    required this.tournamentId,
    required this.tournamentName,
    required this.date,
    required this.round,
    required this.isTopCut,
    required this.playerId,
    required this.playerName,
    required this.opponentId,
    required this.opponentName,
    required this.opponentDeckId,
    required this.opponentDeckName,
    required this.outcome,
  });

  final String tournamentId;
  final String tournamentName;
  final DateTime date;
  final int round;
  final bool isTopCut;
  final String playerId;
  final String playerName;
  final String opponentId;
  final String opponentName;
  final String? opponentDeckId;
  final String? opponentDeckName;

  /// 'W', 'L' o 'D' para el piloto del mazo.
  final String outcome;

  bool isMirror(String deckId) => opponentDeckId == deckId;

  /// Resultado desde el lado del jugador 1 o 2 del match.
  static String outcomeFor(MatchResult r, {required bool asPlayer1}) => switch (r) {
        MatchResult.p1Win => asPlayer1 ? 'W' : 'L',
        MatchResult.p2Win => asPlayer1 ? 'L' : 'W',
        MatchResult.draw => 'D',
        // Doble derrota: derrota para los dos.
        _ => 'L',
      };
}

/// Récord V-D-E.
class Record3 {
  int wins = 0;
  int losses = 0;
  int draws = 0;

  int get played => wins + losses + draws;
  double get winrate => played == 0 ? 0 : wins / played;

  void add(String outcome) {
    switch (outcome) {
      case 'W':
        wins++;
      case 'L':
        losses++;
      default:
        draws++;
    }
  }

  @override
  String toString() => '$wins-$losses-$draws';
}

/// Cómo le fue a un jugador con el mazo.
class DeckPilot {
  DeckPilot(this.playerId, this.name);

  final String playerId;
  final String name;
  final Record3 record = Record3();
  final Set<String> tournaments = {};
  int tops = 0;
  int titles = 0;
  int? bestPosition;
}

/// Un rival (jugador) que se enfrentó al mazo: récord desde el mazo.
class DeckOpponent {
  DeckOpponent(this.playerId, this.name);

  final String playerId;
  final String name;
  final Record3 record = Record3();
}

/// Inscripción con el mazo (para tops, títulos y mejor puesto).
class DeckEntryResult {
  const DeckEntryResult({
    required this.tournamentId,
    required this.playerId,
    required this.playerName,
    required this.finalPosition,
    required this.madeTop,
  });

  final String tournamentId;
  final String playerId;
  final String playerName;
  final int? finalPosition;
  final bool madeTop;
}

/// Ficha completa de un mazo (como la de un jugador). Dart puro.
class DeckProfile {
  DeckProfile._({
    required this.deckId,
    required this.games,
    required this.total,
    required this.swiss,
    required this.topCut,
    required this.mirrors,
    required this.pilots,
    required this.opponents,
    required this.vsDecks,
    required this.vsDeckNames,
  });

  /// Partidas mínimas para el mejor y el peor piloto.
  static const minGames = 3;

  final String deckId;

  /// Partidas del mazo (del más reciente al más antiguo).
  final List<DeckGameRow> games;

  /// Récord sin contar los espejos.
  final Record3 total;
  final Record3 swiss;
  final Record3 topCut;

  /// Partidas contra el mismo mazo.
  final int mirrors;

  /// Pilotos (más partidas primero).
  final List<DeckPilot> pilots;

  /// Jugadores que se enfrentaron al mazo (más partidas primero).
  final List<DeckOpponent> opponents;

  /// Récord contra cada mazo (sin espejos), más partidas primero.
  final List<(String, MatchupRecord)> vsDecks;
  final Map<String, String> vsDeckNames;

  int get tournaments => {for (final p in pilots) ...p.tournaments}.length;
  int get tops => pilots.fold(0, (s, p) => s + p.tops);
  int get titles => pilots.fold(0, (s, p) => s + p.titles);

  /// Pilotos que cuentan para mejor/peor (con [minGames] partidas o, si
  /// nadie llega, todos los que jugaron).
  List<DeckPilot> get _ranked {
    final played = pilots.where((p) => p.record.played > 0).toList();
    final enough = played.where((p) => p.record.played >= minGames).toList();
    return enough.isNotEmpty ? enough : played;
  }

  /// Piloto con mejor % de victorias con el mazo (a igualdad, más partidas).
  DeckPilot? get bestPilot {
    final list = _ranked;
    if (list.isEmpty) return null;
    list.sort((a, b) {
      final c = b.record.winrate.compareTo(a.record.winrate);
      return c != 0 ? c : b.record.played.compareTo(a.record.played);
    });
    return list.first;
  }

  /// Piloto con peor % de victorias (si hay más de uno).
  DeckPilot? get worstPilot {
    final list = _ranked;
    if (list.length < 2) return null;
    list.sort((a, b) {
      final c = a.record.winrate.compareTo(b.record.winrate);
      return c != 0 ? c : b.record.played.compareTo(a.record.played);
    });
    return list.first.playerId == bestPilot?.playerId ? null : list.first;
  }

  /// Mazo contra el que mejor / peor le va (mínimo [minGames] partidas).
  (String, MatchupRecord)? get bestMatchup => _matchup(best: true);
  (String, MatchupRecord)? get worstMatchup => _matchup(best: false);

  (String, MatchupRecord)? _matchup({required bool best}) {
    final list = vsDecks.where((e) => e.$2.played >= minGames).toList();
    if (list.isEmpty) return null;
    list.sort((a, b) {
      final c = best ? b.$2.winrate.compareTo(a.$2.winrate) : a.$2.winrate.compareTo(b.$2.winrate);
      return c != 0 ? c : b.$2.played.compareTo(a.$2.played);
    });
    return list.first;
  }

  factory DeckProfile.compute({
    required String deckId,
    required List<DeckGameRow> games,
    required List<DeckEntryResult> entries,
  }) {
    final total = Record3(), swiss = Record3(), top = Record3();
    var mirrorRows = 0;
    final pilots = <String, DeckPilot>{};
    final opponents = <String, DeckOpponent>{};
    final vs = <String, MatchupRecord>{};
    final vsNames = <String, String>{};

    for (final e in entries) {
      final p = pilots[e.playerId] ??= DeckPilot(e.playerId, e.playerName);
      p.tournaments.add(e.tournamentId);
      if (e.madeTop) p.tops++;
      final pos = e.finalPosition;
      if (pos == 1) p.titles++;
      if (pos != null && (p.bestPosition == null || pos < p.bestPosition!)) p.bestPosition = pos;
    }

    for (final g in games) {
      final p = pilots[g.playerId] ??= DeckPilot(g.playerId, g.playerName);
      p.record.add(g.outcome);
      p.tournaments.add(g.tournamentId);
      if (g.isMirror(deckId)) {
        mirrorRows++;
        continue;
      }
      total.add(g.outcome);
      (g.isTopCut ? top : swiss).add(g.outcome);
      (opponents[g.opponentId] ??= DeckOpponent(g.opponentId, g.opponentName)).record.add(g.outcome);
      final od = g.opponentDeckId;
      if (od != null) {
        final r = vs[od] ??= MatchupRecord();
        switch (g.outcome) {
          case 'W':
            r.wins++;
          case 'L':
            r.losses++;
          default:
            r.draws++;
        }
        vsNames[od] = g.opponentDeckName ?? 'Otro mazo';
      }
    }

    int byPlayed(Record3 a, Record3 b) => b.played.compareTo(a.played);
    return DeckProfile._(
      deckId: deckId,
      games: [...games]..sort((a, b) {
          final c = b.date.compareTo(a.date);
          return c != 0 ? c : b.round.compareTo(a.round);
        }),
      total: total,
      swiss: swiss,
      topCut: top,
      mirrors: mirrorRows ~/ 2,
      pilots: pilots.values.toList()..sort((a, b) => byPlayed(a.record, b.record)),
      opponents: opponents.values.toList()..sort((a, b) => byPlayed(a.record, b.record)),
      vsDecks: vs.entries.map((e) => (e.key, e.value)).toList()
        ..sort((a, b) => b.$2.played.compareTo(a.$2.played)),
      vsDeckNames: vsNames,
    );
  }
}
