import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/auth/account.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/http_auth_api.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/db/database_provider.dart';
import '../../ranking/domain/ranking_row.dart';
import '../../ranking/presentation/ranking_page.dart';
import '../../ranking/presentation/season_picker.dart';
import 'player_profile_page.dart';

/// Jugadores activos filtrados por texto ('' = todos).
final playersProvider =
    StreamProvider.autoDispose.family<List<Player>, String>((ref, query) {
  return ref.watch(playersDaoProvider).watchAll(query: query);
});

class PlayersPage extends ConsumerStatefulWidget {
  const PlayersPage({super.key});

  @override
  ConsumerState<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends ConsumerState<PlayersPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    // Sin permiso para ver a todos: la pestaña es "Mi perfil".
    final perms = ref.watch(permissionsProvider);
    if (!perms.canSeeAllPlayers) {
      final mine = perms.playerId;
      if (mine != null) return PlayerProfilePage(playerId: mine);
      return Scaffold(
        appBar: AppBar(title: const Text('MI PERFIL')),
        body: perms.visitor
            ? const EmptyState(
                icon: Icons.person_outline,
                title: 'Entraste sin cuenta',
                subtitle: 'Crea una cuenta o inicia sesión en Ajustes para tener tu ficha '
                    '(torneos, mazos y ranking). Las fichas de los demás se abren desde Datos → Ranking.',
              )
            : const EmptyState(
                icon: Icons.link_off,
                title: 'Tu cuenta aún no tiene ficha',
                subtitle: 'El administrador la vincula con tu ficha de jugador '
                    '(torneos, mazos y ranking).',
              ),
      );
    }
    final players = ref.watch(playersProvider(_query));
    // Total sin filtrar (para el contador aunque se esté buscando).
    final total = ref.watch(playersProvider('')).value?.length;
    final found = players.value?.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('JUGADORES'),
        actions: [
          // El perfil propio (organizadores y administración con ficha).
          if (perms.playerId != null)
            IconButton(
              tooltip: 'Mi perfil',
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => context.push('/jugadores/${perms.playerId}'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar jugador',
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          if (total != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              child: Row(
                children: [
                  Icon(Icons.people, size: 18, color: AppColors.neon),
                  const SizedBox(width: 8),
                  Text(
                    total == 1 ? '1 jugador registrado' : '$total jugadores registrados',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.neon),
                  ),
                  if (_query.isNotEmpty && found != null) ...[
                    const Spacer(),
                    Text('$found encontrado(s)',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
          Expanded(
            child: AsyncView(
              value: players,
              builder: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline,
                      title: 'Aún no hay jugadores',
                      subtitle: 'Pulsa "Jugador" para registrar el primero.',
                    )
                  : Builder(builder: (context) {
                      // Puesto en el ranking de la temporada actual (subtítulo).
                      final seasons = ref.watch(seasonListProvider).value;
                      final season = seasons == null || seasons.isEmpty ? null : pickSeason(seasons, null);
                      final rows = season == null
                          ? const <RankingRow>[]
                          : ref.watch(seasonRankingProvider(season.id)).value ?? const <RankingRow>[];
                      final byId = {
                        for (var i = 0; i < rows.length; i++) rows[i].playerId: (rows[i].rank > 0 ? rows[i].rank : i + 1, rows[i]),
                      };
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _PlayerTile(player: list[i], ranking: byId[list[i].id]),
                      );
                    }),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showPlayerForm(context, ref),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Jugador'),
      ),
    );
  }
}

class _PlayerTile extends ConsumerWidget {
  const _PlayerTile({required this.player, this.ranking});

  final Player player;

  /// Puesto y fila del ranking de la temporada actual (null: sin puntos).
  final (int, RankingRow)? ranking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NeonCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: () => context.push('/jugadores/${player.id}'),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.forest,
            foregroundColor: AppColors.neon,
            child: Text(player.nickname.characters.first.toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player.nickname,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  ranking == null
                      ? 'Sin torneos esta temporada'
                      : '${ranking!.$2.points == 0 ? 'Sin puntos' : '${ranking!.$1}º · ${ranking!.$2.points} pts'}'
                          '${ranking!.$2.lastDeck == null ? '' : ' · ${ranking!.$2.lastDeck}'}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          // Acciones en un menú (borrar no queda a un toque por accidente).
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            icon: Icon(Icons.more_vert, color: AppColors.textSecondary),
            onSelected: (v) async {
              if (v == 'edit') {
                await showPlayerForm(context, ref, player: player);
                return;
              }
              // Sin confirmación: se puede deshacer desde el aviso.
              final dao = ref.read(playersDaoProvider);
              await dao.softDelete(player.id);
              if (!context.mounted) return;
              showMessage(
                context,
                '${player.nickname} eliminado (su historial se conserva)',
                actionLabel: 'Deshacer',
                onAction: () => dao.restore(player.id),
              );
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar')),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: AppColors.loss),
                  title: Text('Eliminar', style: TextStyle(color: AppColors.loss)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Alta o edición de jugador. Devuelve el jugador creado (en alta).
Future<Player?> showPlayerForm(BuildContext context, WidgetRef ref, {Player? player}) {
  return showDialog<Player>(
    context: context,
    builder: (_) => _PlayerFormDialog(player: player),
  );
}

class _PlayerFormDialog extends ConsumerStatefulWidget {
  const _PlayerFormDialog({this.player});

  final Player? player;

  @override
  ConsumerState<_PlayerFormDialog> createState() => _PlayerFormDialogState();
}

class _PlayerFormDialogState extends ConsumerState<_PlayerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nick = TextEditingController(text: widget.player?.nickname ?? '');
  late final _name = TextEditingController(text: widget.player?.fullName ?? '');
  late final _notes = TextEditingController(text: widget.player?.notes ?? '');
  late final _konami = TextEditingController(text: widget.player?.konamiId ?? '');
  late final _phone = TextEditingController(text: widget.player?.phone ?? '');

  @override
  void dispose() {
    _nick.dispose();
    _name.dispose();
    _notes.dispose();
    _konami.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool _busy = false;

  /// El jugador (y la versión web) guarda en el servidor; el teléfono del
  /// organizador, en su base y lo sube al sincronizar.
  bool get _onServer => widget.player != null && ref.read(permissionsProvider).editsPlayersOnServer;

  bool get _boss {
    final perms = ref.read(permissionsProvider);
    return perms.isAdmin || perms.role == AppRole.organizer;
  }

  Future<void> _saveOnServer(Player p) async {
    final api = ref.read(authApiProvider);
    final session = ref.read(sessionProvider).value;
    if (api is! HttpAuthApi || session == null) {
      showMessage(context, 'Necesitas conexión con el servidor para guardar.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await api.request('POST', 'v1/players/${Uri.encodeComponent(p.id)}/profile', token: session.token, body: {
        'nickname': _nick.text.trim(),
        'fullName': _name.text.trim(),
        'konamiId': _konami.text.trim(),
        'phone': _phone.text.trim(),
        if (_boss) 'notes': _notes.text.trim(),
      });
      // Baja la ficha cambiada (y la cuenta, con el apodo nuevo).
      await ref.read(syncControllerProvider.notifier).sync();
      if (session.account.playerId == p.id) {
        unawaitedRefresh(ref);
      }
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Datos guardados');
      }
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final dao = ref.read(playersDaoProvider);
    final p = widget.player;
    if (p != null && _onServer) return _saveOnServer(p);
    if (p == null) {
      final created = await dao.create(
        nickname: _nick.text,
        fullName: _name.text,
        notes: _notes.text,
        konamiId: _konami.text,
        phone: _phone.text,
      );
      if (mounted) Navigator.pop(context, created);
    } else {
      String? clean(String s) => s.trim().isEmpty ? null : s.trim();
      await dao.edit(
        p.id,
        nickname: _nick.text,
        fullName: Value(clean(_name.text)),
        notes: Value(clean(_notes.text)),
        konamiId: Value(clean(_konami.text)),
        phone: Value(clean(_phone.text)),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      actionsOverflowButtonSpacing: 10,
      title: Text(widget.player == null ? 'Nuevo jugador' : 'Editar jugador'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nick,
                autofocus: widget.player == null,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nickname *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Escribe un nickname' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre (opcional)'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _konami,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Konami ID / COSSY ID (opcional)',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono / WhatsApp (opcional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              if (!_onServer || _boss) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notas (opcional)'),
              ),
              ],
              if (_onServer) ...[
                const SizedBox(height: 8),
                Text('Se guarda en el servidor: los resultados y estadísticas no cambian.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Vuelve a pedir la cuenta (apodo nuevo) sin esperar.
void unawaitedRefresh(WidgetRef ref) {
  ref.read(sessionProvider.notifier).refreshAccount().catchError((_) {});
}
