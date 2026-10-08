import '../../../core/db/enums.dart';
import '../../tournaments/domain/game_score.dart';

/// Resultado de un match visto desde el jugador del perfil.
enum Outcome { win, loss, draw, pending, bye }

/// Un match del historial del jugador.
class HistoryEntry {
  const HistoryEntry({
    required this.tournamentId,
    required this.tournamentName,
    required this.date,
    required this.phase,
    required this.phaseLabel,
    required this.outcome,
    this.ownDeck,
    this.opponentName,
    this.opponentDeck,
    this.score,
  });

  final String tournamentId;
  final String tournamentName;
  final DateTime date;
  final RoundPhase phase;

  /// "Ronda 2", "Cuartos", "Semis", "Final", "3er puesto"...
  final String phaseLabel;
  final Outcome outcome;
  final String? ownDeck;
  final String? opponentName; // null = BYE
  final String? opponentDeck;

  /// Marcador desde el punto de vista del jugador (propios - empates - rival).
  final GameScore? score;

  bool get counts => outcome == Outcome.win || outcome == Outcome.loss || outcome == Outcome.draw;
}

/// Participación del jugador en un torneo.
class TournamentEntry {
  const TournamentEntry({
    required this.tournamentId,
    required this.name,
    required this.date,
    required this.finished,
    this.deck,
    this.finalPosition,
    this.dropped = false,
  });

  final String tournamentId;
  final String name;
  final DateTime date;
  final bool finished;
  final String? deck;
  final int? finalPosition;
  final bool dropped;
}

/// Estadísticas del jugador con un mazo concreto.
class DeckUsage {
  DeckUsage(this.deck);

  final String deck;
  int tournaments = 0;
  int wins = 0;
  int losses = 0;
  int draws = 0;
  DateTime? lastUsed;

  int get played => wins + losses + draws;
  double get winrate => played == 0 ? 0 : wins / played;
}

class ProfileTotals {
  const ProfileTotals({
    required this.tournaments,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.titles,
    this.bestPosition,
  });

  final int tournaments;
  final int wins;
  final int losses;
  final int draws;
  final int titles;
  final int? bestPosition;

  int get played => wins + losses + draws;
  double get winrate => played == 0 ? 0 : wins / played;
}

/// Todo lo que muestra el perfil. Se construye en Dart puro a partir de las
/// filas de la BD (ver PlayerProfileRepository) para poder testearlo.
class PlayerProfileData {
  PlayerProfileData({required this.history, required this.tournaments})
      : decks = _decks(history, tournaments),
        totals = _totals(history, tournaments);

  /// Más reciente primero.
  final List<HistoryEntry> history;

  /// Más reciente primero.
  final List<TournamentEntry> tournaments;
  final List<DeckUsage> decks;
  final ProfileTotals totals;

  /// Historial agrupado por torneo, en el orden de [history].
  Map<String, List<HistoryEntry>> get historyByTournament {
    final map = <String, List<HistoryEntry>>{};
    for (final h in history) {
      (map[h.tournamentId] ??= []).add(h);
    }
    return map;
  }

  static List<DeckUsage> _decks(List<HistoryEntry> history, List<TournamentEntry> tournaments) {
    final byDeck = <String, DeckUsage>{};
    DeckUsage get(String d) => byDeck[d] ??= DeckUsage(d);

    for (final t in tournaments) {
      if (t.deck == null) continue;
      final u = get(t.deck!)..tournaments += 1;
      if (u.lastUsed == null || t.date.isAfter(u.lastUsed!)) u.lastUsed = t.date;
    }
    for (final h in history) {
      if (h.ownDeck == null || !h.counts) continue;
      final u = get(h.ownDeck!);
      switch (h.outcome) {
        case Outcome.win:
          u.wins++;
        case Outcome.loss:
          u.losses++;
        case Outcome.draw:
          u.draws++;
        case Outcome.pending:
        case Outcome.bye:
          break;
      }
      if (u.lastUsed == null || h.date.isAfter(u.lastUsed!)) u.lastUsed = h.date;
    }
    final list = byDeck.values.toList()
      ..sort((a, b) {
        final c = b.tournaments.compareTo(a.tournaments);
        if (c != 0) return c;
        final p = b.played.compareTo(a.played);
        return p != 0 ? p : a.deck.toLowerCase().compareTo(b.deck.toLowerCase());
      });
    return list;
  }

  static ProfileTotals _totals(List<HistoryEntry> history, List<TournamentEntry> tournaments) {
    var w = 0, l = 0, d = 0;
    for (final h in history) {
      switch (h.outcome) {
        case Outcome.win:
          w++;
        case Outcome.loss:
          l++;
        case Outcome.draw:
          d++;
        case Outcome.pending:
        case Outcome.bye:
          break;
      }
    }
    final positions = [
      for (final t in tournaments)
        if (t.finished && t.finalPosition != null) t.finalPosition!,
    ];
    return ProfileTotals(
      tournaments: tournaments.length,
      wins: w,
      losses: l,
      draws: d,
      titles: positions.where((p) => p == 1).length,
      bestPosition: positions.isEmpty ? null : positions.reduce((a, b) => a < b ? a : b),
    );
  }
}

/// Nombre de la fase en que se jugó un match.
String phaseLabel({
  required RoundPhase phase,
  required int roundNumber,
  int? bracketSize,
  bool isThirdPlace = false,
}) {
  if (phase == RoundPhase.swiss) return 'Ronda $roundNumber';
  if (isThirdPlace) return '3er puesto';
  return switch (bracketSize) {
    2 => 'Final',
    4 => 'Semifinal',
    8 => 'Cuartos',
    final n? => 'Top $n',
    null => 'Top Cut',
  };
}

/// Resultado y marcador desde el punto de vista del jugador.
(Outcome, GameScore?) outcomeFor({
  required bool isPlayer1,
  required bool isBye,
  required MatchResult result,
  int? games1,
  int? gamesDraw,
  int? games2,
}) {
  if (isBye) return (Outcome.bye, GameScore.bye);
  final raw = games1 == null ? null : GameScore(games1, gamesDraw ?? 0, games2 ?? 0);
  final score = raw == null ? null : (isPlayer1 ? raw : raw.swapped);
  final outcome = switch (result) {
    MatchResult.pending => Outcome.pending,
    MatchResult.draw => Outcome.draw,
    MatchResult.doubleLoss => Outcome.loss,
    MatchResult.p1Win => isPlayer1 ? Outcome.win : Outcome.loss,
    MatchResult.p2Win => isPlayer1 ? Outcome.loss : Outcome.win,
  };
  return (outcome, score);
}
