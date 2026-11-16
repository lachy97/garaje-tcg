import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/app_database.dart';
import 'package:garaje_tcg/features/tournaments/domain/tournament_names.dart';

void main() {
  test('nombres "Torneo #N · T4 2026": siguiente número y renombrar terminados', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = db.tournamentsDao;
    Future<Tournament> make(String name, DateTime date, {bool finished = true}) async {
      final t = await dao.createTournament(name: name, date: date, swissRounds: 3);
      if (finished) {
        await (db.update(db.tournaments)..where((x) => x.id.equals(t.id)))
            .write(const TournamentsCompanion(status: Value(TournamentStatus.finished)));
      }
      return t;
    }

    await make('Torneo #1 · T4 2026', DateTime(2026, 10, 4));
    await make('Torneo #2 · T4 2026', DateTime(2026, 10, 18));
    final prueba = await make('Prueba piloto', DateTime(2026, 11, 14));
    await make('Torneo 15/11', DateTime(2026, 11, 15));
    await make('Torneo de septiembre', DateTime(2026, 9, 20));
    final all = await dao.watchAll().first;

    expect(nextTournamentName(all, DateTime(2026, 11, 22)), 'Torneo #5 · T4 2026');
    expect(nextTournamentName(all, DateTime(2027, 1, 10)), 'Torneo #1 · T1 2027');

    final names = {for (final (t, n) in renameProposals(all)) t.name: n};
    expect(names, {
      'Prueba piloto': 'Torneo #3 · T4 2026',
      'Torneo 15/11': 'Torneo #4 · T4 2026',
      'Torneo de septiembre': 'Torneo #1 · T3 2026',
    });
    // Sin la prueba: el del 15/11 pasa a ser el #3.
    final skip = {for (final (t, n) in renameProposals(all, skip: {prueba.id})) t.name: n};
    expect(skip['Torneo 15/11'], 'Torneo #3 · T4 2026');
    expect(skip.containsKey('Prueba piloto'), isFalse);
  });
}
