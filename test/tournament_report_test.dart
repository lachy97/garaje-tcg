import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/enums.dart';
import 'package:garaje_tcg/features/tournaments/domain/tournament_report.dart';
import 'package:garaje_tcg/features/tournaments/presentation/report/report_widgets.dart';

void main() {
  const entries = [
    ReportEntry(playerId: 'a', name: 'Ana', deck: 'Blackwing', position: 1),
    ReportEntry(playerId: 'b', name: 'Beto', deck: 'Vayu Turbo', position: 2),
    ReportEntry(playerId: 'c', name: 'Caro', deck: 'Blackwing', position: 3),
    ReportEntry(playerId: 'd', name: 'Dani', position: 4, dropped: true),
    ReportEntry(playerId: 'e', name: 'Eli', deck: 'Hero Frog', position: 5, lateRounds: 1),
  ];
  const matches = [
    // Ronda 1 (Eli entró tarde): Ana gana, Beto empata con Caro, Dani BYE.
    ReportMatch(player1Id: 'a', player2Id: 'b', result: MatchResult.p1Win),
    ReportMatch(player1Id: 'c', player2Id: 'd', result: MatchResult.draw),
    // Ronda 2
    ReportMatch(player1Id: 'a', player2Id: 'c', result: MatchResult.p2Win),
    ReportMatch(player1Id: 'b', player2Id: 'e', result: MatchResult.doubleLoss),
    ReportMatch(player1Id: 'd', result: MatchResult.p1Win, isBye: true),
    // Top (final): sin resultado aún no cuenta.
    ReportMatch(player1Id: 'a', player2Id: 'b', result: MatchResult.pending),
  ];

  final r = TournamentReport.build(entries: entries, matches: matches, topCutSize: 2);

  test('récord de todo el torneo', () {
    final by = {for (final p in r.participants) p.playerId: p};
    expect(by['a']!.record, '1-1');
    expect(by['b']!.record, '0-2');
    expect(by['c']!.record, '1-0-1');
    expect(by['d']!.record, '1-0-1', reason: 'BYE = victoria');
    expect(by['e']!.record, '0-2', reason: 'ronda perdida por entrar tarde + doble derrota');
    expect(by['a']!.winRate, 0.5);
    expect(by['a']!.madeTop && by['b']!.madeTop, isTrue);
    expect(by['c']!.madeTop, isFalse);
    expect(r.participants.map((p) => p.position), [1, 2, 3, 4, 5]);
  });

  test('metagame: de más a menos jugadores, sin mazo al final', () {
    expect(r.metagame.map((d) => (d.name, d.players)).toList(), [
      ('Blackwing', 2),
      ('Hero Frog', 1),
      ('Vayu Turbo', 1),
      (null, 1),
    ]);
    expect(r.metagame.first.fraction, 0.4);
    expect(r.deckCount, 3);
    expect(r.players, 5);
  });

  test('colores: el más jugado primero, sin mazo en gris', () {
    final c = metaColors(r.metagame);
    expect(c['Blackwing'], kMetaPalette[0]);
    expect(c['Vayu Turbo'], kMetaPalette[2]);
    expect(c[null], kMetaNoDeck);
  });

  test('porcentajes', () {
    expect(sharePct(0.15), '15 %');
    expect(sharePct(2 / 42), '4,8 %');
    expect(sharePct(0.05), '5 %');
    expect(sharePct(0.0997), '10 %');
  });
}
