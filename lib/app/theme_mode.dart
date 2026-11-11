import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modo de color elegido en Ajustes → Apariencia (sistema, claro u oscuro).
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'ui.themeMode';

  @override
  ThemeMode build() {
    // Se lee de forma asíncrona; mientras tanto, el del sistema.
    SharedPreferences.getInstance().then((prefs) {
      final saved = ThemeMode.values.where((m) => m.name == prefs.getString(_key)).firstOrNull;
      if (saved != null && ref.mounted && saved != state) state = saved;
    });
    return ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
