import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/backup/backup_merge.dart';
import 'package:garaje_tcg/core/db/app_database.dart';
import 'package:garaje_tcg/features/tournaments/application/tournament_service.dart';
import 'package:garaje_tcg/features/tournaments/domain/game_score.dart';

/// Pruebas de la importación integrada con BDs SQLite reales en archivos
/// temporales. Si el equipo no tiene SQLite nativo, se saltan.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('gtcg_merge'));
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<AppDatabase?> open(String name) async {
    try {
      final db = AppDatabase(NativeDatabase(File('${tmp.path}/$name')));
      await db.customSelect('SELECT 1').get();
      return db;
    } catch (e) {
      stderr.writeln('SQLite no disponible, prueba omitida: $e');
      return null;
    }
  }

  /// Torneo de 4 jugadores con la ronda 1 jugada.
  Future<Tournament> tournament(AppDatabase db, String name, DateTime date,
      {List<String> nicks = const ['Ana', 'Beto', 'Caro', 'Dani']}) async {
    final t = await db.tournamentsDao.createTournament(name: name, date: date, swissRounds: 3);
    for (final n in nicks) {
      final existing = (await db.select(db.players).get()).where((p) => p.nickname == n);
      final p = existing.isNotEmpty ? existing.first : await db.playersDao.create(nickname: n);
      await db.tournamentsDao.registerPlayer(t.id, p.id, deckName: 'Blackwing');
    }
    final service = TournamentService(db);
    await service.generateNextSwissRound(t.id);
    for (final m in await db.tournamentsDao.matchesOfTournament(t.id)) {
      if (!m.isBye) await service.reportScore(m.id, const GameScore(2, 0, 1));
    }
    return t;
  }

  /// Bytes del archivo SQLite de [db] (se cierra).
  Future<Uint8List> fileOf(AppDatabase db, String name) async {
    await db.close();
    return File('${tmp.path}/$name').readAsBytes();
  }

  Future<int> count(AppDatabase db, String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as int;

  test('Torneo nuevo se añade y los jugadores se unen por apodo', () async {
    final src = await open('src.sqlite');
    if (src == null) return;
    await tournament(src, 'Torneo #5', DateTime(2026, 10, 18));
    final bytes = await fileOf(src, 'src.sqlite');

    final phone = (await open('phone.sqlite'))!;
    await phone.playersDao.create(nickname: 'ana'); // mismo apodo, otro id
    final merger = BackupMerger(phone, tempDir: tmp);
    final plan = await merger.plan(bytes);
    expect(plan.items.single.kind, MergeKind.newTournament);
    expect(plan.items.single.action, MergeAction.add);

    final report = await merger.merge(bytes);
    expect(report.tournamentsAdded, 1);
    expect(report.playersAdded, 3); // Ana ya estaba
    expect(await count(phone, "SELECT COUNT(*) FROM players WHERE lower(nickname) = 'ana'"), 1);
    expect(await count(phone, 'SELECT COUNT(*) FROM matches'), 2);
    await phone.close();
  });

  test('Mismo nombre y otra fecha: por defecto se añade como otro torneo', () async {
    final src = await open('src.sqlite');
    if (src == null) return;
    await tournament(src, 'Torneo semanal', DateTime(2026, 10, 18));
    final bytes = await fileOf(src, 'src.sqlite');

    final phone = (await open('phone.sqlite'))!;
    await tournament(phone, 'Torneo semanal', DateTime(2026, 10, 11));
    final merger = BackupMerger(phone, tempDir: tmp);
    final plan = await merger.plan(bytes);
    expect(plan.items.single.kind, MergeKind.sameNameOtherDate);
    expect(plan.items.single.action, MergeAction.add);
    await merger.merge(bytes);
    expect(await count(phone, 'SELECT COUNT(*) FROM tournaments WHERE deleted_at IS NULL'), 2);
    await phone.close();
  });

  test('El mismo torneo con cambios más nuevos en el teléfono no se pisa', () async {
    final src = await open('src.sqlite');
    if (src == null) return;
    final t = await tournament(src, 'Torneo #6', DateTime(2026, 10, 25));
    final bytes = await fileOf(src, 'src.sqlite');

    // El teléfono parte de la misma copia y luego corrige un resultado.
    await File('${tmp.path}/src.sqlite').copy('${tmp.path}/phone.sqlite');
    final phone = (await open('phone.sqlite'))!;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final m = (await phone.tournamentsDao.matchesOfTournament(t.id)).firstWhere((m) => !m.isBye);
    await TournamentService(phone).reportScore(m.id, const GameScore(0, 0, 2));

    final merger = BackupMerger(phone, tempDir: tmp);
    final plan = await merger.plan(bytes);
    final item = plan.items.single;
    expect(item.kind, MergeKind.sameTournament);
    expect(item.localNewer, isTrue);
    expect(item.action, MergeAction.skip);

    final report = await merger.merge(bytes);
    expect(report.tournamentsSkipped, 1);
    final after = await phone.tournamentsDao.matchById(m.id);
    expect(after!.result, MatchResult.p2Win); // se conservó la corrección

    // Si se elige reemplazar, gana la copia.
    await merger.merge(bytes, decisions: {item.importId: MergeAction.replace});
    expect((await phone.tournamentsDao.matchById(m.id))!.result, MatchResult.p1Win);
    await phone.close();
  });

  test('Jugadores borrados en la copia con partidas no rompen la importación', () async {
    final src = await open('src.sqlite');
    if (src == null) return;
    await tournament(src, 'Torneo #7', DateTime(2026, 11, 1));
    final caro = (await src.select(src.players).get()).firstWhere((p) => p.nickname == 'Caro');
    await src.playersDao.softDelete(caro.id);
    final bytes = await fileOf(src, 'src.sqlite');

    final phone = (await open('phone.sqlite'))!;
    final report = await BackupMerger(phone, tempDir: tmp).merge(bytes);
    expect(report.tournamentsAdded, 1);
    expect(await count(phone, 'SELECT COUNT(*) FROM matches'), 2);
    // Caro existe (para las partidas) pero sigue borrada.
    expect(await count(phone, "SELECT COUNT(*) FROM players WHERE nickname = 'Caro' "
        'AND deleted_at IS NOT NULL'), 1);
    await phone.close();
  });

  test('Los torneos de una temporada cerrada en el teléfono no se importan', () async {
    final src = await open('src.sqlite');
    if (src == null) return;
    await tournament(src, 'Torneo #8', DateTime(2026, 8, 2));
    final bytes = await fileOf(src, 'src.sqlite');

    final phone = (await open('phone.sqlite'))!;
    final season = await phone.seasonsDao.seasonFor(DateTime(2026, 8, 2));
    await phone.rankingDao.closeSeason(season.id);
    final merger = BackupMerger(phone, tempDir: tmp);
    final plan = await merger.plan(bytes);
    expect(plan.items.single.kind, MergeKind.lockedSeason);
    expect(plan.items.single.allowed, [MergeAction.skip]);
    await merger.merge(bytes, decisions: {plan.items.single.importId: MergeAction.add});
    expect(await count(phone, 'SELECT COUNT(*) FROM tournaments'), 0);
    await phone.close();
  });
}
