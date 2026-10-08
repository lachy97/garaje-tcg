import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/enums.dart';
import 'package:garaje_tcg/features/players/domain/player_profile.dart';
import 'package:garaje_tcg/features/tournaments/domain/game_score.dart';

HistoryEntry _h(String t, Outcome o, String deck, {DateTime? date}) => HistoryEntry(
      tournamentId: t,
      tournamentName: 'Torneo $t',
      date: date ?? DateTime(2026, 10, 1),
      phase: RoundPhase.swiss,
      phaseLabel: 'Ronda 1',
      outcome: o,
      ownDeck: deck,
      opponentName: 'Rival',
    );

void main() {
  test('Resultado y marcador desde el punto de vista del jugador', () {
    final (o1, s1) = outcomeFor(
        isPlayer1: true, isBye: false, result: MatchResult.p1Win,
        games1: 2, gamesDraw: 0, games2: 1);
    expect(o1, Outcome.win);
    expect(s1, const GameScore(2, 0, 1));

    final (o2, s2) = outcomeFor(
        isPlayer1: false, isBye: false, result: MatchResult.p1Win,
        games1: 2, gamesDraw: 0, games2: 1);
    expect(o2, Outcome.loss);
    expect(s2, const GameScore(1, 0, 2)); // visto desde el jugador 2

    expect(outcomeFor(isPlayer1: true, isBye: true, result: MatchResult.p1Win).$1, Outcome.bye);
    expect(outcomeFor(isPlayer1: false, isBye: false, result: MatchResult.draw).$1, Outcome.draw);
  });

  test('Nombre de la fase', () {
    expect(phaseLabel(phase: RoundPhase.swiss, roundNumber: 3), 'Ronda 3');
    expect(phaseLabel(phase: RoundPhase.topCut, roundNumber: 5, bracketSize: 8), 'Cuartos');
    expect(phaseLabel(phase: RoundPhase.topCut, roundNumber: 7, bracketSize: 2), 'Final');
    expect(
        phaseLabel(phase: RoundPhase.topCut, roundNumber: 7, bracketSize: 2, isThirdPlace: true),
        '3er puesto');
  });

  test('Mazos usados y totales', () {
    final data = PlayerProfileData(
      history: [
        _h('a', Outcome.win, 'Snake-Eye'),
        _h('a', Outcome.loss, 'Snake-Eye'),
        _h('a', Outcome.bye, 'Snake-Eye'), // el BYE no cuenta como partida
        _h('b', Outcome.draw, 'Yubel', date: DateTime(2026, 10, 8)),
        _h('b', Outcome.win, 'Yubel', date: DateTime(2026, 10, 8)),
      ],
      tournaments: [
        TournamentEntry(tournamentId: 'b', name: 'B', date: DateTime(2026, 10, 8),
            finished: true, deck: 'Yubel', finalPosition: 1),
        TournamentEntry(tournamentId: 'a', name: 'A', date: DateTime(2026, 10, 1),
            finished: true, deck: 'Snake-Eye', finalPosition: 5),
      ],
    );
    expect(data.totals.tournaments, 2);
    expect(data.totals.played, 4);
    expect([data.totals.wins, data.totals.losses, data.totals.draws], [2, 1, 1]);
    expect(data.totals.titles, 1);
    expect(data.totals.bestPosition, 1);

    final snake = data.decks.firstWhere((d) => d.deck == 'Snake-Eye');
    expect(snake.tournaments, 1);
    expect(snake.played, 2);
    expect(snake.winrate, 0.5);
    final yubel = data.decks.firstWhere((d) => d.deck == 'Yubel');
    expect(yubel.lastUsed, DateTime(2026, 10, 8));
    expect(data.historyByTournament.keys.toList(), ['a', 'b']);
  });
}
