import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/license/license_gate.dart';
import 'router.dart';
import 'theme.dart';
import 'theme_mode.dart';

class GarajeTcgApp extends ConsumerWidget {
  const GarajeTcgApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Modo de color: el elegido en Ajustes o el del teléfono.
    final mode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);
    // MediaQuery propio por encima de MaterialApp: sin él no se puede leer
    // el modo (claro/oscuro) del teléfono aquí.
    return MediaQuery.fromView(
      view: View.of(context),
      child: Builder(builder: (context) => _build(context, mode, router)),
    );
  }

  Widget _build(BuildContext context, ThemeMode mode, GoRouter router) {
    final dark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final palette = dark ? AppPalette.dark : AppPalette.light;
    if (!identical(AppColors.palette, palette)) {
      AppColors.palette = palette;
      // Los colores son de la paleta activa: se redibuja todo una vez.
      WidgetsBinding.instance.addPostFrameCallback((_) => rebuildAllWidgets());
    }

    // Barras del sistema del color del fondo.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: palette.background,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: palette.background,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp.router(
      title: 'Garage TCG',
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      // Licencia: si no es válida se muestra la pantalla de bloqueo.
      builder: (context, child) => LicenseGate(child: child ?? const SizedBox()),
    );
  }
}
