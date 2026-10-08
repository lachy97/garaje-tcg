/// Reglas generales de formato. Dart puro, sin Flutter ni BD.
class TournamentRules {
  const TournamentRules._();

  static const int winPoints = 3;
  static const int drawPoints = 1;
  static const int lossPoints = 0;

  /// Rango de rondas Swiss que puede elegir el organizador.
  static const int minSwissRounds = 1;
  static const int maxSwissRounds = 15;

  /// Tiempo por ronda (minutos). Editable antes de empezar el torneo.
  static const int defaultRoundMinutes = 45;
  static const int minRoundMinutes = 5;
  static const int maxRoundMinutes = 120;

  /// Piso de MWP/OMW% (estándar: 33 %), evita que rivales muy malos hundan a alguien.
  static const double minMatchWinPct = 1 / 3;

  /// Jugadores mínimos para habilitar cada Top Cut.
  /// - Menos de 15 jugadores → Top 4 (con menos puntos).
  /// - 15+ → Top 8 · 24+ → Top 16 · 48+ → Top 32.
  static const Map<int, int> topCutMinPlayers = {4: 6, 8: 15, 16: 24, 32: 48};

  static List<int> get topCutSizes => topCutMinPlayers.keys.toList();

  /// Rondas Swiss sugeridas: ceil(log2 N), mínimo 3.
  /// ≤8 → 3 · 9-16 → 4 · 17-32 → 5 · 33-64 → 6 · 65-128 → 7
  static int suggestedSwissRounds(int playerCount) {
    if (playerCount <= 8) return 3;
    // (N-1).bitLength == ceil(log2 N) en enteros, sin errores de coma flotante.
    final r = (playerCount - 1).bitLength;
    return r < 3 ? 3 : r;
  }

  /// Top 4 solo aplica por debajo de 15; desde 15 el mínimo es Top 8.
  static List<int> allowedTopCuts(int playerCount) {
    if (playerCount < topCutMinPlayers[8]!) {
      return playerCount >= topCutMinPlayers[4]! ? const [4] : const [];
    }
    return [
      for (final MapEntry(key: size, value: min) in topCutMinPlayers.entries)
        if (size >= 8 && playerCount >= min) size,
    ];
  }

  /// Top Cut sugerido: el mayor permitido, o 0 si ninguno.
  static int suggestedTopCut(int playerCount) {
    final allowed = allowedTopCuts(playerCount);
    return allowed.isEmpty ? 0 : allowed.last;
  }
}
