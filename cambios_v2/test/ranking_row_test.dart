import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/features/ranking/domain/ranking_row.dart';

RankingRow _r(String name, int pts, int best, int t, {int w = 0, int l = 0, int d = 0}) =>
    RankingRow(
      playerId: name,
      nickname: name,
      points: pts,
      tournaments: t,
      bestPosition: best,
      wins: w,
      losses: l,
      draws: d,
    );

void main() {
  test('Ranking: puntos → mejor posición → winrate → menos torneos', () {
    final ranked = RankingRow.sortAndRank([
      _r('A', 500, 2, 2, w: 5, l: 3),
      _r('B', 600, 3, 3),
      _r('C', 500, 1, 2, w: 1, l: 5), // misma cifra que A, mejor posición
      _r('D', 500, 2, 2, w: 7, l: 1), // empata con A en puntos y posición; más WR
      _r('E', 500, 2, 1, w: 7, l: 1), // igual que D pero menos torneos
    ]);
    expect(ranked.map((r) => r.nickname).toList(), ['B', 'C', 'E', 'D', 'A']);
    expect(ranked.map((r) => r.rank).toList(), [1, 2, 3, 4, 5]);
  });

  test('Winrate no cuenta BYE y sin partidas es 0', () {
    expect(_r('X', 0, 9, 1).winrate, 0);
    expect(_r('Y', 0, 9, 1, w: 3, l: 1).winrate, 0.75);
  });
}
