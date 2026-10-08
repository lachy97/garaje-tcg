import 'dart:math';

import '../../../../core/db/enums.dart';
import '../models.dart';
import '../tournament_rules.dart';

class PairingOutcome {
  const PairingOutcome(this.pairings, {this.rematches = 0});

  /// Mesas en orden (mesa 1 = mejores puntuaciones). El BYE va al final.
  final List<Pairing> pairings;

  /// > 0 solo si era imposible evitar repetir rivales (torneos muy pequeños).
  final int rematches;
}

/// Motor de pairings Swiss.
///
/// 1. Ronda 1: orden aleatorio.
/// 2. Rondas siguientes: por puntos (desc); dentro del mismo grupo de puntos,
///    orden aleatorio (así no siempre se cruzan los mismos).
/// 3. Número impar: BYE al jugador de menor puntuación que aún no tuvo BYE.
/// 4. Backtracking: cada jugador se enfrenta al rival más cercano en la tabla
///    con quien no haya jugado. Si no hay solución sin repetir rivales,
///    se aplica un emparejamiento que minimiza repeticiones.
class SwissPairingEngine {
  SwissPairingEngine({Random? random, this.maxSteps = 50000})
      : _random = random ?? Random();

  final Random _random;

  /// Límite de pasos del backtracking por intento (protege teléfonos lentos).
  final int maxSteps;
  int _steps = 0;

  PairingOutcome pairRound({
    required int round,
    required List<SwissPlayer> players,
    required List<MatchRecord> previous,
  }) {
    final active = players.where((p) => p.isActiveFor(round)).map((p) => p.id).toList();
    if (active.length < 2) {
      throw const TournamentException('Se necesitan al menos 2 jugadores activos');
    }

    // Historial: rivales previos, BYEs y puntos
    final opponents = {for (final id in active) id: <String>{}};
    final hadBye = <String>{};
    final points = {for (final id in active) id: 0};
    for (final m in previous) {
      if (m.isBye) {
        hadBye.add(m.player1Id);
        if (m.result.isReported) _add(points, m.player1Id, TournamentRules.winPoints);
        continue;
      }
      opponents[m.player1Id]?.add(m.player2Id!);
      opponents[m.player2Id!]?.add(m.player1Id);
      switch (m.result) {
        case MatchResult.p1Win:
          _add(points, m.player1Id, TournamentRules.winPoints);
        case MatchResult.p2Win:
          _add(points, m.player2Id!, TournamentRules.winPoints);
        case MatchResult.draw:
          _add(points, m.player1Id, TournamentRules.drawPoints);
          _add(points, m.player2Id!, TournamentRules.drawPoints);
        case MatchResult.pending:
        case MatchResult.doubleLoss:
          break;
      }
    }

    // Orden: aleatorio y luego estable por puntos => aleatorio dentro de cada grupo
    final order = [...active]..shuffle(_random);
    _stableSortBy(order, (id) => -points[id]!);

    String? byePlayer;
    List<(String, String)>? pairs;

    if (order.length.isOdd) {
      // Candidatos al BYE: de abajo hacia arriba, primero los que no tuvieron BYE
      final candidates = [
        ...order.reversed.where((id) => !hadBye.contains(id)),
        ...order.reversed.where(hadBye.contains),
      ];
      for (final c in candidates) {
        final rest = [...order]..remove(c);
        final solved = _trySolve(rest, opponents);
        if (solved != null) {
          byePlayer = c;
          pairs = solved;
          break;
        }
      }
      if (pairs == null) {
        byePlayer = candidates.first;
        final rest = [...order]..remove(byePlayer);
        final greedy = _greedy(rest, opponents);
        return _build(greedy.$1, byePlayer, rematches: greedy.$2);
      }
    } else {
      pairs = _trySolve(order, opponents);
      if (pairs == null) {
        final greedy = _greedy(order, opponents);
        return _build(greedy.$1, null, rematches: greedy.$2);
      }
    }
    return _build(pairs, byePlayer);
  }

  PairingOutcome _build(List<(String, String)> pairs, String? bye, {int rematches = 0}) {
    var table = 1;
    return PairingOutcome([
      for (final (a, b) in pairs) Pairing(player1Id: a, player2Id: b, table: table++),
      if (bye != null) Pairing(player1Id: bye),
    ], rematches: rematches);
  }

  /// Backtracking sin rematches. null si no hay solución (o se agotó el presupuesto).
  List<(String, String)>? _trySolve(List<String> pool, Map<String, Set<String>> opp) {
    _steps = 0;
    try {
      return _solve(pool, opp);
    } on _BudgetExceeded {
      return null;
    }
  }

  List<(String, String)>? _solve(List<String> pool, Map<String, Set<String>> opp) {
    if (pool.isEmpty) return const [];
    if (++_steps > maxSteps) throw const _BudgetExceeded();

    // Poda: si alguien ya jugó contra todos los que quedan, no hay solución.
    for (final p in pool) {
      final played = opp[p]!;
      if (pool.every((q) => q == p || played.contains(q))) return null;
    }

    final a = pool.first;
    for (var i = 1; i < pool.length; i++) {
      final b = pool[i];
      if (opp[a]!.contains(b)) continue;
      final rest = [...pool]
        ..removeAt(i)
        ..removeAt(0);
      final sub = _solve(rest, opp);
      if (sub != null) return [(a, b), ...sub];
    }
    return null;
  }

  /// Plan B: empareja en orden evitando rivales repetidos cuando se puede.
  (List<(String, String)>, int) _greedy(List<String> order, Map<String, Set<String>> opp) {
    final pool = [...order];
    final pairs = <(String, String)>[];
    var rematches = 0;
    while (pool.length >= 2) {
      final a = pool.removeAt(0);
      var idx = pool.indexWhere((b) => !opp[a]!.contains(b));
      if (idx < 0) {
        idx = 0;
        rematches++;
      }
      pairs.add((a, pool.removeAt(idx)));
    }
    return (pairs, rematches);
  }

  static void _add(Map<String, int> m, String id, int v) {
    if (m.containsKey(id)) m[id] = m[id]! + v;
  }

  /// Ordenación estable (List.sort de Dart no garantiza estabilidad).
  static void _stableSortBy(List<String> list, int Function(String) key) {
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((x, y) {
      final c = key(x.$2).compareTo(key(y.$2));
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
    for (var i = 0; i < list.length; i++) {
      list[i] = indexed[i].$2;
    }
  }
}

class _BudgetExceeded implements Exception {
  const _BudgetExceeded();
}
