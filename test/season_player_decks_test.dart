import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/app_database.dart';
import 'package:garaje_tcg/core/db/database_provider.dart';
import 'package:garaje_tcg/features/ranking/presentation/ranking_page.dart';
import 'package:garaje_tcg/features/tournaments/application/tournament_service.dart';
import 'package:garaje_tcg/features/tournaments/domain/game_score.dart';
void main() {
  test('mazos por jugador en la temporada', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final s = TournamentService(db);
    final ps = [for (var i = 0; i < 4; i++) await db.playersDao.create(nickname: 'J$i')];
    Future<Tournament> play(String deck0) async {
      final t = await db.tournamentsDao.createTournament(name: 'T', date: DateTime(2026, 11, 1), swissRounds: 1);
      for (var i = 0; i < 4; i++) { await db.tournamentsDao.registerPlayer(t.id, ps[i].id, deckName: i == 0 ? deck0 : 'Otro'); }
      await s.generateNextSwissRound(t.id);
      for (final m in await db.tournamentsDao.matchesOfTournament(t.id)) { if (!m.isBye) await s.reportScore(m.id, const GameScore(2, 0, 0)); }
      await s.startTopCut(t.id); // sin Top: finaliza
      return (await db.tournamentsDao.getById(t.id))!;
    }
    final t1 = await play('Snake-Eye');
    await play('Fire King');
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    final sub = c.listen(seasonPlayerDecksProvider(t1.seasonId), (_, _) {});
    final m = await c.read(seasonPlayerDecksProvider(t1.seasonId).future);
    expect(m[ps[0].id], containsAll(['Snake-Eye', 'Fire King']));
    sub.close();
  });
}
