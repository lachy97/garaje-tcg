import '../../../core/db/enums.dart';

/// Modelos de dominio en Dart puro (sin Drift) usados por los motores
/// de pairings, standings y Top Cut. Se construyen desde la BD en el servicio.

/// Jugador inscrito, visto por el motor Swiss.
class SwissPlayer {
  const SwissPlayer(this.id, {this.dropped = false, this.dropRound});

  final String id;
  final bool dropped;

  /// Última ronda que jugó antes de retirarse (no se empareja en dropRound + 1).
  final int? dropRound;

  bool isActiveFor(int round) =>
      !dropped || (dropRound != null && round <= dropRound!);
}

/// Resultado de un match ya creado (reportado o pendiente).
class MatchRecord {
  const MatchRecord({
    required this.round,
    required this.player1Id,
    this.player2Id,
    this.result = MatchResult.pending,
    this.games1,
    this.gamesDraw,
    this.games2,
  });

  final int round;
  final String player1Id;
  final String? player2Id; // null = BYE
  final MatchResult result;

  /// Marcador en juegos (mejor de 3). null si no se registró (p. ej. datos antiguos).
  final int? games1;
  final int? gamesDraw;
  final int? games2;

  bool get isBye => player2Id == null;
}

/// Fila de la tabla de posiciones Swiss.
class Standing {
  const Standing({
    required this.playerId,
    required this.rank,
    required this.points,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.byes,
    required this.mwp,
    required this.omw,
    required this.oomw,
    required this.gwp,
    required this.dropped,
  });

  final String playerId;
  final int rank;
  final int points;
  final int wins; // incluye byes
  final int losses;
  final int draws;
  final int byes;

  /// Match-win % propio (piso 33 %).
  final double mwp;

  /// Promedio del MWP de los rivales (desempate 1).
  final double omw;

  /// Promedio del OMW% de los rivales (desempate 2).
  final double oomw;

  /// % de juegos ganados propio, piso 33 % (desempate 3).
  final double gwp;
  final bool dropped;

  int get matchesPlayed => wins + losses + draws;
  String get record => '$wins-$losses-$draws';
}

/// Emparejamiento producido por el motor Swiss.
class Pairing {
  const Pairing({required this.player1Id, this.player2Id, this.table});

  final String player1Id;
  final String? player2Id; // null = BYE
  final int? table;

  bool get isBye => player2Id == null;
}

class TournamentException implements Exception {
  const TournamentException(this.message);
  final String message;

  @override
  String toString() => message;
}
