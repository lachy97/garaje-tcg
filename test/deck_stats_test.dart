import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/enums.dart';
import 'package:garaje_tcg/features/decks/domain/deck_stats.dart';

DeckEntryRow _e(String deck, String player, {int top = 16, int? pos}) => DeckEntryRow(
    deckId: deck, deckName: deck.toUpperCase(), playerId: player, topCutSize: top, finalPosition: pos);

DeckMatchRow _m(String d1, String d2, MatchResult r, {bool top = false}) =>
    DeckMatchRow(deck1Id: d1, deck2Id: d2, result: r, isTopCut: top);

void main() {
  test('Puntos de Power por resultado en el Top', () {
    expect(_e('x', 'p', pos: 1).placementPoints, 8);
    expect(_e('x', 'p', pos: 2).placementPoints, 6);
    expect(_e('x', 'p', pos: 3).placementPoints, 4);
    expect(_e('x', 'p', pos: 4).placementPoints, 4);
    expect(_e('x', 'p', pos: 5).placementPoints, 2);
    expect(_e('x', 'p', pos: 8).placementPoints, 2);
    expect(_e('x', 'p', pos: 9).placementPoints, 1);
    expect(_e('x', 'p', pos: 16).placementPoints, 1);
    expect(_e('x', 'p', pos: 17).placementPoints, 0); // fuera del Top 16
    expect(_e('x', 'p', top: 8, pos: 9).placementPoints, 0); // fuera del Top 8
    // Sin Top Cut: cuentan los 4 primeros
    expect(_e('x', 'p', top: 0, pos: 1).placementPoints, 8);
    expect(_e('x', 'p', top: 0, pos: 4).placementPoints, 4);
    expect(_e('x', 'p', top: 0, pos: 5).placementPoints, 0);
    expect(_e('x', 'p').placementPoints, 0); // sin posición
  });

  test('Power, Presencia, Conversión y tiers', () {
    final list = DeckStats.compute(
      entries: [
        _e('bw', 'p1', pos: 1), // 8
        _e('bw', 'p2', pos: 5), // 2
        _e('bw', 'p3', pos: 20), // 0
        _e('bw', 'p4', pos: 30), // 0
        _e('tw', 'p5', pos: 2), // 6
        _e('tw', 'p6', pos: 3), // 4
        _e('gb', 'p7', pos: 9), // 1
        _e('gb', 'p8', pos: 12), // 1
        _e('zz', 'p9', pos: 25), // 0 → Rogue
        _e('zz', 'p10', pos: 26),
      ],
      matches: [_m('bw', 'tw', MatchResult.p1Win, top: true)],
    );
    final by = {for (final d in list) d.deckId: d};
    // bw y tw empatan a 10 de Power; tw convierte mejor (2/2 vs 2/4) → va primero.
    expect(by['tw']!.power, 10);
    expect(by['bw']!.power, 10);
    expect(list[0].deckId, 'tw');
    expect(list[1].deckId, 'bw');
    expect(by['bw']!.presence, closeTo(4 / 10, 1e-9));
    expect(by['bw']!.conversion, closeTo(2 / 4, 1e-9));
    expect(by['tw']!.conversion, 1.0);
    expect(by['tw']!.tier, DeckTier.s);
    expect(by['bw']!.tier, DeckTier.s);
    expect(by['gb']!.power, 2); // 2/10 = 20 % → B
    expect(by['gb']!.tier, DeckTier.b);
    expect(by['zz']!.power, 0);
    expect(by['zz']!.tier, DeckTier.rogue);
    expect(by['zz']!.rank, 4);
    // Las estadísticas de partidas se siguen contando
    expect(by['bw']!.topWins, 1);
    expect(by['tw']!.topLosses, 1);
  });

  test('Uso, jugadores distintos y entradas al top', () {
    final list = DeckStats.compute(
      entries: [
        _e('x', 'p1', top: 4, pos: 3),
        _e('x', 'p2', top: 4, pos: 9),
        _e('x', 'p1', top: 0, pos: 1), // sin Top Cut: el 1º cuenta como Top
      ],
      matches: const [],
    );
    final x = list.single;
    expect(x.entries, 3);
    expect(x.pilots.length, 2);
    expect(x.topEntries, 2);
    expect(x.titles, 1);
    expect(x.bestPosition, 1);
    expect(x.power, 4 + 8);
    expect(x.presence, 1.0);
  });

  test('Doble derrota cuenta como derrota para los dos mazos', () {
    final list = DeckStats.compute(
      entries: [_e('x', 'p1'), _e('y', 'p2')],
      matches: [_m('x', 'y', MatchResult.doubleLoss)],
    );
    for (final d in list) {
      expect(d.swissLosses, 1);
      expect(d.power, 0);
      expect(d.tier, DeckTier.rogue);
    }
  });

  test('Umbrales de tier relativos al mejor Power', () {
    expect(DeckStats.tierFor(70, 100), DeckTier.s);
    expect(DeckStats.tierFor(69, 100), DeckTier.a);
    expect(DeckStats.tierFor(40, 100), DeckTier.a);
    expect(DeckStats.tierFor(39, 100), DeckTier.b);
    expect(DeckStats.tierFor(15, 100), DeckTier.b);
    expect(DeckStats.tierFor(14, 100), DeckTier.c);
    expect(DeckStats.tierFor(1, 100), DeckTier.c);
    expect(DeckStats.tierFor(0, 100), DeckTier.rogue);
    expect(DeckStats.tierFor(0, 0), DeckTier.rogue);
  });

  test('Empate total se ordena por nombre', () {
    final a = DeckSeasonStats('a', 'Beta');
    final b = DeckSeasonStats('b', 'Alfa');
    final ranked = DeckStats.rank([a, b]);
    expect(ranked.first.name, 'Alfa');
  });
}
