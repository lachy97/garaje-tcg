import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/export/export_models.dart';
import '../../../../app/export/export_sheet.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/table_export.dart';
import '../../../../core/db/app_database.dart';
import '../../../decks/presentation/deck_image.dart';
import '../../domain/tournament_report.dart';
import 'report_widgets.dart';

String _fileSafe(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

String tournamentInfoLine(Tournament t, TournamentReport r) => [
      DateFormat('dd/MM/yyyy').format(t.date),
      '${r.players} jugadores',
      '${t.swissRounds} rondas',
      if (t.topCutSize > 0) 'Top ${t.topCutSize}',
    ].join(' · ');

/// Exporta "Participantes": puesto, jugador, récord, % de victorias y mazo,
/// con la línea de metagame arriba (como la página de un torneo en TopDeck).
Future<void> exportParticipants(
  BuildContext context, {
  required Tournament tournament,
  required TournamentReport report,
  Map<String, int>? points,
}) {
  return AppColors.runDark(() => runExport<ParticipantLine>(
    context,
    ExportSpec(
      heading: '${tournament.name.toUpperCase()} · PARTICIPANTES',
      items: report.participants,
      summary: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tournamentInfoLine(tournament, report),
              style: TextStyle(fontSize: 17, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outline),
            ),
            child: MetaHeadline(meta: report.metagame, fontSize: 17),
          ),
        ],
      ),
      summaryHeightEstimate: 110,
      tableBuilder: (rows, width) => ParticipantsTable(
        lines: rows,
        width: width,
        points: points,
        fontSize: kExportFontSize,
        rowPadding: kExportRowPadding,
      ),
      legend: 'Récord de todo el torneo (Swiss y Top Cut) · BYE = victoria · '
          'Pts = puntos de ranking'
          '${tournament.topCutSize > 0 ? ' · En verde, el Top ${tournament.topCutSize}' : ''}',
      fileBase: 'participantes_${_fileSafe(tournament.name)}',
      shareText: '${tournament.name} · Participantes',
      rowHeightEstimate: 52,
      preload: _deckImages(report),
    ),
  ));
}

// ───────────────────────── Póster de metagame ─────────────────────────

const _kBg = 'assets/export/tierlist_bg.jpg';
const _kPad = 48.0;
const _kDonut = 640.0;
const _kDonutBig = 860.0;
const _kLegendFont = 22.0;

/// Imágenes de los mazos (y la de "Otros") para cargarlas antes de exportar.
List<ImageProvider> _deckImages(TournamentReport report) => [
      const AssetImage(kOthersImage),
      for (final path in {for (final d in report.metagame) d.imagePath})
        if (deckImageProvider(path) case final p?) p,
    ];

/// Comparte el Deck Breakdown (cuántos jugadores usaron cada mazo).
/// [showLegend]: con la lista de mazos debajo o solo el gráfico (más grande).
/// [topCut]: el gráfico es solo de los jugadores del Top Cut.
Future<void> exportMetagame(
  BuildContext context, {
  required Tournament tournament,
  required TournamentReport report,
  bool showLegend = true,
  bool topCut = false,
}) async {
  final images = await loadChartImages(report.chart);
  if (!context.mounted) {
    disposeChartImages(images);
    return;
  }
  final legendRows = (metaLegendRows(report).length / 2).ceil();
  try {
    await AppColors.runDark(() => runExport<DeckShare>(
      context,
      ExportSpec(
        heading: 'DECK BREAKDOWN · ${tournament.name.toUpperCase()}',
        items: report.metagame,
        page: MetagamePoster(
          tournament: tournament,
          report: report,
          images: images,
          showLegend: showLegend,
          topCut: topCut,
        ),
        contentWidth: MetagamePoster.width,
        summaryHeightEstimate: showLegend
            ? _kPad * 2 + 130 + 40 + _kDonut + 40 + legendRows * (_kLegendFont * 2.4) + 60
            : _kPad * 2 + 130 + 40 + _kDonutBig + 80,
        legend: '',
        fileBase: '${topCut ? 'top_cut' : 'tournament'}_deck_breakdown_'
            '${_fileSafe(tournament.name)}',
        shareText: '${tournament.name} · ${topCut ? 'Top Cut' : 'Tournament'} Deck Breakdown',
        preload: [const AssetImage(_kBg), ..._deckImages(report)],
      ),
    ));
  } finally {
    disposeChartImages(images);
  }
}

/// Póster "Tournament / Top Cut Deck Breakdown": dona con el % de cada mazo
/// y, si se pide, la leyenda completa.
class MetagamePoster extends StatelessWidget {
  const MetagamePoster({
    super.key,
    required this.tournament,
    required this.report,
    required this.images,
    this.showLegend = true,
    this.topCut = false,
  });

  final Tournament tournament;
  final TournamentReport report;
  final ChartImages images;
  final bool showLegend;

  /// Solo los jugadores del Top Cut.
  final bool topCut;

  static const width = 1080.0;

