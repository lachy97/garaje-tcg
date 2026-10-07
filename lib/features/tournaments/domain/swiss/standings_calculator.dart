import '../../../../core/db/enums.dart';
import '../models.dart';
import '../tournament_rules.dart';

/// Calcula la tabla de posiciones Swiss.
///
/// Orden: Puntos → OMW% → OOMW% → id (determinista).
/// - Victoria 3 · Empate 1 · Derrota 0. El BYE cuenta como victoria.
/// - El BYE NO cuenta como rival para OMW% (no hay rival).
/// - MWP con piso de 33 %. Los matches pendientes se ignoran.
class StandingsCalculator {
  const StandingsCalculator._();

  static const _eps = 1e-9;

  static List<Standing> compute({
    required List<SwissPlayer> players,
    required Iterable<MatchRecord> matches,
  }) {
    final stats = {for (final p in players) p.id: _Acc(p)};

    for (final m in matches) {
      if (!m.result.isReported) continue;
      final a = stats[m.player1Id];
      if (m.isBye) {
        if (a != null) {
          a.wins++;
          a.byes++;
        }
        continue;
      }
      final b = stats[m.player2Id];
      if (a == null || b == null) continue; // jugador fuera de la lista
      a.opponents.add(b.player.id);
      b.opponents.add(a.player.id);
      switch (m.result) {
        case MatchResult.p1Win:
          a.wins++;
          b.losses++;
        case MatchResult.p2Win:
          b.wins++;
          a.losses++;
        case MatchResult.draw:
          a.draws++;
          b.draws++;
        case MatchResult.pending:
          break;
      }
    }

    // MWP propio
    for (final s in stats.values) {
      final played = s.wins + s.losses + s.draws;
      final raw = played == 0 ? 0.0 : s.points / (TournamentRules.winPoints * played);
      s.mwp = raw < TournamentRules.minMatchWinPct ? TournamentRules.minMatchWinPct : raw;
    }
    // OMW% (promedio del MWP de los rivales)
    for (final s in stats.values) {
      s.omw = _avg(s.opponents.map((id) => stats[id]!.mwp));
    }
    // OOMW% (promedio del OMW% de los rivales)
    for (final s in stats.values) {
      s.oomw = _avg(s.opponents.map((id) => stats[id]!.omw));
    }

    final sorted = stats.values.toList()..sort(_compare);
    return [
      for (var i = 0; i < sorted.length; i++)
        Standing(
          playerId: sorted[i].player.id,
          rank: i + 1,
          points: sorted[i].points,
          wins: sorted[i].wins,
          losses: sorted[i].losses,
          draws: sorted[i].draws,
          byes: sorted[i].byes,
          mwp: sorted[i].mwp,
          omw: sorted[i].omw,
          oomw: sorted[i].oomw,
          dropped: sorted[i].player.dropped,
        ),
    ];
  }

  static int _compare(_Acc a, _Acc b) {
    if (a.points != b.points) return b.points.compareTo(a.points);
    final omw = _cmpDouble(b.omw, a.omw);
    if (omw != 0) return omw;
    final oomw = _cmpDouble(b.oomw, a.oomw);
    if (oomw != 0) return oomw;
    return a.player.id.compareTo(b.player.id);
  }

  static int _cmpDouble(double x, double y) =>
      (x - y).abs() < _eps ? 0 : x.compareTo(y);

  static double _avg(Iterable<double> values) {
    var sum = 0.0;
    var n = 0;
    for (final v in values) {
      sum += v;
      n++;
    }
    return n == 0 ? 0.0 : sum / n;
  }
}

class _Acc {
  _Acc(this.player);

  final SwissPlayer player;
  int wins = 0;
  int losses = 0;
  int draws = 0;
  int byes = 0;
  final List<String> opponents = [];
  double mwp = 0;
  double omw = 0;
  double oomw = 0;

  int get points =>
      wins * TournamentRules.winPoints + draws * TournamentRules.drawPoints;
}
