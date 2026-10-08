/// Fila del ranking trimestral con todas sus estadísticas.
/// Dart puro: se construye desde la BD en RankingDao.
class RankingRow {
  const RankingRow({
    required this.playerId,
    required this.nickname,
    required this.points,
    required this.tournaments,
    required this.bestPosition,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.lastDeck,
    this.rank = 0,
  });

  final String playerId;
  final String nickname;
  final int points;
  final int tournaments;
  final int bestPosition;
  final int wins;
  final int losses;
  final int draws;
  final String? lastDeck;
  final int rank;

  int get played => wins + losses + draws;

  /// Victorias / partidas jugadas (los BYE no cuentan como partida).
  double get winrate => played == 0 ? 0 : wins / played;

  RankingRow copyWith({int? rank, int? wins, int? losses, int? draws, String? lastDeck}) =>
      RankingRow(
        playerId: playerId,
        nickname: nickname,
        points: points,
        tournaments: tournaments,
        bestPosition: bestPosition,
        wins: wins ?? this.wins,
        losses: losses ?? this.losses,
        draws: draws ?? this.draws,
        lastDeck: lastDeck ?? this.lastDeck,
        rank: rank ?? this.rank,
      );

  /// Criterios acordados: 1) puntos ↓, 2) mejor posición ↑, 3) winrate ↓,
  /// 4) menos torneos jugados ↑. Último recurso: nombre (orden estable).
  static int compare(RankingRow a, RankingRow b) {
    if (a.points != b.points) return b.points.compareTo(a.points);
    if (a.bestPosition != b.bestPosition) return a.bestPosition.compareTo(b.bestPosition);
    final wr = b.winrate - a.winrate;
    if (wr.abs() > 1e-9) return wr > 0 ? 1 : -1;
    if (a.tournaments != b.tournaments) return a.tournaments.compareTo(b.tournaments);
    return a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase());
  }

  /// Ordena y numera (1, 2, 3…).
  static List<RankingRow> sortAndRank(Iterable<RankingRow> rows) {
    final list = rows.toList()..sort(compare);
    return [for (var i = 0; i < list.length; i++) list[i].copyWith(rank: i + 1)];
  }
}
