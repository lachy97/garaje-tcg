/// Temporada = trimestre natural (Q1 ene-mar, Q2 abr-jun, Q3 jul-sep, Q4 oct-dic).
int quarterOf(DateTime date) => ((date.month - 1) ~/ 3) + 1;

/// Rango [inicio, fin] del trimestre. `fin` es el último instante del trimestre.
(DateTime start, DateTime end) quarterRange(int year, int quarter) {
  assert(quarter >= 1 && quarter <= 4);
  final start = DateTime(year, (quarter - 1) * 3 + 1, 1);
  final nextStart = DateTime(year, quarter * 3 + 1, 1); // DateTime normaliza mes 13
  final end = nextStart.subtract(const Duration(milliseconds: 1));
  return (start, end);
}

String seasonLabel(int year, int quarter) => 'T$quarter $year';