  @override
  Widget build(BuildContext context) {
    const title = Color(0xFFCFCFCF);
    const muted = Color(0xFF8E8E8E);
    final rows = metaLegendRows(report, fontSize: _kLegendFont);
    final half = (rows.length / 2).ceil();
    Widget column(Iterable<Widget> list) => Column(children: [...list]);
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Color(0xFF0B0B0D),
        image: DecorationImage(image: AssetImage(_kBg), fit: BoxFit.cover),
      ),
      padding: const EdgeInsets.fromLTRB(_kPad, 40, _kPad, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Siempre en una línea: se reduce si no cabe.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        topCut ? 'TOP CUT DECK BREAKDOWN' : 'TOURNAMENT DECK BREAKDOWN',
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 58,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: title,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'GARAGE TCG · ${tournament.name.toUpperCase()}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2, color: muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tournamentInfoLine(tournament, report),
                      style: const TextStyle(fontSize: 20, color: muted),
                    ),
                  ],
                ),
              ),
              Image.asset(BrandAssets.logo,
                  width: 120, height: 120, filterQuality: FilterQuality.high),
            ],
          ),
          const SizedBox(height: 40),
          Center(
            child: MetaDonut(
              chart: report.chart,
              images: images,
              size: showLegend ? _kDonut : _kDonutBig,
            ),
          ),
          const SizedBox(height: 40),
          if (showLegend) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: column(rows.take(half))),
                const SizedBox(width: 40),
                Expanded(child: column(rows.skip(half))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  showLegend
                      ? '${report.deckCount} mazos · jugadores por mazo y % del total · '
                          'en OTROS, los mazos con un solo jugador'
                      : '${report.deckCount} mazos',
                  style: const TextStyle(fontSize: 16, color: muted),
                ),
              ),
              Text(DateFormat('dd/MM/yyyy', 'es').format(tournament.date),
                  style: const TextStyle(fontSize: 16, color: muted)),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Mi torneo (jugador) ─────────────────────────

/// Tarjeta para compartir el resultado de un jugador: puesto, mazo, récord y
/// puntos de ranking ("2º de 12 · Snake-Eye · 3-2 · +300 pts").
Future<void> exportMyResult(
  BuildContext context, {
  required Tournament tournament,
  required TournamentReport report,
  required ParticipantLine line,
  int? points,
}) {
  return AppColors.runDark(() => runExport<ParticipantLine>(
        context,
        ExportSpec(
          heading: tournament.name.toUpperCase(),
          items: const [],
          summary: MyResultCard(
            tournament: tournament,
            players: report.players,
            line: line,
            points: points,
            forExport: true,
          ),
          summaryHeightEstimate: 420,
          legend: '${DateFormat('dd/MM/yyyy').format(tournament.date)} · ${report.players} jugadores',
          fileBase: 'mi_torneo_${_fileSafe(tournament.name)}',
          shareText: '${line.name} en ${tournament.name}',
          preload: _deckImages(report),
        ),
      ));
}

/// Puesto, mazo, récord y puntos de un jugador en un torneo terminado.
class MyResultCard extends StatelessWidget {
  const MyResultCard({
    super.key,
    required this.tournament,
    required this.players,
    required this.line,
    this.points,
    this.forExport = false,
  });

  final Tournament tournament;
  final int players;
  final ParticipantLine line;
  final int? points;
  final bool forExport;

  @override
  Widget build(BuildContext context) {
    final k = forExport ? 1.6 : 1.0;
    final pos = line.position;
    final stat = TextStyle(fontSize: 13 * k, color: AppColors.textSecondary);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16 * k),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line.madeTop ? AppColors.neon : AppColors.outline, width: 1.2),
        boxShadow: line.madeTop ? AppColors.glow(strength: 0.6) : null,
      ),
      child: Row(
        children: [
          DeckImage(path: line.deckImage, name: line.deck ?? '?', width: 72 * k),
          SizedBox(width: 16 * k),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20 * k, fontWeight: FontWeight.w900)),
                Text(line.deck ?? 'Sin mazo',
                    style: TextStyle(fontSize: 14 * k, color: AppColors.textSecondary)),
                SizedBox(height: 8 * k),
                Wrap(
                  spacing: 14 * k,
                  runSpacing: 4,
                  children: [
                    Text('Récord ${line.record}', style: stat),
                    Text('${(line.winRate * 100).round()}% victorias', style: stat),
                    if (points != null && points! > 0)
                      Text('+$points pts', style: stat.copyWith(color: AppColors.neon, fontWeight: FontWeight.w800)),
                    if (line.madeTop && tournament.topCutSize > 0)
                      Text('Top ${tournament.topCutSize}',
                          style: stat.copyWith(color: AppColors.neon, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 12 * k),
          Column(
            children: [
              Text(pos == null ? '–' : '$posº',
                  style: TextStyle(
                    fontSize: 40 * k,
                    fontWeight: FontWeight.w900,
                    color: AppColors.neonBright,
                    shadows: AppColors.textGlow(blur: 10),
                  )),
              Text('de $players', style: stat),
            ],
          ),
        ],
      ),
    );
  }
}
