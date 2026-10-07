import 'package:drift/drift.dart';

import '../../utils/season_utils.dart';
import '../app_database.dart';
import '../tables.dart';

part 'seasons_dao.g.dart';

@DriftAccessor(tables: [Seasons])
class SeasonsDao extends DatabaseAccessor<AppDatabase> with _$SeasonsDaoMixin {
  SeasonsDao(super.attachedDatabase);

  /// Temporada (trimestre) que contiene [date]; la crea si no existe.
  Future<Season> seasonFor(DateTime date, {String game = kDefaultGame}) {
    final quarter = quarterOf(date);
    return transaction(() async {
      final existing = await (select(seasons)
            ..where((s) =>
                s.game.equals(game) &
                s.year.equals(date.year) &
                s.quarter.equals(quarter)))
          .getSingleOrNull();
      if (existing != null) return existing;
      final (start, end) = quarterRange(date.year, quarter);
      return into(seasons).insertReturning(SeasonsCompanion.insert(
        game: Value(game),
        year: date.year,
        quarter: quarter,
        startDate: start,
        endDate: end,
      ));
    });
  }

  Future<Season> current({String game = kDefaultGame}) =>
      seasonFor(DateTime.now(), game: game);

  Stream<List<Season>> watchAll({String game = kDefaultGame}) {
    return (select(seasons)
          ..where((s) => s.game.equals(game) & s.deletedAt.isNull())
          ..orderBy([
            (s) => OrderingTerm.desc(s.year),
            (s) => OrderingTerm.desc(s.quarter),
          ]))
        .watch();
  }

  /// Temporadas cuyo trimestre ya terminó pero siguen activas
  /// (la app las detecta al abrir y ofrece cerrarlas y archivar sus rankings).
  Future<List<Season>> pendingToClose({String game = kDefaultGame}) {
    final now = DateTime.now();
    return (select(seasons)
          ..where((s) =>
              s.game.equals(game) &
              s.status.equalsValue(SeasonStatus.active) &
              s.endDate.isSmallerThanValue(now)))
        .get();
  }
}
