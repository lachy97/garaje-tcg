import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/tournaments_dao.dart';
import '../../../../core/db/database_provider.dart';
import '../../../decks/presentation/decks_page.dart';
import '../../../players/presentation/players_page.dart';
import '../providers.dart';

/// Inscripción: jugadores + mazo. Abierta solo antes de la ronda 1;
/// después permite retirar (drop) jugadores.
class RegistrationTab extends ConsumerWidget {
  const RegistrationTab({super.key, required this.tournament});

  final Tournament tournament;

  bool get _open => tournament.status == TournamentStatus.draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registered = ref.watch(registeredProvider(tournament.id));
    return AsyncView(
      value: registered,
      builder: (list) {
        final noDeck = list.where((r) => r.deck == null).length;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${list.length} inscritos',
                            style: Theme.of(context).textTheme.titleMedium),
                        if (noDeck > 0)
                          Text('$noDeck sin mazo asignado',
                              style: const TextStyle(color: AppColors.draw, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (_open)
                    FilledButton.icon(
                      onPressed: () => _openRegisterSheet(context, list),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Inscribir'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(
                      icon: Icons.how_to_reg_outlined,
                      title: 'Nadie inscrito todavía',
                      subtitle: 'Pulsa "Inscribir" y elige a los jugadores.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: list.length,
                      itemBuilder: (_, i) =>
                          _RegisteredTile(tournament: tournament, item: list[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _openRegisterSheet(BuildContext context, List<RegisteredPlayer> current) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RegisterSheet(
        tournamentId: tournament.id,
        alreadyIn: current.map((r) => r.player.id).toSet(),
      ),
    );
  }
}

class _RegisteredTile extends ConsumerWidget {
  const _RegisteredTile({required this.tournament, required this.item});

  final Tournament tournament;
  final RegisteredPlayer item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dao = ref.read(tournamentsDaoProvider);
    final draft = tournament.status == TournamentStatus.draft;
    final running = tournament.status == TournamentStatus.swiss;
    final dropped = item.entry.dropped;

    return NeonCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: draft ? () => _pickDeck(context, ref) : null,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: dropped ? AppColors.surfaceHighest : AppColors.forest,
            foregroundColor: dropped ? AppColors.textDisabled : AppColors.neon,
            child: Text(item.player.nickname.characters.first.toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.player.nickname,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: dropped ? AppColors.textDisabled : null,
                        decoration: dropped ? TextDecoration.lineThrough : null,
                      ),
                ),
                Text(
                  dropped
                      ? 'Retirado tras la ronda ${item.entry.dropRound ?? '-'}'
                      : item.deck?.name ?? 'Sin mazo · toca para asignar',
                  style: TextStyle(
                    color: item.deck == null && !dropped
                        ? AppColors.draw
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (draft)
            IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
              onPressed: () => dao.unregisterPlayer(tournament.id, item.player.id),
            ),
          if (running && !dropped)
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Retirar jugador',
                  message: '${item.player.nickname} no será emparejado en las '
                      'próximas rondas. Sus resultados se mantienen.',
                  confirm: 'Retirar',
                  danger: true,
                );
                if (ok) {
                  await dao.dropPlayer(
                      tournament.id, item.player.id, tournament.currentRound);
                }
              },
              child: const Text('Drop', style: TextStyle(color: AppColors.loss)),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDeck(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => DeckPickerDialog(initial: item.deck?.name ?? ''),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(tournamentsDaoProvider)
          .setPlayerDeck(tournament.id, item.player.id, name),
    );
  }
}

/// Elegir o escribir un mazo, con autocompletado de los mazos existentes.
class DeckPickerDialog extends ConsumerStatefulWidget {
  const DeckPickerDialog({super.key, this.initial = ''});

  final String initial;

  @override
  ConsumerState<DeckPickerDialog> createState() => _DeckPickerDialogState();
}

class _DeckPickerDialogState extends ConsumerState<DeckPickerDialog> {
  late String _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).value ?? const <Deck>[];
    return AlertDialog(
      title: const Text('Mazo'),
      content: Autocomplete<String>(
        initialValue: TextEditingValue(text: widget.initial),
        optionsBuilder: (v) {
          final q = v.text.trim().toLowerCase();
          final names = decks.map((d) => d.name);
          return q.isEmpty ? names : names.where((n) => n.toLowerCase().contains(q));
        },
        onSelected: (v) => _value = v,
        fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
          controller: controller,
          focusNode: focus,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre del mazo',
            helperText: 'Si no existe, se crea',
          ),
          onChanged: (v) => _value = v,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _value.trim()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Hoja para inscribir varios jugadores de una vez (o crear uno nuevo).
class _RegisterSheet extends ConsumerStatefulWidget {
  const _RegisterSheet({required this.tournamentId, required this.alreadyIn});

  final String tournamentId;
  final Set<String> alreadyIn;

  @override
  ConsumerState<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends ConsumerState<_RegisterSheet> {
  final _selected = <String>{};
  String _query = '';
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    final dao = ref.read(tournamentsDaoProvider);
    for (final id in _selected) {
      await dao.registerPlayer(widget.tournamentId, id);
    }
    if (mounted) {
      showMessage(context, '${_selected.length} jugador(es) inscrito(s)');
      Navigator.pop(context);
    }
  }

  Future<void> _newPlayer() async {
    final created = await showPlayerForm(context, ref);
    if (created != null) setState(() => _selected.add(created.id));
  }

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(playersProvider(_query));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Inscribir jugadores',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  TextButton.icon(
                    onPressed: _newPlayer,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Nuevo'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar',
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Expanded(
              child: AsyncView(
                value: players,
                builder: (all) {
                  final list = all.where((p) => !widget.alreadyIn.contains(p.id)).toList();
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.people_outline,
                      title: 'No hay más jugadores para inscribir',
                      subtitle: 'Crea uno nuevo con el botón "Nuevo".',
                    );
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return CheckboxListTile(
                        value: _selected.contains(p.id),
                        activeColor: AppColors.neon,
                        checkColor: Colors.black,
                        title: Text(p.nickname),
                        subtitle: p.fullName == null ? null : Text(p.fullName!),
                        onChanged: (v) => setState(() {
                          if (v ?? false) {
                            _selected.add(p.id);
                          } else {
                            _selected.remove(p.id);
                          }
                        }),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selected.isEmpty || _saving ? null : _confirm,
                    child: Text('INSCRIBIR (${_selected.length})'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
