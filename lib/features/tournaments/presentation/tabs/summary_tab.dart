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

/// Resumen de un torneo terminado (es lo que se ve al abrirlo), en tres
/// pestañas con icono: Participantes (puesto, mazo, récord, win % y puntos
/// de ranking), Deck Breakdown (dona de todo el torneo o del Top Cut) y
/// Listas (las del Top Cut entero).
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
                // Récord del torneo: cuenta el resultado de la clasificación.
                result: m.standingsResult ?? m.result,
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
                  // En el Top Cut cada mazo tiene su sector (sin "Otros").
                  groupSingles: false,
                );
          final points = {
            for (final r in ref.watch(tournamentResultsProvider(tournament.id)).value ??
                const <SeasonResult>[])
              r.playerId: r.points,
          };
          final listCut = cut > 0 ? cut : 4;
          return DefaultTabController(
            length: 3,
            child: Column(
              children: [
                TabBar(
                  labelColor: AppColors.neon,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.neon,
                  dividerColor: AppColors.outlineVariant,
                  tabs: [
                    Tab(icon: Tooltip(message: 'Participantes', child: Icon(Icons.groups))),
                    Tab(
                        icon: Tooltip(
                            message: 'Deck Breakdown', child: Icon(Icons.pie_chart_outline))),
                    Tab(icon: Tooltip(message: 'Listas', child: Icon(Icons.style_outlined))),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // 1) Participantes, con los puntos de ranking ganados.
                      ListView(
                        padding: const EdgeInsets.only(bottom: 40),
                        children: [
                          _Header(
                            title: 'Participantes',
                            onShare: () => exportParticipants(context,
                                tournament: tournament, report: report, points: points),
                          ),
                          ParticipantsTable(
                            lines: report.participants,
                            points: points,
                            onTapPlayer: (id) => context.push('/jugadores/$id'),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: Text(
                              'Récord de todo el torneo (Swiss y Top Cut). El BYE cuenta como '
                              'victoria; las rondas perdidas por inscribirse tarde, como derrota. '
                              'Pts = puntos de ranking.'
                              '${cut > 0 ? ' Con franja verde, el Top $cut.' : ''}',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      // 2) Deck Breakdown (de todos o del Top Cut).
                      _Breakdown(tournament: tournament, report: report, topReport: topReport),
                      // 3) Listas de mazos de todo el Top Cut.
                      ListView(
                        padding: const EdgeInsets.only(bottom: 40),
                        children: [
                          TopDeckListsSection(
                            tournamentId: tournament.id,
                            targets: [
                              for (final p in report.participants)
                                if (p.position != null && p.position! <= listCut)
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

/// Deck Breakdown: dona de mazos de todo el torneo o solo del Top Cut.
class _Breakdown extends StatefulWidget {
  const _Breakdown({required this.tournament, required this.report, this.topReport});

  final Tournament tournament;
  final TournamentReport report;
  final TournamentReport? topReport;

  @override
  State<_Breakdown> createState() => _BreakdownState();
}

class _BreakdownState extends State<_Breakdown> {
  bool _onlyTop = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final top = widget.topReport;
    final onlyTop = _onlyTop && top != null;
    // `onlyTop` implica top != null, pero Dart no promociona a través de un bool.
    final report = onlyTop ? top! : widget.report;
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        _Header(
          title: onlyTop ? 'Top Cut Deck Breakdown' : 'Tournament Deck Breakdown',
          onShare: () => _share(report, onlyTop),
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
                Padding(
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

  /// Pregunta si compartir con la leyenda (lista de mazos) o solo el gráfico.
  Future<void> _share(TournamentReport report, bool onlyTop) async {
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
        tournament: widget.tournament, report: report, showLegend: legend, topCut: onlyTop);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onShare});

  final String title;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: SectionLabel(title)),
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 4),
          child: TextButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.share, size: 20),
            label: const Text('Compartir'),
          ),
        ),
      ],
    );
  }
}
