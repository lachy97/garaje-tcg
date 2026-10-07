import '../../../core/db/enums.dart';

/// Marcador de un match al mejor de 3 (gana quien llega a 2 juegos).
///
/// Formato: `Jugador1 - Empates - Jugador2`, p. ej. `2-0-1`.
/// El ganador del match es quien ganó más juegos; si empatan en juegos,
/// el match es empate (caso `1-1-1`).
class GameScore {
  const GameScore(this.p1, this.draws, this.p2);

  final int p1;
  final int draws;
  final int p2;

  /// Únicos marcadores aceptados.
  static const List<GameScore> allowed = [
    GameScore(2, 0, 0),
    GameScore(2, 0, 1),
    GameScore(0, 0, 2),
    GameScore(1, 0, 2),
    GameScore(1, 1, 1),
  ];

  /// Marcadores aceptados en Top Cut (no hay empates).
  static List<GameScore> get allowedTopCut =>
      allowed.where((s) => s.result != MatchResult.draw).toList(growable: false);

  /// Un BYE se registra como 2-0-0.
  static const bye = GameScore(2, 0, 0);

  MatchResult get result => p1 > p2
      ? MatchResult.p1Win
      : p2 > p1
          ? MatchResult.p2Win
          : MatchResult.draw;

  bool get isValid => allowed.contains(this);
  bool get isValidForTopCut => isValid && result != MatchResult.draw;

  int get gamesPlayed => p1 + draws + p2;

  /// Marcador visto desde el otro jugador (útil en el perfil / historial).
  GameScore get swapped => GameScore(p2, draws, p1);

  /// Lee "2-0-1" (acepta espacios). Devuelve null si el formato no es válido.
  static GameScore? tryParse(String text) {
    final parts = text.split('-').map((s) => int.tryParse(s.trim())).toList();
    if (parts.length != 3 || parts.any((p) => p == null)) return null;
    return GameScore(parts[0]!, parts[1]!, parts[2]!);
  }

  @override
  bool operator ==(Object other) =>
      other is GameScore && other.p1 == p1 && other.draws == draws && other.p2 == p2;

  @override
  int get hashCode => Object.hash(p1, draws, p2);

  @override
  String toString() => '$p1-$draws-$p2';
}
