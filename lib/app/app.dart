import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/start_screen.dart';
import '../features/license/license_gate.dart';
import '../core/auth/http_auth_api.dart';
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
      // Letra del teléfono: se respeta hasta un 130 % para que las pantallas
      // no se rompan con la letra más grande.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        // Sin sesión: primero la pantalla de inicio (iniciar sesión, crear
        // cuenta o seguir sin cuenta); después, la licencia.
        child: _UpdateBanner(
          child: StartGate(child: LicenseGate(child: child ?? const SizedBox())),
        ),
      ),
    );
  }
}

/// Aviso fijo arriba si el servidor exige una versión más nueva de la app.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: HttpAuthApi.updateRequired,
      builder: (context, required, _) => Column(
        children: [
          if (required)
            Material(
              color: AppColors.loss,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.system_update, color: Colors.white),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Hay una versión nueva de Garage TCG. Instálala para seguir '
                          'sincronizando, reportando e inscribiéndote.',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: required ? MediaQuery.removePadding(context: context, removeTop: true, child: child) : child,
          ),
        ],
      ),
    );
  }
}
