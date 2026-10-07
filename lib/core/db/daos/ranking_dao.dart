import 'package:drift/drift.dart';

import '../../../features/ranking/domain/points_scale.dart';
import '../app_database.dart';
import '../tables.dart';

part 'ranking_dao.g.dart';

/// Fila del ranking trimestral (versión básica de la Fase 1).
class SeasonStandingRow {
  const SeasonStandingRow({
    required this.playerId,
    required this.nickname,
    required this.points,
    required this.tournaments,
    required this.bestPosition,
  });
  final String playerId;
  final String nickname;
  final int points;
  final int tournaments;
  final int bestPosition;
}

@DriftAccessor(tables: [PointsScaleEntries, SeasonResults])
class RankingDao extends DatabaseAccessor<AppDatabase> with _$RankingDaoMixin {
  RankingDao(super.attachedDatabase);

  /// Escala vigente para un tamaño de Top Cut (0 → escala vacía, nadie puntúa).
  Future<PointsScale> scaleFor(int topCutSize) async {
    final rows = await (select(pointsScaleEntries)
          ..where((e) => e.topCutSize.equals(topCutSize) & e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.asc(e.positionFrom)]))
        .get();
    return PointsScale(
      topCutSize,
      [for (final r in rows) PointsTier(r.positionFrom, r.positionTo, r.points)],
    );
  }

  /// Reemplaza la escala de un tamaño de Top Cut (pantalla de Ajustes).
  /// No recalcula torneos ya terminados.
  Future<void> replaceScale(PointsScale scale) {
    final now = DateTime.now();
    return transaction(() async {
      await (update(pointsScaleEntries)
            ..where((e) =>
                e.topCutSize.equals(scale.topCutSize) & e.deletedAt.isNull()))
          .write(PointsScaleEntriesCompanion(
              deletedAt: Value(now), updatedAt: Value(now)));
      await batch((b) => b.insertAll(pointsScaleEntries, [
            for (final t in scale.tiers)
              PointsScaleEntriesCompanion.insert(
                topCutSize: scale.topCutSize,
                positionFrom: t.from,
                positionTo: t.to,
                points: t.points,
              ),
          ]));
    });
  }

  /// Escribe los puntos de ranking de un torneo terminado.
  /// Idempotente: si se vuelve a finalizar el torneo, sobrescribe.
  Future<void> writeTournamentResults({
    required String seasonId,
    required String tournamentId,
    required int topCutSize,
    required Map<String, int> finalPositions, // playerId → posición
  }) async {
    final scale = await scaleFor(topCutSize);
    await batch((b) {
      b.deleteWhere(
          seasonResults, (r) => r.tournamentId.equals(tournamentId));
      b.insertAll(seasonResults, [
        for (final MapEntry(key: playerId, value: pos) in finalPositions.entries)
          SeasonResultsCompanion.insert(
            seasonId: seasonId,
            tournamentId: tournamentId,
            playerId: playerId,
            position: pos,
            points: scale.pointsFor(pos),
          ),
      ]);
    });
  }

  /// Ranking del trimestre: suma de puntos por jugador.
  /// Orden: puntos ↓, mejor posición ↑, menos torneos ↑.
  /// (Winrate como 3er desempate llega con el ranking completo de la Fase 2.)
  Stream<List<SeasonStandingRow>> watchSeasonStandings(String seasonId) {
    return customSelect(
      'SELECT p.id AS id, p.nickname AS nickname, '
      'SUM(sr.points) AS pts, COUNT(*) AS t, MIN(sr.position) AS best '
      'FROM season_results sr JOIN players p ON p.id = sr.player_id '
      'WHERE sr.season_id = ? AND sr.deleted_at IS NULL '
      'GROUP BY p.id, p.nickname '
      'ORDER BY pts DESC, best ASC, t ASC, p.nickname ASC',
      variables: [Variable.withString(seasonId)],
      readsFrom: {seasonResults, attachedDatabase.players},
    ).watch().map((rows) => [
          for (final r in rows)
            SeasonStandingRow(
              playerId: r.read<String>('id'),
              nickname: r.read<String>('nickname'),
              points: r.read<int>('pts'),
              tournaments: r.read<int>('t'),
              bestPosition: r.read<int>('best'),
            ),
        ]);
  }

  /// Puntos obtenidos en un torneo (para la pantalla de resultado final).
  Stream<List<SeasonResult>> watchTournamentResults(String tournamentId) {
    return (select(seasonResults)
          ..where((r) => r.tournamentId.equals(tournamentId))
          ..orderBy([(r) => OrderingTerm.asc(r.position)]))
        .watch();
  }
}
