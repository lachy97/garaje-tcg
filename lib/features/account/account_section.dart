import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/auth/account.dart';
import '../../core/auth/auth_providers.dart';
import 'accounts_admin_page.dart';
import 'auth_pages.dart';

/// Ajustes → Cuenta: sin cuenta (modo local, como hasta ahora) o la cuenta
/// con su rol, la ficha vinculada y, para el administrador, las cuentas y
/// "Ver la app como".
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final simulated = ref.watch(authApiProvider).isSimulated;
    return NeonCard(
      child: AsyncView(
        value: session,
        builder: (s) => s == null ? _LoggedOut(simulated: simulated) : _LoggedIn(account: s.account),
      ),
    );
  }
}

class _LoggedOut extends StatelessWidget {
  const _LoggedOut({required this.simulated});

  final bool simulated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Sin cuenta', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'Este teléfono funciona en modo local, como hasta ahora: todo lo que '
          'hay en él se puede ver y editar.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        if (simulated) ...[
          const SizedBox(height: 8),
          Text(
            'Prueba: las cuentas se guardan solo en este teléfono hasta que '
            'exista el servidor.',
            style: TextStyle(color: AppColors.draw, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => openAuthPage<bool>(context, const LoginPage()),
          icon: const Icon(Icons.login),
          label: const Text('Iniciar sesión'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => openAuthPage<bool>(context, const RegisterPage()),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Crear cuenta'),
        ),
      ],
    );
  }
}

class _LoggedIn extends ConsumerWidget {
  const _LoggedIn({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = account.role == AppRole.admin;
    final preview = ref.watch(rolePreviewProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.nickname,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('@${account.username} · ${account.email}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            RoleChip(account.role),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          account.playerId == null
              ? 'Ficha de jugador: sin vincular (el administrador la vincula).'
              : 'Ficha de jugador vinculada.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => openAuthPage<void>(context, const AccountsAdminPage()),
            icon: const Icon(Icons.manage_accounts),
            label: const Text('Cuentas y roles'),
          ),
          const SizedBox(height: 8),
          Text('Ver la app como (para probar qué ve cada rol):',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('Yo (Administrador)'),
                selected: preview == null,
                onSelected: (_) => ref.read(rolePreviewProvider.notifier).set(null),
              ),
              for (final r in AppRole.values.where((r) => r != AppRole.admin))
                ChoiceChip(
                  label: Text(r.label),
                  selected: preview == r,
                  onSelected: (_) => ref.read(rolePreviewProvider.notifier).set(r),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => openAuthPage<bool>(
            context,
            ResetPasswordPage(initialIdentifier: account.username, lockedIdentifier: true),
          ),
          icon: const Icon(Icons.password),
          label: const Text('Cambiar contraseña'),
        ),
        TextButton.icon(
          onPressed: () async {
            final ok = await confirmDialog(
              context,
              title: 'Cerrar sesión',
              message: 'Para volver a usar la app tendrás que iniciar sesión (con conexión). '
                  'Los datos de torneos de este teléfono no se borran.',
              confirm: 'Cerrar sesión',
            );
            // Sin sesión no se usa la app: vuelve a la pantalla de inicio.
            if (ok && context.mounted) await ref.read(sessionProvider.notifier).logout();
          },
          icon: Icon(Icons.logout, color: AppColors.loss),
          label: Text('Cerrar sesión', style: TextStyle(color: AppColors.loss)),
        ),
      ],
    );
  }
}
