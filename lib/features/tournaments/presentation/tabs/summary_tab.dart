import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../../decklists/presentation/deck_list_editor_page.dart' show DeckListTarget;
import '../../../decklists/presentation/top_deck_lists_section.dart';
import '../../domain/tournament_report.dart';
import '../providers.dart';
import '../report/report_export.dart';
import '../report/report_widgets.dart';

/// Resumen de un torneo terminado: metagame (dona con los mazos) y
/// participantes (puesto, récord, % de victorias y mazo). Ambos se exportan
/// como imagen.
class SummaryTab extends ConsumerWidget {
  const SummaryTab({super.key, required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registered = ref.watch(registeredProvider(tournament.id));
    final matches = ref.watch(tournamentMatchesProvider(tournament.id));
    return AsyncView(
      value: registered,
      builder: (players) => AsyncView(
        value: matches,
        builder: (list) {
          final report = TournamentReport.build(
            entries: [
              for (final r in players)
                ReportEntry(
                  playerId: r.player.id,
                  name: r.player.nickname,
                  deck: r.deck?.name,
                  deckImage: r.deck?.imagePath,
                  position: r.entry.finalPosition,
                  lateRounds: r.entry.lateRounds,
                  dropped: r.entry.dropped,
                ),
            ],
            matches: [
              for (final m in list)
                ReportMatch(
                  player1Id: m.player1Id,
                  player2Id: m.player2Id,
                  result: m.result,
                  isBye: m.isBye,
                ),
            ],
            topCutSize: tournament.topCutSize,
          );
          if (report.players == 0) {
            return const EmptyState(icon: Icons.pie_chart_outline, title: 'Sin participantes');
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              NeonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tournamentInfoLine(tournament, report),
                        style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    MetaHeadline(meta: report.metagame),
                  ],
                ),
              ),
              TopDeckListsSection(
                tournamentId: tournament.id,
                targets: [
                  for (final p in report.participants)
                    if (p.position != null && p.position! <= 4)
                      DeckListTarget(
                        tournamentId: tournament.id,
                        tournamentName: tournament.name,
                        date: tournament.date,
                        playerId: p.playerId,
                        playerName: p.name,
                        position: p.position,
                        deckName: p.deck,
                      ),
                ],
              ),
              _Header(
                title: 'Metagame',
                onExport: () =>
                    exportMetagame(context, tournament: tournament, report: report),
              ),
              NeonCard(
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (_, c) => MetaDonutView(
                        chart: report.chart,
                        size: c.maxWidth.clamp(160.0, 300.0),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...metaLegendRows(report),
                    if (report.chart.any((d) => d.isOthers))
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('En OTROS, los mazos que jugó un solo jugador.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ),
                  ],
                ),
              ),
              _Header(
                title: 'Participantes',
                onExport: () =>
                    exportParticipants(context, tournament: tournament, report: report),
              ),
              ParticipantsTable(
                lines: report.participants,
                onTapPlayer: (id) => context.push('/jugadores/$id'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  'Récord de todo el torneo (Swiss y Top Cut). El BYE cuenta como '
                  'victoria; las rondas perdidas por inscribirse tarde, como derrota.'
                  '${tournament.topCutSize > 0 ? ' Con franja verde, el Top ${tournament.topCutSize}.' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onExport});

  final String title;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: SectionLabel(title)),
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 4),
          child: TextButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.ios_share, size: 20),
            label: const Text('Exportar'),
          ),
        ),
      ],
    );
  }
}
