import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../features/ranking/domain/points_scale.dart';
// Lo usa el código generado (app_database.g.dart): los ids por defecto
// de las tablas llaman a newId(), definido aquí.
import '../utils/ids.dart';
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
    Penalties,
  ],
  daos: [PlayersDao, DecksDao, SeasonsDao, TournamentsDao, RankingDao],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] permite inyectar una BD en memoria para tests.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(name: kDatabaseName);

  bool _closed = false;

  /// Cierra la BD una sola vez (al importar una copia se cierra a mano y
  /// luego Riverpod vuelve a intentar cerrarla al descartarla).
  Future<void> closeOnce() async {
    if (_closed) return;
    _closed = true;
    await close();
  }

  /// Ruta del archivo SQLite en el teléfono.
  Future<String> filePath() async {
    final row = await customSelect(
            "SELECT file FROM pragma_database_list WHERE name = 'main'")
        .getSingle();
    return row.read<String>('file');
  }

  @override
  int get schemaVersion => 7;

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
          if (from < 3) {
            // v3: datos personales del jugador
            await m.addColumn(players, players.konamiId);
            await m.addColumn(players, players.phone);
          }
          if (from < 4) {
            // v4: tiempo por ronda
            await m.addColumn(tournaments, tournaments.roundMinutes);
            await m.addColumn(rounds, rounds.timerStartedAt);
          }
          if (from < 5) {
            // v5: imagen de cada mazo
            await m.addColumn(decks, decks.imagePath);
          }
          if (from < 6) {
            // v6: inscripción tardía y penalizaciones
            await m.addColumn(tournamentPlayers, tournamentPlayers.lateRounds);
            await m.createTable(penalties);
            // createTable no crea los índices de @TableIndex (createAll sí).
            await customStatement('CREATE INDEX IF NOT EXISTS idx_penalty_tournament '
                'ON penalties (tournament_id)');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_penalty_player '
                'ON penalties (player_id)');
          }
          if (from < 7) {
            // v7: cover pagado en cada inscripción
            await m.addColumn(tournamentPlayers, tournamentPlayers.paid);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await seedDefaultPointsScales();
          await decksDao.seedCatalog();
          // Fotos propias de mazos: rutas absolutas antiguas → relativas (AppPaths).
          await customStatement(
            "UPDATE decks SET image_path = 'docs:' || "
            "substr(image_path, instr(image_path, '/deck_images/') + 1) "
            "WHERE image_path LIKE '%/deck_images/%' AND image_path NOT LIKE 'docs:%'",
          );
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
