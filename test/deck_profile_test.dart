import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/features/decks/domain/deck_profile.dart';

DeckGameRow g(String player, String opp, String? oppDeck, String outcome,
        {String t = 't1', int round = 1, bool top = false}) =>
    DeckGameRow(
      tournamentId: t,
      tournamentName: t,
      date: DateTime(2026, 11, 1),
      round: round,
      isTopCut: top,
      playerId: player,
      playerName: player,
      opponentId: opp,
      opponentName: opp,
      opponentDeckId: oppDeck,
      opponentDeckName: oppDeck,
      outcome: outcome,
    );

void main() {
  test('totales sin espejos, pilotos con espejos, mejor y peor', () {
    final p = DeckProfile.compute(
      deckId: 'goat',
      games: [
        // Ana: 3-0 con el mazo
        g('ana', 'x', 'chaos', 'W'),
        g('ana', 'y', 'chaos', 'W', round: 2),
        g('ana', 'z', 'warrior', 'W', round: 3, top: true),
        // Beto: 1-2
        g('beto', 'x', 'chaos', 'L'),
        g('beto', 'y', 'warrior', 'L', round: 2),
        g('beto', 'z', 'warrior', 'W', round: 3),
        // Espejo Ana vs Beto (dos filas)
        g('ana', 'beto', 'goat', 'W', round: 4),
        g('beto', 'ana', 'goat', 'L', round: 4),
        // Caro: 1 partida (no llega al mínimo)
        g('caro', 'x', 'chaos', 'D'),
      ],
      entries: const [
        DeckEntryResult(tournamentId: 't1', playerId: 'ana', playerName: 'ana', finalPosition: 1, madeTop: true),
        DeckEntryResult(tournamentId: 't1', playerId: 'beto', playerName: 'beto', finalPosition: 9, madeTop: false),
      ],
    );
    expect(p.total.played, 7); // sin el espejo
    expect(p.total.wins, 4);
    expect(p.total.losses, 2);
    expect(p.total.draws, 1);
    expect(p.mirrors, 1);
    expect(p.topCut.played, 1);
    expect(p.titles, 1);
    expect(p.tops, 1);
    expect(p.bestPilot!.playerId, 'ana'); // 4-0
    expect(p.worstPilot!.playerId, 'beto'); // 1-3
    final chaos = p.vsDecks.firstWhere((e) => e.$1 == 'chaos').$2;
    expect('${chaos.wins}-${chaos.losses}-${chaos.draws}', '2-1-1');
    expect(p.bestMatchup!.$1, 'warrior'); // 2-1 · 67 %
    expect(p.worstMatchup!.$1, 'chaos'); // 2-1-1 · 50 %
  });

  test('sin partidas', () {
    final p = DeckProfile.compute(deckId: 'd', games: const [], entries: const []);
    expect(p.bestPilot, isNull);
    expect(p.worstPilot, isNull);
    expect(p.total.played, 0);
  });
}
