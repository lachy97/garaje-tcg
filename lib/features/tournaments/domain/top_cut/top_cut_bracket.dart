import '../../../../core/db/enums.dart';
import '../models.dart';

/// Match de Top Cut (a crear o ya jugado). [slot] = posición en el cuadro,
/// se guarda como número de mesa (1-based) para reconstruir el bracket.
class BracketMatch {
  const BracketMatch({
    required this.slot,
    required this.player1Id,
    required this.player2Id,
    this.isThirdPlace = false,
    this.result = MatchResult.pending,
  });

  final int slot;
  final String player1Id;
  final String player2Id;
  final bool isThirdPlace;
  final MatchResult result;

  String get winner => switch (result) {
        MatchResult.p1Win => player1Id,
        MatchResult.p2Win => player2Id,
        _ => throw const TournamentException(
            'En el Top Cut cada match necesita un ganador (sin empates).'),
      };

  String get loser => winner == player1Id ? player2Id : player1Id;
}

/// Cuadro de eliminación directa con siembra estándar (1 vs N).
/// La siembra hace que el 1 y el 2 solo puedan cruzarse en la final.
class TopCutBracket {
  const TopCutBracket._();

  static bool isValidSize(int n) => n >= 2 && (n & (n - 1)) == 0;

  /// Orden de siembra en el cuadro. 8 → [1,8,4,5,2,7,3,6].
  static List<int> seedOrder(int size) {
    assert(isValidSize(size));
    var order = [1, 2];
    while (order.length < size) {
      final n = order.length * 2;
      order = [for (final s in order) ...[s, n + 1 - s]];
    }
    return order;
  }

  /// Primera ronda. [seeds] = jugadores ordenados por standing Swiss (seed 1 primero).
  static List<BracketMatch> firstRound(List<String> seeds) {
    if (!isValidSize(seeds.length)) {
      throw TournamentException('Tamaño de Top Cut inválido: ${seeds.length}');
    }
    final order = seedOrder(seeds.length);
    return [
      for (var i = 0; i < order.length; i += 2)
        BracketMatch(
          slot: i ~/ 2 + 1,
          player1Id: seeds[order[i] - 1], // mejor seed como jugador 1
          player2Id: seeds[order[i + 1] - 1],
        ),
    ];
  }

  /// Siguiente ronda a partir de la anterior (ya reportada).
  /// Devuelve lista vacía si la ronda anterior era la final.
  /// Tras las semifinales añade la partida por el 3er puesto si [thirdPlaceMatch].
  static List<BracketMatch> nextRound(
    List<BracketMatch> previous, {
    required bool thirdPlaceMatch,
  }) {
    final main = previous.where((m) => !m.isThirdPlace).toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
    if (main.length <= 1) return const [];
    final winners = [for (final m in main) m.winner];
    final next = [
      for (var i = 0; i < winners.length; i += 2)
        BracketMatch(slot: i ~/ 2 + 1, player1Id: winners[i], player2Id: winners[i + 1]),
    ];
    if (main.length == 2 && thirdPlaceMatch) {
      next.add(BracketMatch(
        slot: 2,
        player1Id: main[0].loser,
        player2Id: main[1].loser,
        isThirdPlace: true,
      ));
    }
    return next;
  }

  /// Posiciones finales del torneo.
  ///
  /// - 1º campeón, 2º finalista.
  /// - 3º/4º: partida por el 3er puesto (o, si no hubo, standing Swiss).
  /// - Eliminados en una ronda con k matches → posiciones k+1 … 2k,
  ///   ordenados por standing Swiss (p. ej. cuartos: 5-8).
  /// - Resto de jugadores: a continuación, en orden Swiss.
  ///
  /// [rounds] en orden cronológico; [swissOrder] = todos los jugadores por standing.
  static Map<String, int> finalPositions({
    required List<List<BracketMatch>> rounds,
    required List<String> swissOrder,
  }) {
    final swissRank = {for (var i = 0; i < swissOrder.length; i++) swissOrder[i]: i};
    int bySwiss(String a, String b) =>
        (swissRank[a] ?? 1 << 30).compareTo(swissRank[b] ?? 1 << 30);

    final pos = <String, int>{};
    for (final round in rounds) {
      final main = round.where((m) => !m.isThirdPlace).toList();
      final k = main.length;
      if (k == 1) {
        pos[main.first.winner] = 1;
        pos[main.first.loser] = 2;
        final third = round.where((m) => m.isThirdPlace).firstOrNull;
        if (third != null) {
          pos[third.winner] = 3;
          pos[third.loser] = 4;
        }
        continue;
      }
      if (k == 2 && rounds.last.any((m) => m.isThirdPlace)) {
        continue; // 3º/4º los decide la partida por el 3er puesto
      }
      final losers = [for (final m in main) m.loser]..sort(bySwiss);
      for (var i = 0; i < losers.length; i++) {
        pos[losers[i]] = k + 1 + i;
      }
    }

    var next = pos.length + 1;
    for (final id in swissOrder) {
      if (!pos.containsKey(id)) pos[id] = next++;
    }
    return pos;
  }
}
