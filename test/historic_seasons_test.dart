import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/app_database.dart';
import 'package:garaje_tcg/features/ranking/data/historic_seasons.dart';

void main() {
  test('datos de las tablas: puestos seguidos y sin repetir nombres', () {
    expect(historicSeasons.map((s) => s.rows.length), [46, 54, 72]);
    for (final s in historicSeasons) {
      expect([for (final r in s.rows) r.rank], [for (var i = 1; i <= s.rows.length; i++) i]);
      expect(s.rows.map((r) => r.name).toSet().length, s.rows.length);
      for (final r in s.rows) {
        expect(r.wins <= r.games, isTrue, reason: '${s.quarter} ${r.name}');
        expect(r.tournaments > 0, isTrue);
      }
    }
    // Totales de puntos de cada tabla (sumados de las imágenes).
    expect(historicSeasons[0].rows.fold<int>(0, (n, r) => n + r.points), 23000);
  });

  test('importar: temporadas cerradas, fichas propuestas y ranking global', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final javier = await db.playersDao.create(nickname: 'Javier');
    final lachy = await db.playersDao.create(nickname: 'Lachy Lawton', fullName: 'Franklin');
    final samurai = await db.playersDao.create(nickname: 'El Samurai');
    final players = await db.select(db.players).get();
    final proposal = proposeHistoricMatches(players);
    expect(proposal['JAVIER']?.id, javier.id);
    expect(proposal['LACHY(FRANKLIN)']?.id, lachy.id);
    expect(proposal['THE SAMURAI']?.id, samurai.id);
    expect(proposal['ERNESTO CACHARRO'], isNull, reason: 'ficha nueva');
    expect(proposal.containsKey('LACHY PROWA'), isFalse, reason: 'va con LACHY');

    final n = await importHistoricSeasons(db, {for (final e in proposal.entries) e.key: e.value?.id});
    expect(n, 46 + 54 + 72);
    // Otra vez: reemplaza (no duplica).
    await importHistoricSeasons(db, {for (final e in proposal.entries) e.key: e.value?.id});

    final seasons = await db.select(db.seasons).get();
    final t1 = seasons.firstWhere((s) => s.year == 2026 && s.quarter == 1);
    expect(t1.status, SeasonStatus.closed);
    final r1 = await db.rankingDao.seasonRanking(t1.id);
    expect(r1.length, 46);
    expect(r1.first.nickname, 'Javier');
    expect(r1.first.points, 3050);
    expect(r1.first.played, 70);
    expect(r1.firstWhere((r) => r.playerId == lachy.id).bestText, 'Top 8');

    final global = await db.rankingDao.globalRanking();
    final j = global.firstWhere((r) => r.playerId == javier.id);
    expect(j.points, 3050 + 2400 + 1400);
    expect(j.tournaments, 12 + 9 + 7);
    expect(j.bestText, '1º');
    expect(global.first.playerId, javier.id, reason: 'el que más puntos suma');
    // LACHY y LACHY PROWA son la misma ficha.
    final prowa = global.where((r) => r.nickname == 'Lachy').toList();
    expect(prowa.length, 1);
    expect(prowa.first.points, 0 + 400 + 800);
  });
}
