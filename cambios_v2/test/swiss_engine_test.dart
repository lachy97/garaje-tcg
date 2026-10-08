import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/enums.dart';
import 'package:garaje_tcg/features/tournaments/domain/models.dart';
import 'package:garaje_tcg/features/tournaments/domain/swiss/standings_calculator.dart';
import 'package:garaje_tcg/features/tournaments/domain/swiss/swiss_pairing_engine.dart';
import 'package:garaje_tcg/features/tournaments/domain/top_cut/top_cut_bracket.dart';
import 'package:garaje_tcg/features/tournaments/domain/tournament_rules.dart';

List<SwissPlayer> _players(int n) =>
    [for (var i = 1; i <= n; i++) SwissPlayer('p${i.toString().padLeft(2, '0')}')];

/// Simula un Swiss completo con resultados aleatorios.
List<MatchRecord> _simulate(int n, int rounds, int seed) {
  final rnd = Random(seed);
  final engine = SwissPairingEngine(random: Random(seed));
  final players = _players(n);
  final history = <MatchRecord>[];
  for (var r = 1; r <= rounds; r++) {
    final out = engine.pairRound(round: r, players: players, previous: history);
    for (final p in out.pairings) {
      final roll = rnd.nextInt(10);
      history.add(MatchRecord(
        round: r,
        player1Id: p.player1Id,
        player2Id: p.player2Id,
        result: p.isBye
            ? MatchResult.p1Win
            : roll < 5
                ? MatchResult.p1Win
                : roll < 9
                    ? MatchResult.p2Win
                    : MatchResult.draw,
      ));
    }
  }
  return history;
}

