import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../core/auth/auth_providers.dart';
import 'auth_pages.dart';

/// La app solo se usa con sesión iniciada: sin sesión se muestra la pantalla
/// de inicio (Iniciar sesión / Crear cuenta) y no se puede entrar a nada más.
/// La sesión se guarda en el teléfono y funciona sin conexión.
class StartGate extends ConsumerWidget {
  const StartGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    // Mientras se lee la sesión guardada: el logo.
    if (session.isLoading && !session.hasValue) {
      return const Scaffold(body: Center(child: GlowLogo(size: 120)));
    }
    if (session.value != null) return child;
    // Navigator propio: las pantallas de iniciar sesión se abren encima.
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const StartScreen()),
    );
  }
}

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 24),
                  Text(
                    'Necesitas una cuenta para usar la app. Para crearla o iniciar sesión '
                    'hace falta conexión (con VPN); después funciona sin conexión.',
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
