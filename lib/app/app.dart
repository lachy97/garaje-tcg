import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/license/license_gate.dart';
import 'router.dart';
import 'theme.dart';

class GarajeTcgApp extends ConsumerWidget {
  const GarajeTcgApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Barras del sistema en negro para que la app se integre con el fondo.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: AppColors.background,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return MaterialApp.router(
      title: 'Garage TCG',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark, // la app es siempre oscura
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
      // Licencia: si no es válida se muestra la pantalla de bloqueo.
      builder: (context, child) => LicenseGate(child: child ?? const SizedBox()),
    );
  }
}