void main() {
  group('StandingsCalculator', () {
    test('Puntos y OMW% desempatan', () {
      final players = _players(4);
      // R1: p01 > p02, p03 > p04 · R2: p01 > p03, p04 > p02
      final ms = [
        const MatchRecord(round: 1, player1Id: 'p01', player2Id: 'p02', result: MatchResult.p1Win),
        const MatchRecord(round: 1, player1Id: 'p03', player2Id: 'p04', result: MatchResult.p1Win),
        const MatchRecord(round: 2, player1Id: 'p01', player2Id: 'p03', result: MatchResult.p1Win),
        const MatchRecord(round: 2, player1Id: 'p04', player2Id: 'p02', result: MatchResult.p1Win),
      ];
      final s = StandingsCalculator.compute(players: players, matches: ms);
      expect(s.first.playerId, 'p01');
      expect(s.first.points, 6);
      // p03 y p04 con 3 pts: p03 jugó contra p01 (100%) y p04 (50%) → OMW 75%
      // p04 jugó contra p03 (50%) y p02 (33% piso) → OMW ~41.7% → p03 por delante
      expect(s[1].playerId, 'p03');
      expect(s[2].playerId, 'p04');
      expect(s.last.playerId, 'p02');
      expect(s[1].omw, closeTo(0.75, 1e-9));
    });

    test('GW% desempata cuando puntos, OMW% y OOMW% son iguales', () {
      final s = StandingsCalculator.compute(players: _players(4), matches: const [
        MatchRecord(round: 1, player1Id: 'p01', player2Id: 'p02',
            result: MatchResult.p1Win, games1: 2, gamesDraw: 0, games2: 1),
        MatchRecord(round: 1, player1Id: 'p03', player2Id: 'p04',
            result: MatchResult.p1Win, games1: 2, gamesDraw: 0, games2: 0),
      ]);
      // p01 y p03 empatan en todo salvo juegos: p03 (2-0) supera a p01 (2-1)
      expect(s[0].playerId, 'p03');
      expect(s[1].playerId, 'p01');
      expect(s[0].gwp, closeTo(1.0, 1e-9));
      expect(s[1].gwp, closeTo(2 / 3, 1e-9));
    });

    test('BYE suma 3 puntos pero no cuenta como rival', () {
      final s = StandingsCalculator.compute(players: _players(1), matches: const [
        MatchRecord(round: 1, player1Id: 'p01', result: MatchResult.p1Win),
      ]);
      expect(s.single.points, 3);
      expect(s.single.byes, 1);
      expect(s.single.omw, 0);
    });

    test('Matches pendientes no cuentan', () {
      final s = StandingsCalculator.compute(players: _players(2), matches: const [
        MatchRecord(round: 1, player1Id: 'p01', player2Id: 'p02'),
      ]);
      expect(s.every((x) => x.points == 0 && x.matchesPlayed == 0), isTrue);
    });
  });

  group('SwissPairingEngine', () {
    test('Sin rematches y cada jugador una vez por ronda (8-40 jugadores, 30 simulaciones)', () {
      for (var seed = 0; seed < 30; seed++) {
        final n = 8 + seed;
        final rounds = TournamentRules.suggestedSwissRounds(n);
        final history = _simulate(n, rounds, seed);
        final seen = <String>{};
        for (final m in history.where((m) => !m.isBye)) {
          final key = ([m.player1Id, m.player2Id!]..sort()).join('|');
          expect(seen.add(key), isTrue, reason: 'rematch $key (n=$n, seed=$seed)');
        }
        for (var r = 1; r <= rounds; r++) {
          final ids = [
            for (final m in history.where((m) => m.round == r)) ...[m.player1Id, if (m.player2Id != null) m.player2Id!],
          ];
          expect(ids.toSet().length, ids.length);
          expect(ids.length, n);
        }
      }
    });

    test('Nadie recibe dos BYE si se puede evitar', () {
      for (var seed = 0; seed < 20; seed++) {
        final history = _simulate(9, 4, seed);
        final byes = history.where((m) => m.isBye).map((m) => m.player1Id).toList();
        expect(byes.toSet().length, byes.length);
      }
    });

    test('BYE al jugador con menos puntos', () {
      final players = _players(5);
      final prev = [
        const MatchRecord(round: 1, player1Id: 'p01', player2Id: 'p02', result: MatchResult.p1Win),
        const MatchRecord(round: 1, player1Id: 'p03', player2Id: 'p04', result: MatchResult.p1Win),
        const MatchRecord(round: 1, player1Id: 'p05', result: MatchResult.p1Win),
      ];
      final out = SwissPairingEngine(random: Random(1))
          .pairRound(round: 2, players: players, previous: prev);
      final bye = out.pairings.singleWhere((p) => p.isBye);
      expect(['p02', 'p04'], contains(bye.player1Id));
      // Mesa 1 = cruce de jugadores con 3 puntos
      final top = out.pairings.first;
      expect({top.player1Id, top.player2Id}.intersection({'p01', 'p03', 'p05'}).length, 2);
    });

    test('Jugadores retirados no se emparejan', () {
      final players = [..._players(4), const SwissPlayer('p05', dropped: true, dropRound: 1)];
      final out = SwissPairingEngine(random: Random(3))
          .pairRound(round: 2, players: players, previous: const []);
      final ids = [for (final p in out.pairings) ...[p.player1Id, if (p.player2Id != null) p.player2Id!]];
      expect(ids, isNot(contains('p05')));
      expect(out.pairings.any((p) => p.isBye), isFalse);
    });

    test('Torneo diminuto: repite rival solo cuando es inevitable', () {
      final history = _simulate(4, 4, 7); // 4 jugadores, 4 rondas → forzoso
      expect(history.length, 8);
    });
  });

  group('TopCutBracket', () {
    test('Siembra estándar', () {
      expect(TopCutBracket.seedOrder(4), [1, 4, 2, 3]);
      expect(TopCutBracket.seedOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
      final r1 = TopCutBracket.firstRound(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
      expect([for (final m in r1) '${m.player1Id}${m.player2Id}'], ['ah', 'de', 'bg', 'cf']);
    });

    BracketMatch played(BracketMatch m, {bool p1 = true}) => BracketMatch(
          slot: m.slot,
          player1Id: m.player1Id,
          player2Id: m.player2Id,
          isThirdPlace: m.isThirdPlace,
          result: p1 ? MatchResult.p1Win : MatchResult.p2Win,
        );

    test('Top 8 completo con partida por el 3er puesto', () {
      final seeds = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
      final swissOrder = [...seeds, 'i', 'j'];
      // Cuartos: ah→a, de→e (sorpresa), bg→b, cf→c
      final qf = TopCutBracket.firstRound(seeds);
      final qfPlayed = [played(qf[0]), played(qf[1], p1: false), played(qf[2]), played(qf[3])];
      // Semis: a-e, b-c (+ nada aún)
      final sf = TopCutBracket.nextRound(qfPlayed, thirdPlaceMatch: true);
      expect(sf.length, 2);
      expect('${sf[0].player1Id}${sf[0].player2Id}', 'ae');
      expect('${sf[1].player1Id}${sf[1].player2Id}', 'bc');
      final sfPlayed = [played(sf[0]), played(sf[1], p1: false)]; // a y c a la final
      final fin = TopCutBracket.nextRound(sfPlayed, thirdPlaceMatch: true);
      expect(fin.length, 2);
      expect(fin.where((m) => m.isThirdPlace).single.player1Id, 'e');
      final finPlayed = [played(fin[0], p1: false), played(fin[1])]; // c campeón; e 3º
      expect(TopCutBracket.nextRound(finPlayed, thirdPlaceMatch: true), isEmpty);

      final pos = TopCutBracket.finalPositions(
        rounds: [qfPlayed, sfPlayed, finPlayed],
        swissOrder: swissOrder,
      );
      expect(pos['c'], 1);
      expect(pos['a'], 2);
      expect(pos['e'], 3);
      expect(pos['b'], 4);
      // Eliminados en cuartos (h, d, g, f) ordenados por Swiss: d, f, g, h → 5..8
      expect([pos['d'], pos['f'], pos['g'], pos['h']], [5, 6, 7, 8]);
      expect([pos['i'], pos['j']], [9, 10]);
    });

    test('Empate en Top Cut lanza error', () {
      const m = BracketMatch(slot: 1, player1Id: 'a', player2Id: 'b', result: MatchResult.draw);
      expect(() => m.winner, throwsA(isA<TournamentException>()));
    });
  });
}
