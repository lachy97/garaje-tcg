import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/enums.dart';
import 'package:garaje_tcg/features/players/domain/player_profile.dart';
import 'package:garaje_tcg/features/tournaments/domain/models.dart';
import 'package:garaje_tcg/features/tournaments/domain/swiss/standings_calculator.dart';
import 'package:garaje_tcg/features/tournaments/domain/swiss/swiss_pairing_engine.dart';
import 'package:garaje_tcg/features/tournaments/domain/tournament_rules.dart';

void main() {
  const players = [SwissPlayer('a'), SwissPlayer('b'), SwissPlayer('c'), SwissPlayer('d')];

  test('Doble derrota: los dos suman una derrota y 0 puntos', () {
    final ms = [
      const MatchRecord(round: 1, player1Id: 'a', player2Id: 'b', result: MatchResult.doubleLoss,
          games1: 0, gamesDraw: 0, games2: 0),
      const MatchRecord(round: 1, player1Id: 'c', player2Id: 'd', result: MatchResult.p1Win,
          games1: 2, gamesDraw: 0, games2: 0),
    ];
    final s = {for (final x in StandingsCalculator.compute(players: players, matches: ms)) x.playerId: x};
    expect(s['a']!.points, 0);
    expect(s['a']!.losses, 1);
    expect(s['b']!.points, 0);
    expect(s['b']!.losses, 1);
    expect(s['c']!.points, TournamentRules.winPoints);
    expect(s['a']!.wins + s['a']!.draws, 0);
  });

  test('Doble derrota cuenta como reportado y no repite rival', () {
    expect(MatchResult.doubleLoss.isReported, isTrue);
    final engine = SwissPairingEngine();
    final out = engine.pairRound(round: 2, players: players, previous: const [
      MatchRecord(round: 1, player1Id: 'a', player2Id: 'b', result: MatchResult.doubleLoss),
      MatchRecord(round: 1, player1Id: 'c', player2Id: 'd', result: MatchResult.p1Win),
    ]);
    for (final p in out.pairings) {
      final pair = {p.player1Id, p.player2Id};
      expect(pair.containsAll(['a', 'b']), isFalse);
      expect(pair.containsAll(['c', 'd']), isFalse);
    }
    expect(out.rematches, 0);
  });

  test('En el perfil la doble derrota es derrota para ambos', () {
    for (final isP1 in [true, false]) {
      final (o, _) = outcomeFor(
          isPlayer1: isP1, isBye: false, result: MatchResult.doubleLoss,
          games1: 0, gamesDraw: 0, games2: 0);
      expect(o, Outcome.loss);
    }
  });

  test('Tiempo por ronda: 45 min por defecto', () {
    expect(TournamentRules.defaultRoundMinutes, 45);
    expect(TournamentRules.minRoundMinutes, lessThan(45));
    expect(TournamentRules.maxRoundMinutes, greaterThan(45));
  });
}
