import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../core/auth/auth_providers.dart';
import 'auth_pages.dart';

/// "Continuar sin cuenta" elegido en la pantalla de inicio. null = aún se lee.
/// Al cerrar sesión se vuelve a mostrar la pantalla de inicio.
class StartSkippedController extends Notifier<bool?> {
  static const _key = 'start.skipped';

  @override
  bool? build() {
    SharedPreferences.getInstance().then((prefs) {
      if (ref.mounted) state = prefs.getBool(_key) ?? false;
    });
    return null;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

final startSkippedProvider =
    NotifierProvider<StartSkippedController, bool?>(StartSkippedController.new);

/// Al abrir la app sin sesión: pantalla de inicio con Iniciar sesión / Crear
/// cuenta / Continuar sin cuenta (modo local, como hasta ahora).
class StartGate extends ConsumerWidget {
  const StartGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final skipped = ref.watch(startSkippedProvider);
    // Mientras se lee la sesión guardada: el logo.
    if ((session.isLoading && !session.hasValue) || skipped == null) {
      return const Scaffold(body: Center(child: GlowLogo(size: 120)));
    }
    // Si falla al leer la sesión no se bloquea a nadie.
    if (session.hasError || session.value != null || skipped) return child;
    // Navigator propio: las pantallas de iniciar sesión se abren encima.
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const StartScreen()),
    );
  }
}

class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: GlowLogo(size: 150)),
                  const SizedBox(height: 28),
                  Text(
                    'Bienvenido',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppColors.neonBright,
                      shadows: AppColors.textGlow(blur: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Entra con tu cuenta para ver el ranking, la tier list, tus torneos '
                    'y tu ficha de jugador.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () => openAuthPage<bool>(context, const LoginPage()),
                    icon: const Icon(Icons.login),
                    label: const Text('Iniciar sesión'),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => openAuthPage<bool>(context, const RegisterPage()),
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Crear cuenta'),
                  ),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => ref.read(startSkippedProvider.notifier).set(true),
                    child: const Text('Continuar sin cuenta'),
                  ),
                  Text(
                    'Para organizar torneos en este teléfono (con licencia). '
                    'Puedes iniciar sesión cuando quieras en Ajustes → Cuenta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
