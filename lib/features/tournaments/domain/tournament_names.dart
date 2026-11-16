import '../../../core/db/app_database.dart';
import '../../../core/utils/season_utils.dart';

/// Nombre de los torneos: el número del torneo en su temporada y la
/// temporada, como los primeros de la comunidad: "Torneo #1 · T4 2026".
String tournamentName(int number, int year, int quarter) =>
    'Torneo #$number · ${seasonLabel(year, quarter)}';

final _number = RegExp(r'^Torneo #(\d+)\b');

/// Número de un nombre con ese formato (null si no lo tiene).
int? tournamentNumber(String name) {
  final m = _number.firstMatch(name.trim());
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Nombre por defecto de un torneo nuevo en la fecha [date]: el siguiente
/// número de su temporada (el mayor número ya usado + 1; si ninguno tiene
/// número, los torneos de la temporada + 1).
String nextTournamentName(Iterable<Tournament> all, DateTime date) {
  final q = quarterOf(date);
  final same = [
    for (final t in all)
      if (t.deletedAt == null && t.date.year == date.year && quarterOf(t.date) == q) t,
  ];
  var n = same.length;
  for (final t in same) {
    final k = tournamentNumber(t.name);
    if (k != null && k > n) n = k;
  }
  return tournamentName(n + 1, date.year, q);
}

/// Propuesta de nombres para los torneos terminados: por temporada y por
/// fecha, #1, #2… Los de [skip] (pruebas) no cuentan ni se renombran.
/// Devuelve solo los que cambian: (torneo, nombre nuevo).
List<(Tournament, String)> renameProposals(Iterable<Tournament> all, {Set<String> skip = const {}}) {
  final finished = [
    for (final t in all)
      if (t.deletedAt == null && t.status == TournamentStatus.finished && !skip.contains(t.id)) t,
  ]..sort((a, b) => a.date.compareTo(b.date));
  final counters = <(int, int), int>{};
  final out = <(Tournament, String)>[];
  for (final t in finished) {
    final key = (t.date.year, quarterOf(t.date));
    final n = (counters[key] ?? 0) + 1;
    counters[key] = n;
    final name = tournamentName(n, key.$1, key.$2);
    if (t.name.trim() != name) out.add((t, name));
  }
  return out;
}
