import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/tournaments_dao.dart';
import '../../../../core/db/database_provider.dart';
import '../../../decks/presentation/deck_image.dart';
import '../../../decks/presentation/deck_picker.dart';
import '../../../players/presentation/players_page.dart';
import '../../application/tournament_service.dart';
import '../providers.dart';
import 'penalties.dart';

/// Inscripción: jugadores + mazo. Antes de la ronda 1 se inscribe normal;
/// durante el Swiss se puede inscribir tarde (las rondas perdidas cuentan como
/// derrotas) y retirar (drop) jugadores. Penalizaciones: menú de cada jugador.
class RegistrationTab extends ConsumerWidget {
  const RegistrationTab({super.key, required this.tournament});

  final Tournament tournament;

  bool get _open => tournament.status == TournamentStatus.draft;

  /// Inscripción tardía: durante el Swiss, si aún quedan rondas por generar.
  bool get _lateOpen =>
      tournament.status == TournamentStatus.swiss &&
      tournament.currentRound < tournament.swissRounds;

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
                    )
                  else if (_lateOpen)
                    OutlinedButton.icon(
                      onPressed: () => _openRegisterSheet(context, list, late: true),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Inscribir tarde'),
                    ),
                ],
              ),
            ),
            PenaltiesSection(
              tournament: tournament,
              names: {for (final r in list) r.player.id: r.player.nickname},
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

  void _openRegisterSheet(BuildContext context, List<RegisteredPlayer> current,
      {bool late = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RegisterSheet(
        tournament: tournament,
        late: late,
        alreadyIn: current.where((r) => r.entry.deletedAt == null).map((r) => r.player.id).toSet(),
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
    final finished = tournament.status == TournamentStatus.finished;
    // El mazo se elige en la inscripción, o después si aún no tiene (p. ej. tardíos).
    final canPickDeck = draft || (!finished && item.deck == null);
    final late = item.entry.lateRounds;

    return NeonCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: canPickDeck ? () => _pickDeck(context, ref) : null,
      child: Row(
        children: [
          if (item.deck != null)
            Opacity(
              opacity: dropped ? 0.4 : 1,
              child: DeckImage(
                  path: item.deck!.imagePath, name: item.deck!.name, width: 40),
            )
          else
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
                      : item.deck?.name ??
                          (canPickDeck ? 'Sin mazo · toca para asignar' : 'Sin mazo'),
                  style: TextStyle(
                    color: item.deck == null && !dropped
                        ? AppColors.draw
                        : AppColors.textSecondary,
                  ),
                ),
                if (late > 0)
                  Text('Inscripción tardía · entró en la ronda ${late + 1}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (draft)
            IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Quitar inscripción',
                  message: '¿Quitar a ${item.player.nickname} de este torneo? '
                      'El jugador no se borra de la app.',
                  confirm: 'Quitar',
                  danger: true,
                );
                if (ok && context.mounted) {
                  await runGuarded(
                      context, () => dao.unregisterPlayer(tournament.id, item.player.id));
                }
              },
            ),
          if (running && !dropped)
            TextButton(
              onPressed: () => runGuarded(context, () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Retirar jugador',
                  message: '${item.player.nickname} no será emparejado en las '
                      'próximas rondas. Sus resultados se mantienen.',
                  confirm: 'Retirar',
                  danger: true,
                );
                if (!ok) throw const ActionCancelled();
                await dao.dropPlayer(tournament.id, item.player.id, tournament.currentRound);
              }),
              child: const Text('Drop', style: TextStyle(color: AppColors.loss)),
            ),
          if (!draft)
            IconButton(
              tooltip: 'Penalización',
              icon: const Icon(Icons.gavel, size: 20, color: AppColors.textSecondary),
              onPressed: () => addPenaltyDialog(context, ref,
                  tournament: tournament, player: item.player),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDeck(BuildContext context, WidgetRef ref) async {
    final name = await showDeckPicker(context, current: item.deck?.name);
    if (name == null || name.isEmpty || !context.mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(tournamentsDaoProvider)
          .setPlayerDeck(tournament.id, item.player.id, name),
    );
  }
}

/// Hoja para inscribir varios jugadores de una vez (o crear uno nuevo).
class _RegisterSheet extends ConsumerStatefulWidget {
  const _RegisterSheet({required this.tournament, required this.alreadyIn, this.late = false});

  final Tournament tournament;
  final Set<String> alreadyIn;

  /// Inscripción tardía (Swiss empezado).
  final bool late;

  @override
  ConsumerState<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends ConsumerState<_RegisterSheet> {
  final _selected = <String>{};
  String _query = '';
  bool _saving = false;

  Future<void> _confirm() async {
    final t = widget.tournament;
    if (widget.late) {
      final missed = t.currentRound;
      final ok = await confirmDialog(
        context,
        title: 'Inscripción tardía',
        message: 'Entran en la ronda ${missed + 1}. Las $missed ronda(s) ya '
            'generadas cuentan como derrota 0-2 sin rival (0 puntos).',
        confirm: 'Inscribir',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    final ids = _selected.toList();
    final ok = await runGuarded(context, () async {
      if (widget.late) {
        await ref.read(tournamentServiceProvider).registerLate(t.id, ids);
      } else {
        final dao = ref.read(tournamentsDaoProvider);
        for (final id in ids) {
          await dao.registerPlayer(t.id, id);
        }
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      showMessage(context, '${ids.length} jugador(es) inscrito(s)');
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
                    child: Text(widget.late ? 'Inscripción tardía' : 'Inscribir jugadores',
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
