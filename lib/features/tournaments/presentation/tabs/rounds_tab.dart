import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/tournaments_dao.dart';
import '../../../../core/db/database_provider.dart';
import '../../../decks/presentation/decks_page.dart';
import '../../application/tournament_service.dart';
import '../../domain/tournament_rules.dart';
import '../providers.dart';
import '../share_tournament.dart';
import 'first_round_pairing_page.dart';
import 'match_score_card.dart';
import 'pairing_editor.dart';
import 'play_alerts.dart';
import 'round_timer.dart';

/// Rondas: configuración (rondas Swiss / Top Cut), pairings, reporte de
/// resultados y botón para avanzar el torneo.
class RoundsTab extends ConsumerStatefulWidget {
  const RoundsTab({super.key, required this.tournament, this.readOnly = false});

  final Tournament tournament;

  /// Solo consulta (jugadores): sin configurar, reportar ni avanzar.
  final bool readOnly;

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
          // El tiempo de la ronda en juego queda fijo arriba (fuera del scroll).
          final timerRound =
              current != null && t.status != TournamentStatus.finished ? current : null;

          return Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    if (timerRound != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: RoundTimer(
                            key: ValueKey(timerRound.id),
                            round: timerRound,
                            minutes: t.roundMinutes,
                            readOnly: widget.readOnly),
                      ),
                    Expanded(
                      child: CustomScrollView(
                  slivers: [
                    if (t.status != TournamentStatus.finished && !widget.readOnly)
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
                        tournament: t,
                        round: selected,
                        isCurrent: selected.id == current?.id &&
                            t.status != TournamentStatus.finished,
                        names: names,
                        deckNames: deckNames,
                        readOnly: widget.readOnly,
                      ),
                    // espacio para que el botón flotante no tape la última tarjeta
                    const SliverToBoxAdapter(child: SizedBox(height: 104)),
                  ],
                ),
                    ),
                  ],
                ),
              ),
              if (!widget.readOnly)
              Positioned(
                right: 20,
                bottom: 20,
                child: SafeArea(
                  child: _AdvanceFab(
                    tournament: t,
                    currentRound: current,
                    activePlayers: players.where((p) => !p.entry.dropped).length,
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
            Icon(Icons.lock_outline, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${t.swissRounds} rondas Swiss · $topLabel · ${t.roundMinutes} min/ronda',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Text('Fijado',
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
          Text('Se puede cambiar hasta generar la ronda 1.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text('Rondas Swiss',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
          const Text('Top Cut', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 6),
          TopCutSelector(
            value: t.topCutSize,
            onChanged: (size) =>
                runGuarded(context, () => service.setTopCutSize(t.id, size)),
          ),
          if (topTooBig) ...[
            const SizedBox(height: 6),
            Text('Hay $active jugadores: no alcanzan para un Top ${t.topCutSize}.',
                style: TextStyle(color: AppColors.loss, fontSize: 12)),
          ],
          if (active > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Sugerencia para $active jugadores: $sugRounds rondas · '
              '${sugTop == 0 ? 'sin Top' : 'Top $sugTop'} (solo orientativa)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
    required this.tournament,
    required this.round,
    required this.isCurrent,
    required this.names,
    required this.deckNames,
    this.readOnly = false,
  });

  final Tournament tournament;
  final Round round;
  final bool readOnly;

  /// Ronda en juego y se puede llevar el torneo desde este teléfono.
  final bool isCurrent;
  final Map<String, String> names;
  final Map<String, String> deckNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(roundMatchesProvider(round.id));
    final title = round.phase == RoundPhase.swiss
        ? 'Ronda ${round.number}'
        : roundLabel(round);
    final editable = !readOnly &&
        TournamentService.canEditResults(tournament, round, isCurrent: isCurrent);
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
              fontSize: 20,
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
          Center(
            child: TextButton.icon(
              onPressed: () => shareRound(
                context,
                tournament: tournament,
                roundTitle: title,
                isTopCut: round.phase == RoundPhase.topCut,
                matches: list,
                names: names,
              ),
              icon: const Icon(Icons.share, size: 20),
              label: const Text('Compartir ronda'),
            ),
          ),
          if (isCurrent &&
              !readOnly &&
              round.phase == RoundPhase.swiss &&
              tournament.status == TournamentStatus.swiss)
            Center(
              child: TextButton.icon(
                onPressed: () => openPairingEditor(context, round: round, names: names),
                icon: const Icon(Icons.swap_horiz, size: 20),
                label: const Text('Cambiar cruces'),
              ),
            ),
          // Avisos desde los móviles: juez, resultados reportados, drops.
          if (isCurrent && !readOnly)
            PlayAlertsPanel(tournament: tournament, matches: list, names: names),
          // Ronda 1 sin resultados: rehacer los cruces importándolos de un texto.
          if (isCurrent &&
              !readOnly &&
              round.number == 1 &&
              round.phase == RoundPhase.swiss &&
              tournament.status == TournamentStatus.swiss &&
              list.every((m) => m.isBye || !m.result.isReported))
            Center(
              child: TextButton.icon(
                onPressed: () => _importFirstRound(context, ref),
                icon: const Icon(Icons.content_paste_go, size: 20),
                label: const Text('Importar cruces desde texto'),
              ),
            ),
          const SizedBox(height: 8),
          if (!isCurrent && editable)
            Padding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, 4),
              child: Text(
                'Ronda cerrada: puedes corregir resultados mientras dure el Swiss. '
                'La clasificación se recalcula; los cruces ya hechos no cambian.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          for (final m in list)
            MatchScoreCard(
              key: ValueKey(m.id),
              match: m,
              phase: round.phase,
              names: names,
              deckNames: deckNames,
              editable: editable && !m.isBye,
              canClear: isCurrent,
            ),
          if (isCurrent && !readOnly)
            Center(
              child: TextButton.icon(
                onPressed: () => _undoRound(context, ref),
                icon: Icon(Icons.undo, size: 20, color: AppColors.loss),
                label: Text('Deshacer ${title.toLowerCase()}',
                    style: TextStyle(color: AppColors.loss)),
              ),
            ),
        ]);
      },
    );
  }

  /// Reemplaza los cruces de la ronda 1 (aún sin resultados) por los de un
  /// texto: se deshace la ronda y se vuelve a generar con esos cruces.
  Future<void> _importFirstRound(BuildContext context, WidgetRef ref) async {
    final picked = await Navigator.of(context)
        .push<({List<(String, String?)> pairs, Map<String, int> tables})>(
      MaterialPageRoute(
        builder: (_) => FirstRoundPairingPage(
          tournament: tournament,
          startWithImport: true,
          actionLabel: 'REEMPLAZAR CRUCES',
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await runGuarded(context, () async {
      final ok = await confirmDialog(
        context,
        title: 'Reemplazar cruces de la ronda 1',
        message: 'Los cruces actuales de la ronda 1 se cambian por los importados '
            '(los que falten se emparejan al azar). El tiempo de ronda se reinicia.',
        confirm: 'Reemplazar',
      );
      if (!ok) throw const ActionCancelled();
      await ref.read(tournamentServiceProvider).replaceFirstRound(tournament.id,
          fixedPairs: picked.pairs, fixedTables: picked.tables);
    }, success: 'Cruces de la ronda 1 importados');
  }

  Future<void> _undoRound(BuildContext context, WidgetRef ref) async {
    final isFirstTop = round.phase == RoundPhase.topCut &&
        tournament.status == TournamentStatus.topCut &&
        round.bracketSize == tournament.topCutSize;
    final back = round.number == 1
        ? 'El torneo vuelve a la inscripción (se puede cambiar la configuración).'
        : isFirstTop
            ? 'El torneo vuelve al Swiss: la última ronda Swiss se reabre.'
            : 'Se reabre la ronda anterior para corregirla.';
    await runGuarded(context, () async {
      final ok = await confirmDialog(
        context,
        title: 'Deshacer ${roundLabel(round).toLowerCase()}',
        message: 'Se borran los cruces y todos los resultados de esta ronda.\n\n$back',
        confirm: 'Deshacer',
        danger: true,
      );
      if (!ok) throw const ActionCancelled();
      await ref.read(tournamentServiceProvider).undoLastRound(tournament.id);
    }, success: 'Ronda deshecha');
  }
}

// ───────────────────────── Botón de avanzar ─────────────────────────

/// Botón flotante con el texto de lo que hará ("Generar ronda 4", "Iniciar
/// Top 8", "Siguiente ronda del Top", "Finalizar torneo").
/// Siempre pide confirmación diciendo qué va a pasar.
class _AdvanceFab extends ConsumerWidget {
  const _AdvanceFab({
    required this.tournament,
    required this.currentRound,
    required this.activePlayers,
    required this.busy,
    required this.onRun,
  });

  final Tournament tournament;
  final Round? currentRound;
  final int activePlayers;
  final bool busy;
  final Future<void> Function(Future<void> Function() action, {String? success}) onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tournament;
    final service = ref.read(tournamentServiceProvider);
    final registered = ref.watch(registeredProvider(t.id)).value ?? const <RegisteredPlayer>[];

    late final String title;
    late final String message;
    // [fixed]: enfrentamientos definidos a mano (solo ronda 1).
    late final Future<void> Function(
        List<(String, String?)> fixed, Map<String, int> tables) step;
    var firstRound = false;
    String? success;
    IconData icon = Icons.chevron_right;

    switch (t.status) {
      case TournamentStatus.draft:
      case TournamentStatus.swiss:
        if (t.currentRound < t.swissRounds) {
          final n = t.currentRound + 1;
          title = 'Generar ronda $n';
          // Avisos antes de cerrar inscripciones (no impiden empezar).
          final noDeck = registered.where((r) => r.deck == null).length;
          final unpaid = registered.where((r) => !r.entry.paid).length;
          final warnings = [
            if (noDeck > 0) '⚠ $noDeck jugador(es) sin mazo.',
            if (unpaid > 0) '⚠ $unpaid jugador(es) sin pagar el cover.',
          ];
          message = n == 1
              ? 'Se cierran las inscripciones y se generan los cruces de la ronda 1.\n\n'
                  'La configuración queda fija: ${t.swissRounds} rondas Swiss · '
                  '${t.topCutSize == 0 ? 'sin Top Cut' : 'Top ${t.topCutSize}'}.'
                  '${warnings.isEmpty ? '' : '\n\n${warnings.join('\n')}'}'
              : 'Se generan los cruces de la ronda $n de ${t.swissRounds}.';
          success = 'Ronda $n generada';
          firstRound = n == 1;
          step = (fixed, tables) async {
            final out = await service.generateNextSwissRound(t.id,
                fixedPairs: fixed, fixedTables: tables);
            if (out.rematches > 0 && context.mounted) {
              showMessage(context,
                  'Aviso: ${out.rematches} cruce(s) repetidos (no había otra opción).');
            }
          };
        } else {
          final size = TournamentRules.effectiveTopCut(t.topCutSize, activePlayers);
          final reduced = t.topCutSize != 0 && size != t.topCutSize;
          final why = reduced
              ? 'Por los drops solo quedan $activePlayers jugadores activos, '
                  'no alcanzan para el Top ${t.topCutSize}. '
              : '';
          if (size == 0) {
            title = 'Finalizar torneo';
            message = '${why}Se cierra el Swiss y se guardan las posiciones finales.';
            success = 'Torneo terminado.';
            icon = Icons.flag;
          } else {
            title = 'Iniciar Top $size';
            message = reduced
                ? '${why}Se juega un Top $size con los $size primeros. '
                    'Ya no se podrán jugar más rondas Swiss.'
                : 'Los $size primeros pasan al Top Cut. '
                    'Ya no se podrán jugar más rondas Swiss.';
            success = '¡Top $size generado!';
            icon = Icons.emoji_events;
          }
          step = (_, _) => service.startTopCut(t.id);
        }
      case TournamentStatus.topCut:
        final isFinal = currentRound?.bracketSize == 2;
        title = isFinal ? 'Finalizar torneo' : 'Siguiente ronda del Top';
        message = isFinal
            ? 'Se guardan las posiciones y se suman los puntos al ranking.'
            : 'Los ganadores pasan a la siguiente ronda.';
        success = isFinal ? '¡Torneo terminado! Puntos sumados al ranking.' : null;
        icon = isFinal ? Icons.flag : Icons.chevron_right;
        step = (_, _) => service.advanceTopCut(t.id);
      case TournamentStatus.finished:
        return const SizedBox.shrink();
    }

    return FloatingActionButton.extended(
      heroTag: 'advance-${t.id}',
      tooltip: title,
      onPressed: busy
          ? null
          : () => onRun(() async {
                var fixed = const <(String, String?)>[];
                var tables = const <String, int>{};
                if (firstRound && t.checkIn) {
                  // Check-in: quitar a los que no lo hicieron (no llegaron).
                  final missing = [
                    for (final r in registered)
                      if (!r.entry.checkedIn && !r.entry.dropped) r,
                  ];
                  if (missing.isNotEmpty) {
                    final remove = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        actionsOverflowButtonSpacing: 10,
                        title: Text('${missing.length} sin check-in'),
                        content: SingleChildScrollView(
                          child: Text('${missing.map((r) => r.player.nickname).join(', ')}\n\n'
                              '¿Los quito del torneo antes de generar la ronda 1?'),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Jugar con todos'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Quitarlos'),
                          ),
                        ],
                      ),
                    );
                    if (remove == null || !context.mounted) throw const ActionCancelled();
                    if (remove) {
                      final dao = ref.read(tournamentsDaoProvider);
                      for (final r in missing) {
                        await dao.unregisterPlayer(t.id, r.player.id);
                      }
                    }
                  }
                }
                if (firstRound) {
                  // Ronda 1: al azar, o definiendo los enfrentamientos a mano.
                  final mode = await _askFirstRound(context, title, message);
                  if (mode == null || !context.mounted) throw const ActionCancelled();
                  if (mode != _FirstRoundMode.random) {
                    final pairs = await Navigator.of(context)
                        .push<({List<(String, String?)> pairs, Map<String, int> tables})>(
                      MaterialPageRoute(
                        builder: (_) => FirstRoundPairingPage(
                          tournament: t,
                          startWithImport: mode == _FirstRoundMode.paste,
                        ),
                      ),
                    );
                    if (pairs == null) throw const ActionCancelled();
                    fixed = pairs.pairs;
                    tables = pairs.tables;
                  }
                } else {
                  final ok = await confirmDialog(context,
                      title: title, message: message, confirm: 'Continuar');
                  if (!ok) throw const ActionCancelled();
                }
                await step(fixed, tables);
              }, success: success),
      icon: busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 3, color: Theme.of(context).colorScheme.onPrimary))
          : Icon(icon, size: 28),
      label: Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
    );
  }
}

