import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../app/widgets/neon_table.dart';
import '../../../../core/db/app_database.dart';
import '../../application/tournament_service.dart';
import '../providers.dart';

/// Clasificación Swiss en vivo; al terminar, resultado final con puntos de ranking.
class StandingsTab extends ConsumerWidget {
  const StandingsTab({super.key, required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registered = ref.watch(registeredProvider(tournament.id));
    return AsyncView(
      value: registered,
      builder: (players) {
        final names = {for (final r in players) r.player.id: r.player.nickname};
        final decks = {for (final r in players) r.player.id: r.deck?.name};
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (tournament.status == TournamentStatus.finished)
              _FinalResults(tournament: tournament, names: names, decks: decks),
            _SwissStandings(tournament: tournament, names: names, decks: decks),
          ],
        );
      },
    );
  }
}

class _FinalResults extends ConsumerWidget {
  const _FinalResults({required this.tournament, required this.names, required this.decks});

  final Tournament tournament;
  final Map<String, String> names;
  final Map<String, String?> decks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(tournamentResultsProvider(tournament.id));
    return results.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('$e'),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Resultado final'),
          for (final r in list)
            NeonCard(
              glow: r.position == 1,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  _Position(r.position),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(names[r.playerId] ?? '?',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(decks[r.playerId] ?? 'Sin mazo',
                            style: const TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(
                    r.points > 0 ? '+${r.points}' : '0',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: r.points > 0 ? AppColors.neon : AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('pts', style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SwissStandings extends ConsumerWidget {
  const _SwissStandings({required this.tournament, required this.names, required this.decks});

  final Tournament tournament;
  final Map<String, String> names;
  final Map<String, String?> decks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standings = ref.watch(standingsProvider(tournament.id));
    return standings.when(
      loading: () => const Padding(
          padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('$e'),
      data: (list) {
        if (tournament.currentRound == 0) {
          return const Padding(
            padding: EdgeInsets.only(top: 48),
            child: EmptyState(
              icon: Icons.leaderboard_outlined,
              title: 'La clasificación aparece al jugar la ronda 1',
            ),
          );
        }
        final cut = tournament.topCutSize;
        String pct(double v) => (v * 100).toStringAsFixed(1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Clasificación Swiss'),
            NeonTable(
              columns: const [
                NeonColumn('#', width: 32, align: TextAlign.start),
                NeonColumn('Jugador', width: 120, align: TextAlign.start, flex: true),
                NeonColumn('V-D-E', width: 56),
                NeonColumn('Pts', width: 40),
                NeonColumn('OMW%', width: 54),
                NeonColumn('OOMW%', width: 60),
                NeonColumn('GW%', width: 50),
              ],
              rows: [
                for (final s in list)
                  NeonTableRow(
                    highlight: cut > 0 && s.rank <= cut && !s.dropped,
                    dim: s.dropped,
                    footer: cut > 0 && s.rank == cut ? _CutLine(cut: cut) : null,
                    cells: [
                      Text('${s.rank}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      _NameCell(
                        name: s.dropped
                            ? '${names[s.playerId] ?? '?'} (drop)'
                            : names[s.playerId] ?? '?',
                        deck: decks[s.playerId],
                        accent: cut > 0 && s.rank <= cut && !s.dropped,
                      ),
                      Text('${s.wins}-${s.losses}-${s.draws}'),
                      Text('${s.points}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, color: AppColors.neon)),
                      Text(pct(s.omw)),
                      Text(pct(s.oomw)),
                      Text(s.gwp == 0 ? '-' : pct(s.gwp)),
                    ],
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'Desempates en orden: Puntos → OMW% (rivales) → OOMW% (rivales de los '
                'rivales) → GW% (juegos ganados propios).',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.name, this.deck, this.accent = false});

  final String name;
  final String? deck;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: accent ? AppColors.neon : null)),
        if (deck != null)
          Text(deck!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _CutLine extends StatelessWidget {
  const _CutLine({required this.cut});

  final int cut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(color: AppColors.neon, boxShadow: AppColors.glow()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('CORTE TOP $cut',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.neon)),
          ),
          Expanded(
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(color: AppColors.neon, boxShadow: AppColors.glow()),
            ),
          ),
        ],
      ),
    );
  }
}

class _Position extends StatelessWidget {
  const _Position(this.position);

  final int position;

  @override
  Widget build(BuildContext context) {
    final medal = switch (position) {
      1 => AppColors.neon,
      2 => AppColors.neonBright,
      3 || 4 => AppColors.leaf,
      _ => AppColors.moss,
    };
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: medal, width: 1.5),
        boxShadow: position == 1 ? AppColors.glow(strength: 0.6) : null,
      ),
      child: Text('$position',
          style: TextStyle(fontWeight: FontWeight.w900, color: medal)),
    );
  }
}
