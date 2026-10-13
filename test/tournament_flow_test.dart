import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/app_database.dart';
import 'package:garaje_tcg/features/tournaments/application/tournament_service.dart';
import 'package:garaje_tcg/features/tournaments/domain/game_score.dart';
import 'package:garaje_tcg/features/tournaments/domain/models.dart';

/// Flujo del torneo con una BD SQLite real en memoria (corregir rondas,
/// deshacer, Top Cut con drops, cierre de temporada). Si el equipo no tiene
/// SQLite nativo, se omiten.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<AppDatabase?> open() async {
    try {
      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
      return db;
    } catch (e) {
      stderr.writeln('SQLite no disponible, prueba omitida: $e');
      return null;
    }
  }

  Future<Tournament> create(AppDatabase db, int players,
      {int swissRounds = 3, int topCut = 0, DateTime? date, String? deckName}) async {
    final t = await db.tournamentsDao.createTournament(
        name: 'Prueba', date: date ?? DateTime(2026, 10, 18), swissRounds: swissRounds,
        topCutSize: topCut);
    for (var i = 1; i <= players; i++) {
      final p = await db.playersDao.create(nickname: 'Jugador $i');
      await db.tournamentsDao.registerPlayer(t.id, p.id, deckName: deckName);
    }
    return t;
  }

  Future<void> reportAll(AppDatabase db, TournamentService s, String tid) async {
    final rounds = await db.tournamentsDao.roundsOf(tid);
    for (final m in await db.tournamentsDao.matchesOfTournament(tid)) {
      if (m.roundId == rounds.last.id && !m.isBye && !m.result.isReported) {
        await s.reportScore(m.id, const GameScore(2, 0, 0));
      }
    }
  }

  Future<Tournament> reload(AppDatabase db, String id) async =>
      (await db.tournamentsDao.getById(id))!;

  test('Se corrigen rondas Swiss cerradas, pero no se dejan pendientes', () async {
    final db = await open();
    if (db == null) return;
    final s = TournamentService(db);
    final t = await create(db, 4);
    await s.generateNextSwissRound(t.id);
    await reportAll(db, s, t.id);
    final r1 = (await db.tournamentsDao.matchesOfTournament(t.id)).first;
    await s.generateNextSwissRound(t.id);

    await s.reportScore(r1.id, const GameScore(0, 0, 2)); // ronda 1 ya cerrada
    expect((await db.tournamentsDao.matchById(r1.id))!.result, MatchResult.p2Win);
    await expectLater(s.clearResult(r1.id), throwsA(isA<TournamentException>()));
    await db.close();
  });

  test('Deshacer ronda: vuelve a la anterior y luego a la inscripción', () async {
    final db = await open();
    if (db == null) return;
    final s = TournamentService(db);
    final t = await create(db, 4);
    await s.generateNextSwissRound(t.id);
    await reportAll(db, s, t.id);
    await s.generateNextSwissRound(t.id);

    await s.undoLastRound(t.id);
    var now = await reload(db, t.id);
    expect(now.currentRound, 1);
    expect(now.status, TournamentStatus.swiss);
    final rounds = await db.tournamentsDao.roundsOf(t.id);
    expect(rounds.length, 1);
    expect(rounds.single.status, RoundStatus.open);
    expect((await db.tournamentsDao.matchesOfTournament(t.id)).length, 2);

    await s.undoLastRound(t.id);
    now = await reload(db, t.id);
    expect(now.currentRound, 0);
    expect(now.status, TournamentStatus.draft);
    expect(await db.tournamentsDao.matchesOfTournament(t.id), isEmpty);
    await db.close();
  });

  test('Deshacer la 1ª ronda del Top Cut vuelve al Swiss', () async {
    final db = await open();
    if (db == null) return;
    final s = TournamentService(db);
    final t = await create(db, 6, swissRounds: 1, topCut: 4);
    await s.generateNextSwissRound(t.id);
    await reportAll(db, s, t.id);
    await s.startTopCut(t.id);
    expect((await reload(db, t.id)).status, TournamentStatus.topCut);

    await s.undoLastRound(t.id);
    final now = await reload(db, t.id);
    expect(now.status, TournamentStatus.swiss);
    expect(now.currentRound, 1);
    final regs = await db.tournamentsDao.registeredPlayers(t.id);
    expect(regs.every((r) => r.entry.swissPosition == null), isTrue);
    await db.close();
  });

  test('Con drops el Top Cut se reduce en vez de bloquearse', () async {
    final db = await open();
    if (db == null) return;
    final s = TournamentService(db);
    final t = await create(db, 8, swissRounds: 1, topCut: 8);
    await s.generateNextSwissRound(t.id);
    await reportAll(db, s, t.id);
    final p = (await db.tournamentsDao.registeredPlayers(t.id)).first;
    await db.tournamentsDao.dropPlayer(t.id, p.player.id, 1);

    await s.startTopCut(t.id);
    final now = await reload(db, t.id);
    expect(now.topCutSize, 4);
    expect(now.status, TournamentStatus.topCut);
    final top = (await db.tournamentsDao.roundsOf(t.id)).last;
    expect(top.bracketSize, 4);
    await db.close();
  });

  test('Temporada cerrada: ranking congelado y torneos bloqueados', () async {
    final db = await open();
    if (db == null) return;
    final s = TournamentService(db);
    final t = await create(db, 4, swissRounds: 1, date: DateTime(2026, 8, 2));
    await s.generateNextSwissRound(t.id);
    await reportAll(db, s, t.id);
    await s.startTopCut(t.id); // sin Top: termina el torneo
    expect((await reload(db, t.id)).status, TournamentStatus.finished);

    final season = (await reload(db, t.id)).seasonId;
    final before = await db.rankingDao.seasonRanking(season);
    await db.rankingDao.closeSeason(season);

    await expectLater(db.tournamentsDao.softDelete(t.id), throwsA(isA<StateError>()));
    await expectLater(
      db.tournamentsDao.createTournament(
          name: 'Tarde', date: DateTime(2026, 8, 20), swissRounds: 3),
      throwsA(isA<StateError>()),
    );
    // El ranking sale de la foto aunque cambie un apodo.
    await db.playersDao.edit(before.first.playerId, nickname: 'Otro nombre');
    final frozen = await db.rankingDao.seasonRanking(season);
    expect(frozen.length, before.length);
    expect(frozen.first.nickname, before.first.nickname);
    expect(frozen.first.points, before.first.points);

    await db.rankingDao.reopenSeason(season);
    await db.tournamentsDao.softDelete(t.id); // ya se puede
    await db.close();
  });

  test('No se cierra una temporada con torneos sin terminar', () async {
    final db = await open();
    if (db == null) return;
    final t = await create(db, 4);
    await expectLater(db.rankingDao.closeSeason(t.seasonId), throwsA(isA<StateError>()));
    await db.close();
  });

  test('Temporada cerrada: la tier list también queda congelada', () async {
    final db = await open();
    if (db == null) return;
    final s = TournamentService(db);
    final t = await create(db, 4,
        swissRounds: 1, date: DateTime(2026, 8, 2), deckName: 'Mazo Prueba Uno');
    await s.generateNextSwissRound(t.id);
    await reportAll(db, s, t.id);
    await s.startTopCut(t.id);

    final season = (await reload(db, t.id)).seasonId;
    final before = await db.rankingDao.seasonDecks(season);
    expect(before.single.name, 'Mazo Prueba Uno');
    await db.rankingDao.closeSeason(season);

    await db.decksDao.rename(before.single.deckId, 'Mazo Renombrado');
    final frozen = await db.rankingDao.seasonDecks(season);
    expect(frozen.single.name, 'Mazo Prueba Uno');
    expect(frozen.single.power, before.single.power);
    expect(frozen.single.tier, before.single.tier);
    expect(frozen.single.entries, 4);
    expect(frozen.single.pilots.length, 4);

    await db.rankingDao.reopenSeason(season);
    expect((await db.rankingDao.seasonDecks(season)).single.name, 'Mazo Renombrado');
    await db.close();
  });
}
