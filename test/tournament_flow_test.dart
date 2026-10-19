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

  test('Inscripción tardía, cambiar cruces y penalizaciones', () async {
    final db = await open();
    if (db == null) return;
    final s = TournamentService(db);
    final t = await create(db, 4, swissRounds: 3);
    await s.generateNextSwissRound(t.id);
    await reportAll(db, s, t.id);

    // Entra uno tarde: la ronda 1 cuenta como derrota.
    final late = await db.playersDao.create(nickname: 'Tarde');
    await s.registerLate(t.id, [late.id]);
    var table = await s.standings(t.id);
    final row = table.firstWhere((x) => x.playerId == late.id);
    expect(row.losses, 1);
    expect(row.points, 0);

    // Ronda 2 con 5 jugadores: hay BYE y el tardío entra a jugar.
    await s.generateNextSwissRound(t.id);
    final rounds = await db.tournamentsDao.roundsOf(t.id);
    final r2 = (await db.tournamentsDao.matchesOfTournament(t.id))
        .where((m) => m.roundId == rounds.last.id)
        .toList();
    expect(r2.length, 3);
    expect(r2.any((m) => m.player1Id == late.id || m.player2Id == late.id), isTrue);

    // Intercambiar el jugador del BYE con uno de otra mesa.
    final bye = r2.firstWhere((m) => m.isBye);
    final other = r2.firstWhere((m) => !m.isBye);
    final fromBye = bye.player1Id, fromOther = other.player2Id!;
    await s.swapPlayers(matchIdA: bye.id, slotA: 1, matchIdB: other.id, slotB: 2);
    final bye2 = (await db.tournamentsDao.matchById(bye.id))!;
    final other2 = (await db.tournamentsDao.matchById(other.id))!;
    expect(bye2.player1Id, fromOther);
    expect(bye2.isBye, isTrue);
    expect(other2.player2Id, fromBye);

    // Con resultado ya no se puede.
    await s.reportScore(other.id, const GameScore(2, 0, 0));
    await expectLater(
      s.swapPlayers(matchIdA: bye.id, slotA: 1, matchIdB: other.id, slotB: 1),
      throwsA(isA<TournamentException>()),
    );

    // Penalización (solo registro) y borrado lógico.
    await db.tournamentsDao.addPenalty(
        tournamentId: t.id, playerId: late.id, round: 2, kind: PenaltyKind.warning, reason: ' Tarde ');
    var pens = await db.tournamentsDao.watchPenalties(t.id).first;
    expect(pens.single.reason, 'Tarde');
    await db.tournamentsDao.deletePenalty(pens.single);
    pens = await db.tournamentsDao.watchPenalties(t.id).first;
    expect(pens, isEmpty);

    // Deshacer hasta la ronda 1 recorta las rondas perdidas del tardío.
    await s.undoLastRound(t.id);
    final reg = (await db.tournamentsDao.registeredPlayers(t.id))
        .firstWhere((r) => r.player.id == late.id);
    expect(reg.entry.lateRounds, 1);
    table = await s.standings(t.id);
    expect(table.length, 5);
    await db.close();
  });

  test('Al borrar un torneo sus puntos dejan de contar en el ranking', () async {
    final db = await open();
    if (db == null) return;
    final s = TournamentService(db);
    final keep = await create(db, 4, swissRounds: 1, topCut: 0);
    await s.generateNextSwissRound(keep.id);
    await reportAll(db, s, keep.id);
    await s.startTopCut(keep.id); // termina
    final gone = await db.tournamentsDao.createTournament(
        name: 'Se borra', date: DateTime(2026, 10, 19), swissRounds: 1);
    final regs = await db.tournamentsDao.registeredPlayers(keep.id);
    for (final r in regs) {
      await db.tournamentsDao.registerPlayer(gone.id, r.player.id);
    }
    await s.generateNextSwissRound(gone.id);
    await reportAll(db, s, gone.id);
    await s.startTopCut(gone.id);

    final season = keep.seasonId;
    final before = await db.rankingDao.seasonRanking(season);
    expect(before.every((r) => r.tournaments == 2), isTrue);

    await db.tournamentsDao.softDelete(gone.id);
    final after = await db.rankingDao.seasonRanking(season);
    expect(after.length, before.length);
    expect(after.every((r) => r.tournaments == 1), isTrue);
    expect(after.fold<int>(0, (a, r) => a + r.played), 2 * 2); // solo las partidas del que queda
    expect(await db.rankingDao.watchTournamentResults(gone.id).first, isEmpty);
    await db.close();
  });

  test('Último mazo de cada jugador y cover pagado', () async {
    final db = await open();
    if (db == null) return;
    final s = TournamentService(db);
    final dao = db.tournamentsDao;
    final a = await db.playersDao.create(nickname: 'Ana');
    final b = await db.playersDao.create(nickname: 'Beto');
    final c = await db.playersDao.create(nickname: 'Caro');

    // Torneo viejo: Ana con Zombie, Beto con Gladiator.
    final old = await dao.createTournament(
        name: 'Viejo', date: DateTime(2026, 10, 4), swissRounds: 1);
    await dao.registerPlayer(old.id, a.id, deckName: 'Zombie');
    await dao.registerPlayer(old.id, b.id, deckName: 'Gladiator Beast');
    await s.generateNextSwissRound(old.id);
    // Torneo más nuevo: Ana cambia a Plant Synchro; Beto sin mazo.
    final newer = await dao.createTournament(
        name: 'Nuevo', date: DateTime(2026, 10, 11), swissRounds: 1);
    await dao.registerPlayer(newer.id, a.id, deckName: 'Plant Synchro');
    await dao.registerPlayer(newer.id, b.id);
    await s.generateNextSwissRound(newer.id);
    // Un torneo aún en inscripción no cuenta como "jugado".
    final draft = await dao.createTournament(
        name: 'Borrador', date: DateTime(2026, 10, 25), swissRounds: 1);
    await dao.registerPlayer(draft.id, a.id, deckName: 'Blackwing');

    final next = await dao.createTournament(
        name: 'Siguiente', date: DateTime(2026, 10, 18), swissRounds: 1);
    final last = await dao.lastDecks(excludeTournamentId: next.id);
    expect(last[a.id]!.name, 'Plant Synchro');
    expect(last[b.id]!.name, 'Gladiator Beast', reason: 'sin mazo en el nuevo: vale el anterior');
    expect(last.containsKey(c.id), isFalse);

    await dao.registerPlayer(next.id, a.id, deckName: last[a.id]!.name);
    var reg = (await dao.registeredPlayers(next.id)).single;
    expect(reg.deck!.name, 'Plant Synchro');
    expect(reg.entry.paid, isFalse);

    await dao.setPaid(next.id, a.id, true);
    reg = (await dao.registeredPlayers(next.id)).single;
    expect(reg.entry.paid, isTrue);
    // Reinscribir no borra el pago.
    await dao.registerPlayer(next.id, a.id, deckName: 'Zombie');
    reg = (await dao.registeredPlayers(next.id)).single;
    expect((reg.entry.paid, reg.deck!.name), (true, 'Zombie'));
    await db.close();
  });
}
