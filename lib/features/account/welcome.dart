import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../core/auth/account.dart';
import '../../core/auth/auth_providers.dart';

/// Bienvenida (una vez por cuenta) para jugadores y jueces: qué pueden ver,
/// cómo se vincula su ficha y para qué hace falta la VPN.
class WelcomeGate extends ConsumerStatefulWidget {
  const WelcomeGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends ConsumerState<WelcomeGate> {
  String? _checkedFor;

  Future<void> _maybeShow(Account account) async {
    if (_checkedFor == account.id) return;
    _checkedFor = account.id;
    if (account.role != AppRole.player && account.role != AppRole.judge) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'welcome.seen.${account.id}';
    if (prefs.getBool(key) ?? false) return;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WelcomeSheet(account: account),
    );
    await prefs.setBool(key, true);
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(sessionProvider).value?.account;
    if (account != null && _checkedFor != account.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow(account));
    }
    return widget.child;
  }
}

class _WelcomeSheet extends StatelessWidget {
  const _WelcomeSheet({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String title, String text) => ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.forest,
            foregroundColor: AppColors.neon,
            child: Icon(icon),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(text),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: GlowLogo(size: 96)),
            const SizedBox(height: 8),
            Text('¡Bienvenido, ${account.nickname}!',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.neon)),
            const SizedBox(height: 12),
            step(Icons.leaderboard_outlined, 'Ranking y tier list',
                'El ranking de la temporada y los mazos del momento, siempre al día.'),
            step(Icons.emoji_events_outlined, 'Tus torneos',
                'Los torneos en los que estás inscrito: cruces, mesa, tiempo de ronda y '
                    'clasificación en vivo.'),
            step(Icons.person_outline, 'Tu ficha',
                account.playerId == null
                    ? 'Cuando el administrador vincule tu cuenta con tu ficha verás tu '
                        'historial, mazos y rivales en "Mi ficha".'
                    : 'Tu historial, tus mazos y tus rivales, en "Mi ficha".'),
            step(Icons.vpn_lock_outlined, 'Conexión',
                'Desde Cuba el servidor responde con VPN. Sin conexión ves lo último que '
                    'bajó; arrastra hacia abajo para actualizar.'),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Empezar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
