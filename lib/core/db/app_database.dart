import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../features/ranking/domain/points_scale.dart';
import 'daos/decks_dao.dart';
import 'daos/players_dao.dart';
import 'daos/ranking_dao.dart';
import 'daos/seasons_dao.dart';
import 'daos/tournaments_dao.dart';
import 'enums.dart';
import 'tables.dart';

export 'enums.dart';

part 'app_database.g.dart';

const kDatabaseName = 'garaje_tcg';

@DriftDatabase(
  tables: [
    Players,
    Decks,
    Seasons,
    PointsScaleEntries,
    Tournaments,
    TournamentPlayers,
    Rounds,
    Matches,
    SeasonResults,
    RankingSnapshots,
    DeckSnapshots,
  ],
  daos: [PlayersDao, DecksDao, SeasonsDao, TournamentsDao, RankingDao],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] permite inyectar una BD en memoria para tests.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(name: kDatabaseName);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: marcador al mejor de 3 en cada match
            await m.addColumn(matches, matches.games1);
            await m.addColumn(matches, matches.gamesDraw);
            await m.addColumn(matches, matches.games2);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await seedDefaultPointsScales();
        },
      );

  /// Copia a la BD las escalas por defecto de los tamaños de Top Cut que aún
  /// no tengan escala. Así una BD existente recibe tamaños nuevos (p. ej. Top 4)
  /// sin pisar escalas que el organizador ya editó.
  Future<void> seedDefaultPointsScales() async {
    final existing = await (selectOnly(pointsScaleEntries, distinct: true)
          ..addColumns([pointsScaleEntries.topCutSize])
          ..where(pointsScaleEntries.deletedAt.isNull()))
        .map((r) => r.read(pointsScaleEntries.topCutSize)!)
        .get();
    final missing = PointsScale.defaults.entries
        .where((e) => !existing.contains(e.key))
        .toList();
    if (missing.isEmpty) return;
    await batch((b) {
      b.insertAll(pointsScaleEntries, [
        for (final MapEntry(key: size, value: tiers) in missing)
          for (final t in tiers)
            PointsScaleEntriesCompanion.insert(
              topCutSize: size,
              positionFrom: t.from,
              positionTo: t.to,
              points: t.points,
            ),
      ]);
    });
  }
}
