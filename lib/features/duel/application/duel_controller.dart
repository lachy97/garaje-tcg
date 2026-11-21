import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme.dart';
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

/// Temas de colores de la calculadora. La barra de vida usa siempre los
/// mismos colores (ver `lifeBarColor`).
enum DuelTheme {
  neon('Neón', AppPalette.dark),
  hielo(
    'Hielo',
    AppPalette(
      isDark: true,
      background: Color(0xFF040A14),
      surface: Color(0xFF0A1525),
      surfaceHigh: Color(0xFF102036),
      surfaceHighest: Color(0xFF152A45),
      neon: Color(0xFF6FD3FF),
      neonBright: Color(0xFFD4F3FF),
      leaf: Color(0xFF4FA3D1),
      moss: Color(0xFF2F6A8C),
      forest: Color(0xFF123150),
      outline: Color(0xFF26486B),
      outlineVariant: Color(0xFF172E47),
      textPrimary: Color(0xFFDCF1FF),
      textSecondary: Color(0xFF7FA3C2),
      textDisabled: Color(0xFF3C5672),
      draw: Color(0xFFE6C84F),
      loss: Color(0xFFFF5C5C),
      logo: Color(0xFFFFFFFF),
    ),
  ),
  faraon(
    'Faraón',
    AppPalette(
      isDark: true,
      background: Color(0xFF0D0903),
      surface: Color(0xFF191207),
      surfaceHigh: Color(0xFF231A0B),
      surfaceHighest: Color(0xFF2E2310),
      neon: Color(0xFFF2C14E),
      neonBright: Color(0xFFFFE7A8),
      leaf: Color(0xFFC9973A),
      moss: Color(0xFF8A6A2A),
      forest: Color(0xFF3D2E12),
      outline: Color(0xFF5A4520),
      outlineVariant: Color(0xFF33270F),
      textPrimary: Color(0xFFFFF0CC),
      textSecondary: Color(0xFFBFA36B),
      textDisabled: Color(0xFF6B5A36),
      draw: Color(0xFFE6C84F),
      loss: Color(0xFFFF5C5C),
      logo: Color(0xFFFFFFFF),
    ),
  ),
  abismo(
    'Abismo',
    AppPalette(
      isDark: true,
      background: Color(0xFF090512),
      surface: Color(0xFF140B22),
      surfaceHigh: Color(0xFF1C1030),
      surfaceHighest: Color(0xFF26163F),
      neon: Color(0xFFC983FF),
      neonBright: Color(0xFFEFD8FF),
      leaf: Color(0xFF9B5ED1),
      moss: Color(0xFF6A3F94),
      forest: Color(0xFF331A52),
      outline: Color(0xFF4B2C70),
      outlineVariant: Color(0xFF2A1842),
      textPrimary: Color(0xFFF1E3FF),
      textSecondary: Color(0xFFA78CC4),
      textDisabled: Color(0xFF5B4674),
      draw: Color(0xFFE6C84F),
      loss: Color(0xFFFF5C5C),
      logo: Color(0xFFFFFFFF),
    ),
  ),
  papel(
    'Papel',
    AppPalette(
      isDark: false,
      background: Color(0xFFF6F4EE),
      surface: Color(0xFFFFFFFF),
      surfaceHigh: Color(0xFFEDEAE1),
      surfaceHighest: Color(0xFFE2DED2),
      neon: Color(0xFF1D3F73),
      neonBright: Color(0xFF0F2547),
      leaf: Color(0xFF2F5C99),
      moss: Color(0xFF8DA0BD),
      forest: Color(0xFFD6E0F0),
      outline: Color(0xFFC4CBD6),
      outlineVariant: Color(0xFFDDE2EA),
      textPrimary: Color(0xFF16233A),
      textSecondary: Color(0xFF55627A),
      textDisabled: Color(0xFFA2ABBA),
      draw: Color(0xFFA87400),
      loss: Color(0xFFC62828),
      logo: Color(0xFF111111),
    ),
  );

  const DuelTheme(this.label, this.palette);

  final String label;
  final AppPalette palette;
}

/// Tema elegido. Es un ajuste del teléfono (no un dato de la partida): se
/// recuerda para la próxima vez.
class DuelThemeController extends Notifier<DuelTheme> {
  static const _key = 'duel.theme';

  @override
  DuelTheme build() {
    SharedPreferences.getInstance()
        .then((p) {
          final v = DuelTheme.values.where((t) => t.name == p.getString(_key)).firstOrNull;
          if (v != null && ref.mounted && state != v) state = v;
        })
        .catchError((_) {});
    return DuelTheme.neon;
  }

  Future<void> set(DuelTheme v) async {
    state = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, v.name);
    } catch (_) {}
  }
}

final duelThemeProvider = NotifierProvider<DuelThemeController, DuelTheme>(DuelThemeController.new);

final duelProvider = NotifierProvider<DuelController, DuelMatch?>(DuelController.new);
