import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/auth/account.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/db/app_database.dart';
import '../players/presentation/players_page.dart' show playersProvider;
import 'auth_pages.dart';

/// Cuentas de la comunidad (solo administrador): rol, ficha de jugador
/// vinculada y verificación manual si el código no llegó.
final _accountsProvider = FutureProvider.autoDispose<List<Account>>((ref) async {
  final session = ref.watch(sessionProvider).value;
  if (session == null) return const [];
  return ref.read(authApiProvider).listAccounts(session);
});

class AccountsAdminPage extends ConsumerWidget {
  const AccountsAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(_accountsProvider);
    final players = ref.watch(playersProvider('')).value ?? const <Player>[];
    final names = {for (final p in players) p.id: p.nickname};
    return Scaffold(
      appBar: AppBar(title: const Text('CUENTAS Y ROLES')),
      body: AsyncView(
        value: accounts,
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.group_off, title: 'Todavía no hay cuentas')
            : ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  SectionLabel('${list.length} cuenta(s)'),
                  for (final a in list)
                    NeonCard(
                      onTap: () => _edit(context, ref, a, players),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${a.nickname} · @${a.username}',
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text(a.email,
                                    style: TextStyle(
                                        color: AppColors.textSecondary, fontSize: 12)),
                                Text(
                                  [
                                    if (!a.verified) 'Sin confirmar',
                                    a.playerId == null
                                        ? 'Sin ficha'
                                        : 'Ficha: ${names[a.playerId] ?? '(borrada)'}',
                                  ].join(' · '),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: a.verified ? AppColors.textSecondary : AppColors.draw),
                                ),
                              ],
                            ),
                          ),
                          RoleChip(a.role),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Account a, List<Player> players) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('@${a.username}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Cambiar rol'),
              subtitle: Text(a.role.label),
              onTap: () => Navigator.pop(ctx, 'role'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(a.playerId == null ? 'Vincular ficha de jugador' : 'Cambiar ficha vinculada'),
              onTap: () => Navigator.pop(ctx, 'link'),
            ),
            if (a.playerId != null)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Quitar ficha vinculada'),
                onTap: () => Navigator.pop(ctx, 'unlink'),
              ),
            if (!a.verified)
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text('Confirmar Gmail a mano'),
                subtitle: const Text('Si el código no le llega'),
                onTap: () => Navigator.pop(ctx, 'verify'),
              ),
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Código para cambiar la contraseña'),
              subtitle: const Text('Para mandárselo por WhatsApp si olvidó la contraseña'),
              onTap: () => Navigator.pop(ctx, 'resetcode'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final session = ref.read(sessionProvider).value;
    if (session == null) return;
    final api = ref.read(authApiProvider);

    Future<Account?> run(Future<Account> Function() f) async {
      try {
        return await f();
      } on AuthException catch (e) {
        if (context.mounted) showMessage(context, e.message, error: true);
      } catch (e) {
        if (context.mounted) showMessage(context, 'No se pudo conectar: $e', error: true);
      }
      return null;
    }

    if (action == 'resetcode') {
      String? code;
      try {
        code = await api.adminResetCode(session, accountId: a.id);
      } on AuthException catch (e) {
        if (context.mounted) showMessage(context, e.message, error: true);
      } catch (e) {
        if (context.mounted) showMessage(context, 'No se pudo conectar: $e', error: true);
      }
      if (code == null || !context.mounted) return;
      final text = 'Garage TCG · @${a.username}: tu código para poner una contraseña nueva es '
          '$code (vale 15 minutos). En la app: Iniciar sesión → Olvidé mi contraseña → '
          'Ya tengo un código.';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Código para @${a.username}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(code!,
                  style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 6,
                      color: AppColors.neon)),
              const SizedBox(height: 8),
              Text('Vale 15 minutos. Mándaselo al jugador por WhatsApp.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                showMessage(ctx, 'Mensaje copiado');
              },
              child: const Text('Copiar mensaje'),
            ),
            FilledButton.icon(
              onPressed: () => SharePlus.instance.share(ShareParams(text: text)),
              icon: const Icon(Icons.share),
              label: const Text('Compartir'),
            ),
          ],
        ),
      );
      return;
    }

    Account? updated;
    switch (action) {
      case 'role':
        final role = await showDialog<AppRole>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Rol'),
            children: [
              for (final r in AppRole.values)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, r),
                  child: Row(
                    children: [
                      Icon(r == a.role ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 18, color: AppColors.neon),
                      const SizedBox(width: 10),
                      Text(r.label),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (role == null || role == a.role) return;
        updated = await run(() => api.setRole(session, accountId: a.id, role: role));
      case 'link':
        if (!context.mounted) return;
        final player = await _pickPlayer(context, players, a);
        if (player == null) return;
        updated = await run(() => api.linkPlayer(session, accountId: a.id, playerId: player.id));
      case 'unlink':
        updated = await run(() => api.linkPlayer(session, accountId: a.id));
      case 'verify':
        updated = await run(() => api.verifyManually(session, accountId: a.id));
    }
    if (updated == null) return;
    await ref.read(sessionProvider.notifier).updateAccount(updated);
    ref.invalidate(_accountsProvider);
    if (context.mounted) showMessage(context, 'Cuenta actualizada');
  }

  /// Elige la ficha de jugador (búsqueda por apodo o nombre).
  Future<Player?> _pickPlayer(BuildContext context, List<Player> players, Account a) {
    return showModalBottomSheet<Player>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PlayerPicker(players: players, hint: a.nickname),
    );
  }
}

class _PlayerPicker extends StatefulWidget {
  const _PlayerPicker({required this.players, required this.hint});

  final List<Player> players;
  final String hint;

  @override
  State<_PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<_PlayerPicker> {
  late final _q = TextEditingController(text: widget.hint);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = [
      for (final p in widget.players)
        if (q.isEmpty ||
            p.nickname.toLowerCase().contains(q) ||
            (p.fullName ?? '').toLowerCase().contains(q))
          p,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _q,
              decoration: const InputDecoration(
                labelText: 'Buscar ficha',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('Ninguna ficha coincide'))
                : ListView(
                    children: [
                      for (final p in list)
                        ListTile(
                          title: Text(p.nickname),
                          subtitle: p.fullName == null ? null : Text(p.fullName!),
                          onTap: () => Navigator.pop(context, p),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
