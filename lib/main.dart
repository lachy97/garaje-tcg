import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app/restartable_app.dart';
import 'core/auth/auth_providers.dart';
import 'core/auth/http_auth_api.dart';
import 'core/sync/control.dart';
import 'core/backup/pending_import.dart';
import 'core/security/screen_protection.dart';
import 'core/utils/app_paths.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  // Carpeta de documentos: para las imágenes guardadas con ruta relativa.
  try {
    await AppPaths.init();
  } catch (_) {
    // Sin ella solo faltarían las fotos propias de los mazos.
  }
  // Termina una importación que quedó pendiente (antes de abrir la BD).
  try {
    await PendingImport.applyIfAny();
  } catch (_) {
    // Si falla se sigue con los datos que había.
  }
  // Capturas permitidas: se quita el bloqueo (también para el próximo
  // arranque, que lo leía MainActivity).
  try {
    await ScreenProtection.setEnabled(false);
  } catch (_) {
    // MainActivity ya la activó al arrancar.
  }
  // Número de compilación (sin el prefijo de arquitectura de --split-per-abi:
  // 2045 y 1045 son la misma compilación 45) para la versión mínima.
  try {
    final info = await PackageInfo.fromPlatform();
    HttpAuthApi.appBuild = (int.tryParse(info.buildNumber) ?? 0) % 1000;
  } catch (_) {}
  // Identificador de este teléfono (para pasar un torneo a otro teléfono).
  try {
    await DeviceIdentity.init();
  } catch (_) {}
  // Entró sin cuenta la última vez: directo a la app (solo consulta).
  try {
    await VisitorMode.init();
  } catch (_) {}
  runApp(const RestartableApp());
}
