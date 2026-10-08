/// Enums persistidos como TEXTO (no como índice) para que reordenarlos
/// o añadir valores nunca corrompa datos existentes.

/// Por ahora solo Yu-Gi-Oh!; el campo queda listo para otros juegos.
const kDefaultGame = 'ygo';

enum TournamentStatus { draft, swiss, topCut, finished }

enum RoundPhase { swiss, topCut }

enum RoundStatus { open, closed }

enum SeasonStatus { active, closed }

enum MatchResult {
  pending,
  p1Win,
  p2Win,
  draw,

  /// Se acabó el tiempo sin terminar el match: pierden los dos (0-0-0).
  /// Solo en Swiss; el organizador lo marca a mano.
  doubleLoss;

  bool get isReported => this != MatchResult.pending;
}
