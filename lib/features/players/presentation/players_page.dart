import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';

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
    final players = ref.watch(playersProvider(_query));
    return Scaffold(
      appBar: AppBar(title: const Text('JUGADORES')),
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
          Expanded(
            child: AsyncView(
              value: players,
              builder: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline,
                      title: 'Aún no hay jugadores',
                      subtitle: 'Pulsa "Jugador" para registrar el primero.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _PlayerTile(player: list[i]),
                    ),
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
  const _PlayerTile({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NeonCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: () => showPlayerForm(context, ref, player: player),
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
                Text(player.nickname, style: Theme.of(context).textTheme.titleMedium),
                if (player.fullName != null)
                  Text(player.fullName!,
                      style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Eliminar jugador',
                message:
                    '¿Eliminar a ${player.nickname}? Su historial de partidas se conserva.',
                confirm: 'Eliminar',
                danger: true,
              );
              if (ok) await ref.read(playersDaoProvider).softDelete(player.id);
            },
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

  @override
  void dispose() {
    _nick.dispose();
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final dao = ref.read(playersDaoProvider);
    final p = widget.player;
    if (p == null) {
      final created = await dao.create(
        nickname: _nick.text,
        fullName: _name.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, created);
    } else {
      String? clean(String s) => s.trim().isEmpty ? null : s.trim();
      await dao.edit(
        p.id,
        nickname: _nick.text,
        fullName: Value(clean(_name.text)),
        notes: Value(clean(_notes.text)),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notas (opcional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
