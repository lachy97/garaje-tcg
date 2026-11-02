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
import 'standings_tab.dart' show FinalResults;

/// Resumen de un torneo terminado, en tres apartados:
/// 1. Puntos: los jugadores que suman puntos de ranking.
/// 2. Top y metagame: listas del Top 4 y la dona de mazos (de todos o solo
///    del Top Cut), exportable con o sin leyenda.
/// 3. Participantes: puesto, récord, % de victorias y mazo.
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
          final entries = [
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
          ];
          final reportMatches = [
            for (final m in list)
              ReportMatch(
                player1Id: m.player1Id,
                player2Id: m.player2Id,
                result: m.result,
                isBye: m.isBye,
              ),
          ];
          final report = TournamentReport.build(
            entries: entries,
            matches: reportMatches,
            topCutSize: tournament.topCutSize,
          );
          if (report.players == 0) {
            return const EmptyState(icon: Icons.pie_chart_outline, title: 'Sin participantes');
          }
          final names = {for (final r in players) r.player.id: r.player.nickname};
          final decks = {for (final r in players) r.player.id: r.deck?.name};
          final cut = tournament.topCutSize;
          final topReport = cut == 0
              ? null
              : TournamentReport.build(
                  entries: [
                    for (final e in entries)
                      if (e.position != null && e.position! <= cut) e,
                  ],
                  matches: reportMatches,
                  topCutSize: cut,
                );
          return DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(
                  labelColor: AppColors.neon,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.neon,
                  dividerColor: AppColors.outlineVariant,
                  labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  tabs: [
                    Tab(text: 'Puntos'),
                    Tab(text: 'Top y metagame'),
                    Tab(text: 'Participantes'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(
                        padding: const EdgeInsets.only(bottom: 40, top: 4),
                        children: [
                          FinalResults(
                            tournament: tournament,
                            names: names,
                            decks: decks,
                            onlyScoring: true,
                            showTitle: false,
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: Text('Solo los jugadores que suman puntos de ranking.',
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                      _TopAndMetagame(
                        tournament: tournament,
                        report: report,
                        topReport: topReport,
                      ),
                      ListView(
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
                          _Header(
                            title: 'Participantes',
                            onExport: () => exportParticipants(context,
                                tournament: tournament, report: report),
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
                              '${cut > 0 ? ' Con franja verde, el Top $cut.' : ''}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Listas del Top 4 y la dona de mazos (de todos o solo del Top Cut).
class _TopAndMetagame extends StatefulWidget {
  const _TopAndMetagame({required this.tournament, required this.report, this.topReport});

  final Tournament tournament;
  final TournamentReport report;
  final TournamentReport? topReport;

  @override
  State<_TopAndMetagame> createState() => _TopAndMetagameState();
}

class _TopAndMetagameState extends State<_TopAndMetagame> {
  bool _onlyTop = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final top = widget.topReport;
    final onlyTop = _onlyTop && top != null;
    // `onlyTop` implica top != null, pero Dart no promociona a través de un bool.
    final report = onlyTop ? top! : widget.report;
    final scope = onlyTop ? 'TOP ${t.topCutSize}' : null;
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        TopDeckListsSection(
          tournamentId: t.id,
          targets: [
            for (final p in widget.report.participants)
              if (p.position != null && p.position! <= 4)
                DeckListTarget(
                  tournamentId: t.id,
                  tournamentName: t.name,
                  date: t.date,
                  playerId: p.playerId,
                  playerName: p.name,
                  position: p.position,
                  deckName: p.deck,
                ),
          ],
        ),
        _Header(
          title: onlyTop ? 'Metagame del Top ${t.topCutSize}' : 'Metagame',
          onExport: () => _export(report, scope),
        ),
        if (top != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text('Todos (${widget.report.players})')),
                ButtonSegment(value: true, label: Text('Top ${t.topCutSize}')),
              ],
              selected: {onlyTop},
              onSelectionChanged: (v) => setState(() => _onlyTop = v.first),
            ),
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
      ],
    );
  }

  /// Pregunta si exportar con la leyenda (lista de mazos) o solo el gráfico.
  Future<void> _export(TournamentReport report, String? scope) async {
    final legend = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Con leyenda'),
              subtitle: const Text('Gráfico y la lista de mazos con jugadores y %'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.donut_large),
              title: const Text('Sin leyenda'),
              subtitle: const Text('Solo el gráfico, más grande'),
              onTap: () => Navigator.pop(ctx, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (legend == null || !mounted) return;
    await exportMetagame(context,
        tournament: widget.tournament, report: report, showLegend: legend, scope: scope);
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
