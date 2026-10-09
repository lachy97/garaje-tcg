import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bloqueo de capturas y grabación de pantalla (Android FLAG_SECURE).
///
/// Activo por defecto en toda la app. Solo el administrador (con la clave
/// desbloqueada con su PIN) puede desactivarlo en este teléfono. La preferencia
/// también la lee MainActivity al arrancar, para que la app quede protegida
/// desde el primer fotograma.
class ScreenProtection {
  const ScreenProtection._();

  static const _channel = MethodChannel('garage_tcg/device');

  /// Guardado al revés ("desactivado") para que sin valor quede ACTIVO.
  /// MainActivity lee "flutter.screen_protection_off".
  static const _keyOff = 'screen_protection_off';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_keyOff) ?? false);
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOff, !enabled);
    await apply(enabled);
  }

  /// Aplica el estado a la ventana de la app.
  static Future<void> apply(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': enabled});
    } on PlatformException {
      // Sin efecto si el sistema no lo permite.
    } on MissingPluginException {
      // Versión nativa antigua: sin efecto.
    }
  }
}
