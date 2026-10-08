import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/enums.dart';
import 'package:garaje_tcg/features/decks/domain/deck_stats.dart';

DeckEntryRow _e(String deck, String player, {int top = 4, int? pos}) => DeckEntryRow(
    deckId: deck, deckName: deck.toUpperCase(), playerId: player, topCutSize: top, finalPosition: pos);

DeckMatchRow _m(String d1, String d2, MatchResult r, {bool top = false}) =>
    DeckMatchRow(deck1Id: d1, deck2Id: d2, result: r, isTopCut: top);

void main() {
  test('Fórmula PP, WRp y Score', () {
    final list = DeckStats.compute(
      entries: [_e('x', 'p1', pos: 1), _e('y', 'p2', pos: 2)],
      matches: [
        _m('x', 'y', MatchResult.p1Win), // Swiss: x V, y D
        _m('x', 'y', MatchResult.draw), // Swiss: E para ambos
        _m('x', 'y', MatchResult.p1Win, top: true), // Final: x V top
      ],
    );
    final x = list.firstWhere((d) => d.deckId == 'x');
    // PP = 3·1 + 1·1 + 6·1 + 3·1 (entrada top) + 5·1 (título) = 18
    expect(x.performancePoints, 18);
    // WRp = (1 + 2·1 + 0.5·1 + 5) / (2 + 2·1 + 10) = 8.5 / 14
    expect(x.weightedWinrate, closeTo(8.5 / 14, 1e-9));
    expect(x.score, closeTo(18 * (0.5 + 8.5 / 14), 1e-9));
    expect(x.rank, 1);
    expect(x.tier, DeckTier.s);

    final y = list.firstWhere((d) => d.deckId == 'y');
    // PP = 0 + 1 + 0 + 3 (entrada top) + 0 = 4
    expect(y.performancePoints, 4);
    expect(y.losses, 2);
    expect(y.bestPosition, 2);
  });

  test('Uso, jugadores distintos y entradas al top', () {
    final list = DeckStats.compute(
      entries: [
        _e('x', 'p1', pos: 3),
        _e('x', 'p2', pos: 9),
        _e('x', 'p1', top: 0, pos: 1), // torneo sin Top: título pero no entrada al Top
      ],
      matches: const [],
    );
    final x = list.single;
    expect(x.entries, 3);
    expect(x.pilots.length, 2);
    expect(x.topEntries, 1);
    expect(x.titles, 1);
    expect(x.bestPosition, 1);
  });

  test('Doble derrota cuenta como derrota para los dos mazos', () {
    final list = DeckStats.compute(
      entries: [_e('x', 'p1'), _e('y', 'p2')],
      matches: [_m('x', 'y', MatchResult.doubleLoss)],
    );
    for (final d in list) {
      expect(d.swissLosses, 1);
      expect(d.performancePoints, 0);
    }
  });

  test('Desempate por títulos y tiers relativos al mejor', () {
    final a = DeckSeasonStats('a', 'A')..titles = 1;
    final b = DeckSeasonStats('b', 'B');
    // a suma 5 PP por el título; b y c empatan en todo y se ordenan por nombre.
    final c = DeckSeasonStats('c', 'C');
    final ranked = DeckStats.rank([b, c, a]);
    expect(ranked.first.deckId, 'a');
    expect(ranked[1].deckId, 'b'); // empate total → por nombre
    expect(DeckStats.tierFor(70, 100), DeckTier.s);
    expect(DeckStats.tierFor(69, 100), DeckTier.a);
    expect(DeckStats.tierFor(45, 100), DeckTier.a);
    expect(DeckStats.tierFor(20, 100), DeckTier.b);
    expect(DeckStats.tierFor(19.9, 100), DeckTier.c);
    expect(DeckStats.tierFor(0, 0), DeckTier.c);
  });
}
