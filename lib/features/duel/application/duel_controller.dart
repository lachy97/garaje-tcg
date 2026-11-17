import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/duel.dart';

/// Partida de un torneo que se abre desde Mi mesa (null = duelo libre).
class DuelSetup {
  const DuelSetup({
    required this.tournamentId,
    required this.matchId,
    required this.iAmP1,
    required this.topCut,
    required this.opponent,
    this.playerId,
  });

  final String tournamentId;
  final String matchId;
  final bool iAmP1;
  final bool topCut;
  final String opponent;

  /// Mi ficha (para seguir el tiempo de la ronda desde Mi mesa).
  final String? playerId;
}

/// Cómo se ve la calculadora: en espejo (vertical, la mitad de arriba
/// girada para el rival) u horizontal (los dos lados de pie, uno junto al
/// otro).
enum DuelLayout { mirror, horizontal }

/// La partida en curso de la calculadora. Solo vive mientras la app está
/// abierta: no se guarda nada de las partidas.
class DuelController extends Notifier<DuelMatch?> {
  @override
  DuelMatch? build() => null;

  /// Abre la calculadora: sigue con la partida en memoria si es la misma
  /// (la misma mesa del torneo, o un duelo libre); si no, empieza de cero.
  void open(DuelSetup? setup) {
    final current = state;
    if (current != null && current.matchId == setup?.matchId) return;
    state = fresh(setup);
  }

  static DuelMatch fresh(DuelSetup? setup, {List<String>? names}) => DuelMatch(
    names: names ?? (setup == null ? ['Jugador 1', 'Jugador 2'] : ['Tú', setup.opponent]),
    tournamentId: setup?.tournamentId,
    matchId: setup?.matchId,
    iAmP1: setup?.iAmP1 ?? true,
    topCut: setup?.topCut ?? false,
  );

  /// Aplica un cambio y lo guarda.
  void act(void Function(DuelMatch m) change) {
    final current = state;
    if (current == null) return;
    final m = current.copy();
    change(m);
    state = m;
  }

  /// Nueva partida (misma mesa o duelo libre), con los mismos nombres.
  /// Reinicia la calculadora desde 0: LP, duelos, tiempos y registro (los
  /// nombres se quedan).
  void restart(DuelSetup? setup) {
    final names = state?.names;
    state = fresh(setup, names: names);
  }
}

/// Vista elegida (espejo u horizontal). Es un ajuste del teléfono, no un dato
/// de la partida: se recuerda para la próxima vez.
class DuelLayoutController extends Notifier<DuelLayout> {
  static const _key = 'duel.layout';

  @override
  DuelLayout build() {
    SharedPreferences.getInstance()
        .then((p) {
          final v = p.getString(_key);
          if (v == DuelLayout.horizontal.name && ref.mounted && state != DuelLayout.horizontal) {
            state = DuelLayout.horizontal;
          }
        })
        .catchError((_) {});
    return DuelLayout.mirror;
  }

  Future<void> set(DuelLayout v) async {
    state = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, v.name);
    } catch (_) {}
  }
}

final duelLayoutProvider = NotifierProvider<DuelLayoutController, DuelLayout>(DuelLayoutController.new);

final duelProvider = NotifierProvider<DuelController, DuelMatch?>(DuelController.new);