/// Cómo hacer los cruces de la ronda 1.
enum _FirstRoundMode { random, define, paste }

/// Antes de la ronda 1: al azar, definir a mano o importar desde texto
/// (null = cancelar).
Future<_FirstRoundMode?> _askFirstRound(BuildContext context, String title, String message) {
  Widget option(_FirstRoundMode mode, IconData icon, String label, String hint,
      {bool primary = false}) {
    final button = primary
        ? FilledButton.icon(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(mode),
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(mode),
            icon: Icon(icon),
            label: Text(label),
          );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          button,
          const SizedBox(height: 4),
          Text(hint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  return showDialog<_FirstRoundMode>(
    context: context,
    builder: (ctx) => AlertDialog(
      actionsOverflowButtonSpacing: 10,
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: 6),
            option(_FirstRoundMode.random, Icons.shuffle, 'Al azar',
                'Todos los cruces al azar.', primary: true),
            option(_FirstRoundMode.define, Icons.touch_app_outlined, 'Definir cruces',
                'Eliges algunos enfrentamientos; el resto, al azar.'),
            option(_FirstRoundMode.paste, Icons.content_paste_go, 'Importar texto',
                'Pegas los cruces (p. ej. de WhatsApp) y los revisas.'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
      ],
    ),
  );
}
