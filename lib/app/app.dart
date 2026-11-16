import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/start_screen.dart';
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
          child: StartGate(child: child ?? const SizedBox()),
        ),
      ),
    );
  }
}

/// Versión demasiado vieja: la app queda bloqueada hasta instalar la última
/// (el servidor la exige; ver Ajustes → Servidor del administrador).
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: HttpAuthApi.updateRequired,
      builder: (context, required, _) => required ? const _UpdateRequiredScreen() : child,
    );
  }
}

class _UpdateRequiredScreen extends StatelessWidget {
  const _UpdateRequiredScreen();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update, size: 72, color: AppColors.neon),
                const SizedBox(height: 18),
                const Text('ACTUALIZACIÓN OBLIGATORIA',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 12),
                Text(
                  'Esta versión de Garage TCG ya no se puede usar. Instala la última versión '
                  '(está en el grupo de WhatsApp de la comunidad) y vuelve a abrir la app. '
                  'Tus datos no se pierden al actualizar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text('Versión instalada: compilación ${HttpAuthApi.appBuild}',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 20),
                // Por si el administrador quitó el mínimo: vuelve a probar.
                OutlinedButton.icon(
                  onPressed: () => HttpAuthApi.updateRequired.value = false,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Volver a comprobar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
