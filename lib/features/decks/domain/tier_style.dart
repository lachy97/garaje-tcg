import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deck_stats.dart';

/// Texto y color de la etiqueta de un tier (cuadro de la izquierda de la
/// tier list). Los edita el organizador; el cálculo del tier no cambia.
class TierStyle {
  const TierStyle(this.label, this.color);

  final String label;
  final Color color;

  /// Color del texto que se lee bien sobre [color].
  Color get textColor =>
      color.computeLuminance() > 0.32 ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);

  Map<String, Object> toJson() => {'label': label, 'color': color.toARGB32()};

  static TierStyle? fromJson(Object? j) {
    if (j is! Map) return null;
    final label = j['label'];
    final color = j['color'];
    if (label is! String || color is! int) return null;
    return TierStyle(label, Color(color));
  }
}

/// Colores por defecto, como la tier list de referencia (tonos apagados).
const kDefaultTierStyles = <DeckTier, TierStyle>{
  DeckTier.s: TierStyle('S', Color(0xFFD66A69)),
  DeckTier.a: TierStyle('A', Color(0xFFD6A06A)),
  DeckTier.b: TierStyle('B', Color(0xFFD4BD6A)),
  DeckTier.c: TierStyle('C', Color(0xFF8CC06A)),
  DeckTier.rogue: TierStyle('Rogue/Local', Color(0xFF8A86D6)),
};

/// Paleta para elegir el color de un tier.
const kTierPalette = <Color>[
  Color(0xFFD66A69), Color(0xFFFF7F7F), Color(0xFFE53935), // rojos
  Color(0xFFD6A06A), Color(0xFFFFBF7F), Color(0xFFFB8C00), // naranjas
  Color(0xFFD4BD6A), Color(0xFFFFDF7F), Color(0xFFFDD835), // amarillos
  Color(0xFF8CC06A), Color(0xFF7FFF7F), Color(0xFF8CF04C), // verdes
  Color(0xFF5DB3A0), Color(0xFF7FFFFF), Color(0xFF4FC3F7), // turquesas
  Color(0xFF6A7FD6), Color(0xFF7F7FFF), Color(0xFF5754AB), // azules / morado
  Color(0xFFB06AD6), Color(0xFFFF7FFF), Color(0xFFEC407A), // violetas / rosas
  Color(0xFFBDBDBD), Color(0xFF757575), Color(0xFFFFFFFF), // grises
];

TierStyle tierStyleOf(Map<DeckTier, TierStyle> styles, DeckTier t) =>
    styles[t] ?? kDefaultTierStyles[t]!;

/// Etiquetas de los tiers guardadas en el teléfono (SharedPreferences).
class TierStylesController extends Notifier<Map<DeckTier, TierStyle>> {
  static const _key = 'tier_styles_v1';

  @override
  Map<DeckTier, TierStyle> build() {
    _load();
    return kDefaultTierStyles;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || !ref.mounted) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      state = {
        for (final t in DeckTier.values)
          t: TierStyle.fromJson(map[t.name]) ?? kDefaultTierStyles[t]!,
      };
    } catch (_) {
      // Datos dañados: se quedan los valores por defecto.
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode({for (final e in state.entries) e.key.name: e.value.toJson()}));
  }

  Future<void> set(DeckTier tier, TierStyle style) async {
    state = {...state, tier: style};
    await _save();
  }

  Future<void> reset(DeckTier tier) => set(tier, kDefaultTierStyles[tier]!);
}

final tierStylesProvider =
    NotifierProvider<TierStylesController, Map<DeckTier, TierStyle>>(TierStylesController.new);
