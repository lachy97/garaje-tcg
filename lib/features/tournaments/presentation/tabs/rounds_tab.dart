import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/tournaments_dao.dart';
import '../../../decks/presentation/decks_page.dart';
import '../../application/tournament_service.dart';
import '../../domain/tournament_rules.dart';
import '../providers.dart';
import 'match_score_card.dart';
import 'round_timer.dart';

/// Rondas: configuración (rondas Swiss / Top Cut), pairings, reporte de
/// resultados y botón para avanzar el torneo.
class RoundsTab extends ConsumerStatefulWidget {
  const RoundsTab({super.key, required this.tournament});

  final Tournament tournament;

  @override
  ConsumerState<RoundsTab> createState() => _RoundsTabState();
}

class _RoundsTabState extends ConsumerState<RoundsTab> {
  String? _selectedRoundId; // null = la última
  bool _busy = false;

  Tournament get t => widget.tournament;

  @override
  Widget build(BuildContext context) {
    final rounds = ref.watch(roundsProvider(t.id));
    final registered = ref.watch(registeredProvider(t.id));
    final decks = ref.watch(decksProvider).value ?? const <Deck>[];

    return AsyncView(
      value: rounds,
      builder: (roundList) => AsyncView(
        value: registered,
        builder: (players) {
          final names = {for (final r in players) r.player.id: r.player.nickname};
          final deckNames = {for (final d in decks) d.id: d.name};
          final selected = roundList.isEmpty
              ? null
              : roundList.firstWhere((r) => r.id == _selectedRoundId,
                  orElse: () => roundList.last);
          final current = roundList.isEmpty ? null : roundList.last;

          return Stack(
            children: [
              Positioned.fill(
                child: CustomScrollView(
                  slivers: [
                    if (t.status != TournamentStatus.finished)
                      SliverToBoxAdapter(
                        child: _ConfigCard(tournament: t, players: players),
                      ),
                    if (roundList.isNotEmpty)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 56,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            children: [
                              for (final r in roundList)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(roundLabel(r)),
                                    selected: r.id == selected?.id,
                                    onSelected: (_) =>
                                        setState(() => _selectedRoundId = r.id),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (selected == null)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.grid_view,
                          title: 'Aún no hay rondas',
                          subtitle: 'Inscribe a los jugadores, revisa la configuración '
                              'y genera la ronda 1.',
                        ),
                      )
                    else
                      _MatchesSliver(
                        round: selected,
                        isCurrent: selected.id == current?.id &&
                            t.status != TournamentStatus.finished,
                        names: names,
                        deckNames: deckNames,
                        roundMinutes: t.roundMinutes,
                      ),
                    // espacio para que el botón flotante no tape la última tarjeta
                    const SliverToBoxAdapter(child: SizedBox(height: 104)),
                  ],
                ),
              ),
              Positioned(
                right: 20,
                bottom: 20,
                child: SafeArea(
                  child: _AdvanceFab(
                    tournament: t,
                    currentRound: current,
                    busy: _busy,
                    onRun: _run,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    final ok = await runGuarded(context, action, success: success);
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) _selectedRoundId = null; // saltar a la ronda nueva
      });
    }
  }
}

// ───────────────────────── Configuración ─────────────────────────

/// Rondas Swiss y Top Cut. Editables solo durante la inscripción; al generar la
/// ronda 1 quedan bloqueadas. La sugerencia de la app es solo informativa.
class _ConfigCard extends ConsumerWidget {
  const _ConfigCard({required this.tournament, required this.players});

  final Tournament tournament;
  final List<RegisteredPlayer> players;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tournament;
    final locked = t.status != TournamentStatus.draft;
    final service = ref.read(tournamentServiceProvider);
    final active = players.where((p) => !p.entry.dropped).length;
    final topLabel = t.topCutSize == 0 ? 'Sin Top Cut' : 'Top ${t.topCutSize}';

    if (locked) {
      return NeonCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${t.swissRounds} rondas Swiss · $topLabel · ${t.roundMinutes} min/ronda',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Text('Fijado',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    final sugRounds = TournamentRules.suggestedSwissRounds(active);
    final sugTop = TournamentRules.suggestedTopCut(active);
    final topTooBig = t.topCutSize > 0 && active > 0 && active < t.topCutSize;

    return NeonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Configuración del torneo',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const Text('Se puede cambiar hasta generar la ronda 1.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text('Rondas Swiss',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              NumberStepper(
                value: t.swissRounds,
                min: TournamentRules.minSwissRounds,
                max: TournamentRules.maxSwissRounds,
                onChanged: (v) =>
                    runGuarded(context, () => service.setSwissRounds(t.id, v)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text('Tiempo por ronda',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              NumberStepper(
                value: t.roundMinutes,
                min: TournamentRules.minRoundMinutes,
                max: TournamentRules.maxRoundMinutes,
                step: 5,
                suffix: 'min',
                onChanged: (v) =>
                    runGuarded(context, () => service.setRoundMinutes(t.id, v)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Top Cut', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          TopCutSelector(
            value: t.topCutSize,
            onChanged: (size) =>
                runGuarded(context, () => service.setTopCutSize(t.id, size)),
          ),
          if (topTooBig) ...[
            const SizedBox(height: 6),
            Text('Hay $active jugadores: no alcanzan para un Top ${t.topCutSize}.',
                style: const TextStyle(color: AppColors.loss, fontSize: 13)),
          ],
          if (active > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Sugerencia para $active jugadores: $sugRounds rondas · '
              '${sugTop == 0 ? 'sin Top' : 'Top $sugTop'} (solo orientativa)',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// Selector de Top Cut: Sin Top / Top 4 / 8 / 16 / 32.
class TopCutSelector extends StatelessWidget {
  const TopCutSelector({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final size in [0, ...TournamentRules.topCutSizes])
          ChoiceChip(
            label: Text(size == 0 ? 'Sin Top' : 'Top $size'),
            selected: value == size,
            onSelected: (_) => onChanged(size),
          ),
      ],
    );
  }
}

// ───────────────────────── Matches ─────────────────────────

class _MatchesSliver extends ConsumerWidget {
  const _MatchesSliver({
    required this.round,
    required this.isCurrent,
    required this.names,
    required this.deckNames,
    required this.roundMinutes,
  });

  final Round round;
  final bool isCurrent;
  final Map<String, String> names;
  final Map<String, String> deckNames;
  final int roundMinutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(roundMatchesProvider(round.id));
    final title = round.phase == RoundPhase.swiss
        ? 'Ronda : ${round.number}'
        : roundLabel(round);
    return matches.when(
      loading: () => const SliverToBoxAdapter(
          child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()))),
      error: (e, _) => SliverToBoxAdapter(child: Text('$e')),
      data: (list) {
        final pending = list.where((m) => !m.result.isReported).length;
        return SliverList.list(children: [
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.neon,
              shadows: AppColors.textGlow(blur: 10),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            pending == 0 ? 'Todos los resultados reportados' : 'Faltan $pending resultado(s)',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: pending == 0 ? AppColors.leaf : AppColors.textSecondary,
            ),
          ),
          if (isCurrent) RoundTimer(round: round, minutes: roundMinutes),
          const SizedBox(height: 8),
          for (final m in list)
            MatchScoreCard(
              key: ValueKey(m.id),
              match: m,
              phase: round.phase,
              names: names,
              deckNames: deckNames,
              editable: isCurrent && !m.isBye,
            ),
        ]);
      },
    );
  }
}

// ───────────────────────── Botón de avanzar ─────────────────────────

/// Botón flotante redondo (">") que hace avanzar el torneo:
/// generar ronda → iniciar Top → siguiente ronda del Top → finalizar.
/// Siempre pide confirmación diciendo qué va a pasar.
class _AdvanceFab extends ConsumerWidget {
  const _AdvanceFab({
    required this.tournament,
    required this.currentRound,
    required this.busy,
    required this.onRun,
  });

  final Tournament tournament;
  final Round? currentRound;
  final bool busy;
  final Future<void> Function(Future<void> Function() action, {String? success}) onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tournament;
    final service = ref.read(tournamentServiceProvider);

    late final String title;
    late final String message;
    late final Future<void> Function() step;
    String? success;
    IconData icon = Icons.chevron_right;

    switch (t.status) {
      case TournamentStatus.draft:
      case TournamentStatus.swiss:
        if (t.currentRound < t.swissRounds) {
          final n = t.currentRound + 1;
          title = 'Generar ronda $n';
          message = n == 1
              ? 'Se cierran las inscripciones y se generan los cruces de la ronda 1.\n\n'
                  'La configuración queda fija: ${t.swissRounds} rondas Swiss · '
                  '${t.topCutSize == 0 ? 'sin Top Cut' : 'Top ${t.topCutSize}'}.'
              : 'Se generan los cruces de la ronda $n de ${t.swissRounds}.';
          success = 'Ronda $n generada';
          step = () async {
            final out = await service.generateNextSwissRound(t.id);
            if (out.rematches > 0 && context.mounted) {
              showMessage(context,
                  'Aviso: ${out.rematches} cruce(s) repetidos (no había otra opción).');
            }
          };
        } else if (t.topCutSize == 0) {
          title = 'Finalizar torneo';
          message = 'Se cierra el Swiss y se guardan las posiciones finales.';
          success = 'Torneo terminado.';
          icon = Icons.flag;
          step = () => service.startTopCut(t.id);
        } else {
          title = 'Iniciar Top ${t.topCutSize}';
          message = 'Los ${t.topCutSize} primeros pasan al Top Cut. '
              'Ya no se podrán jugar más rondas Swiss.';
          success = '¡Top ${t.topCutSize} generado!';
          icon = Icons.emoji_events;
          step = () => service.startTopCut(t.id);
        }
      case TournamentStatus.topCut:
        final isFinal = currentRound?.bracketSize == 2;
        title = isFinal ? 'Finalizar torneo' : 'Siguiente ronda del Top';
        message = isFinal
            ? 'Se guardan las posiciones y se suman los puntos al ranking.'
            : 'Los ganadores pasan a la siguiente ronda.';
        success = isFinal ? '¡Torneo terminado! Puntos sumados al ranking.' : null;
        icon = isFinal ? Icons.flag : Icons.chevron_right;
        step = () => service.advanceTopCut(t.id);
      case TournamentStatus.finished:
        return const SizedBox.shrink();
    }

    return FloatingActionButton.large(
      heroTag: 'advance-${t.id}',
      tooltip: title,
      shape: const CircleBorder(),
      onPressed: busy
          ? null
          : () => onRun(() async {
                final ok = await confirmDialog(context,
                    title: title, message: message, confirm: 'Continuar');
                if (!ok) throw const ActionCancelled();
                await step();
              }, success: success),
      child: busy
          ? const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
          : Icon(icon, size: 40),
    );
  }
}
