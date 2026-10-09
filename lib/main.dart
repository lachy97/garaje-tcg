import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/restartable_app.dart';
import 'core/backup/pending_import.dart';
import 'core/security/screen_protection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  // Termina una importación que quedó pendiente (antes de abrir la BD).
  try {
    await PendingImport.applyIfAny();
  } catch (_) {
    // Si falla se sigue con los datos que había.
  }
  // Bloqueo de capturas (activo salvo que el administrador lo quite).
  try {
    await ScreenProtection.apply(await ScreenProtection.isEnabled());
  } catch (_) {
    // MainActivity ya la activó al arrancar.
  }
  runApp(const RestartableApp());
}
