import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// Única instancia de la BD para toda la app.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.closeOnce);
  return db;
});

final playersDaoProvider = Provider((ref) => ref.watch(databaseProvider).playersDao);
final decksDaoProvider = Provider((ref) => ref.watch(databaseProvider).decksDao);
final seasonsDaoProvider = Provider((ref) => ref.watch(databaseProvider).seasonsDao);
final tournamentsDaoProvider =
    Provider((ref) => ref.watch(databaseProvider).tournamentsDao);
final rankingDaoProvider = Provider((ref) => ref.watch(databaseProvider).rankingDao);
