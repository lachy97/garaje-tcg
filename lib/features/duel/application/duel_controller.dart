import 'dart:convert';

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

/// La partida en curso de la calculadora. Se guarda en el teléfono en cada
/// cambio: si la app se cierra o se queda sin batería, se sigue igual.
class DuelController extends Notifier<DuelMatch?> {
  static const _key = 'duel.current';

  @override
  DuelMatch? build() => null;

  /// Abre la partida: la guardada si es la misma (la misma mesa del torneo,
  /// o un duelo libre), o una nueva.
  Future<void> open(DuelSetup? setup) async {
    DuelMatch? saved;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) saved = DuelMatch.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      saved = null;
    }
    if (saved != null && saved.matchId == setup?.matchId) {
      state = saved;
      return;
    }
    state = fresh(setup);
    await _save();
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
    _save();
  }

  /// Nueva partida (misma mesa o duelo libre), con los mismos nombres.
  void restart(DuelSetup? setup) {
    final names = state?.names;
    state = fresh(setup, names: names);
    _save();
  }

  Future<void> _save() async {
    final m = state;
    if (m == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(m.toJson()));
    } catch (_) {}
  }
}

final duelProvider = NotifierProvider<DuelController, DuelMatch?>(DuelController.new);
