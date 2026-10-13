import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/enums.dart';
import 'package:garaje_tcg/features/decks/domain/deck_matchups.dart';
import 'package:garaje_tcg/features/decks/domain/deck_stats.dart';
import 'package:garaje_tcg/features/tournaments/domain/models.dart';
import 'package:garaje_tcg/features/tournaments/domain/swiss/standings_calculator.dart';

void main() {
  test('Inscripción tardía: cada ronda perdida es una derrota 0-2 sin rival', () {
    const players = [SwissPlayer('a'), SwissPlayer('b'), SwissPlayer('late', lateLosses: 1)];
    final ms = [
      const MatchRecord(round: 1, player1Id: 'a', player2Id: 'b', result: MatchResult.p1Win,
          games1: 2, gamesDraw: 0, games2: 0),
      const MatchRecord(round: 2, player1Id: 'late', player2Id: 'a', result: MatchResult.p1Win,
          games1: 2, gamesDraw: 0, games2: 1),
    ];
    final s = {for (final x in StandingsCalculator.compute(players: players, matches: ms)) x.playerId: x};
    expect(s['late']!.wins, 1);
    expect(s['late']!.losses, 1);
    expect(s['late']!.points, 3);
    // MWP del tardío = 3 / (3·2) = 50 %, y la derrota sin rival no cuenta como rival.
    expect(s['late']!.mwp, closeTo(0.5, 1e-9));
    expect(s['late']!.omw, closeTo(s['a']!.mwp, 1e-9));
    // GW%: 2 ganados de 3 + 2 perdidos (0-2) = 2/5 = 40 %.
    expect(s['late']!.gwp, closeTo(0.4, 1e-9));
  });

  test('Matriz de enfrentamientos', () {
    final m = DeckMatchups.compute(const [
      DeckMatchRow(deck1Id: 'bw', deck2Id: 'tw', result: MatchResult.p1Win, isTopCut: false),
      DeckMatchRow(deck1Id: 'tw', deck2Id: 'bw', result: MatchResult.p1Win, isTopCut: true),
      DeckMatchRow(deck1Id: 'bw', deck2Id: 'tw', result: MatchResult.draw, isTopCut: false),
      DeckMatchRow(deck1Id: 'bw', deck2Id: 'bw', result: MatchResult.p2Win, isTopCut: false),
      DeckMatchRow(deck1Id: 'bw', deck2Id: null, result: MatchResult.p1Win, isTopCut: false),
      DeckMatchRow(deck1Id: 'gb', deck2Id: 'tw', result: MatchResult.doubleLoss, isTopCut: false),
    ]);
    expect(m.of('bw', 'tw').toString(), '1-1-1');
    expect(m.of('tw', 'bw').toString(), '1-1-1');
    expect(m.of('bw', 'bw')!.played, 1); // espejo, una sola vez
    expect(m.of('gb', 'tw').toString(), '0-1');
    expect(m.of('tw', 'gb').toString(), '0-1');
    expect(m.rowOf('bw').first.$1, 'tw'); // el más jugado primero
    expect(m.of('bw', 'gb'), isNull);
  });

  test('Power de una inscripción en la ficha del mazo', () {
    DeckTournamentEntry e(int? pos, {int top = 8}) => DeckTournamentEntry(
        tournamentId: 't', tournamentName: 'T', date: DateTime(2026, 10, 4),
        playerId: 'p', playerName: 'P', topCutSize: top, finalPosition: pos);
    expect(e(1).power, 8);
    expect(e(6).power, 2);
    expect(e(9).power, 0);
    expect(e(9).madeTop, isFalse);
    expect(e(3, top: 0).power, 4);
  });
}
