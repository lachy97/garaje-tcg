import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/export/export_models.dart';
import '../../../../app/export/export_sheet.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/table_export.dart';
import '../../../../core/db/app_database.dart';
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
  required Map<String?, Color> colors,
}) {
  return runExport<ParticipantLine>(
    context,
    ExportSpec(
      heading: '${tournament.name.toUpperCase()} · PARTICIPANTES',
      items: report.participants,
      summary: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tournamentInfoLine(tournament, report),
              style: const TextStyle(fontSize: 17, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outline),
            ),
            child: MetaHeadline(meta: report.metagame, colors: colors, fontSize: 17),
          ),
        ],
      ),
      summaryHeightEstimate: 110,
      tableBuilder: (rows, width) => ParticipantsTable(
        lines: rows,
        colors: colors,
        width: width,
        fontSize: kExportFontSize,
        rowPadding: kExportRowPadding,
      ),
      legend: 'Récord de todo el torneo (Swiss y Top Cut) · BYE = victoria'
          '${tournament.topCutSize > 0 ? ' · En verde, el Top ${tournament.topCutSize}' : ''}',
      fileBase: 'participantes_${_fileSafe(tournament.name)}',
      shareText: '${tournament.name} · Participantes',
      rowHeightEstimate: 52,
    ),
  );
}

// ───────────────────────── Póster de metagame ─────────────────────────

const _kBg = 'assets/export/tierlist_bg.jpg';
const _kPad = 48.0;
const _kDonut = 640.0;
const _kLegendFont = 22.0;

/// Exporta el gráfico de metagame (cuántos jugadores usaron cada mazo).
Future<void> exportMetagame(
  BuildContext context, {
  required Tournament tournament,
  required TournamentReport report,
  required Map<String?, Color> colors,
}) {
  final legendRows = (report.metagame.length / 2).ceil();
  return runExport<DeckShare>(
    context,
    ExportSpec(
      heading: 'METAGAME · ${tournament.name.toUpperCase()}',
      items: report.metagame,
      page: MetagamePoster(tournament: tournament, report: report, colors: colors),
      contentWidth: MetagamePoster.width,
      summaryHeightEstimate:
          _kPad * 2 + 130 + 40 + _kDonut + 40 + legendRows * (_kLegendFont * 1.9) + 60,
      legend: '',
      fileBase: 'metagame_${_fileSafe(tournament.name)}',
      shareText: '${tournament.name} · Metagame',
      preload: const [AssetImage(_kBg)],
    ),
  );
}

/// Póster "METAGAME": dona con el % de cada mazo y la leyenda completa.
class MetagamePoster extends StatelessWidget {
  const MetagamePoster({
    super.key,
    required this.tournament,
    required this.report,
    required this.colors,
  });

  final Tournament tournament;
  final TournamentReport report;
  final Map<String?, Color> colors;

  static const width = 1080.0;

  @override
  Widget build(BuildContext context) {
    const title = Color(0xFFCFCFCF);
    const muted = Color(0xFF8E8E8E);
    final meta = report.metagame;
    final half = (meta.length / 2).ceil();
    final left = meta.take(half).toList();
    final right = meta.skip(half).toList();
    Widget column(List<DeckShare> list) => Column(
          children: [
            for (final d in list)
              MetaLegendRow(
                  share: d, color: colors[d.name] ?? kMetaOther, fontSize: _kLegendFont),
          ],
        );
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
                    const Text(
                      'METAGAME',
                      style: TextStyle(
                        fontSize: 96,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: title,
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
            child: MetaDonut(meta: meta, colors: colors, size: _kDonut),
          ),
          const SizedBox(height: 40),
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
                Expanded(child: column(left)),
                const SizedBox(width: 40),
                Expanded(child: column(right)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${report.deckCount} mazos · jugadores por mazo y % del total',
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
