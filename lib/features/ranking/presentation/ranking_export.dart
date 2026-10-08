import 'package:flutter/material.dart';

import '../../../app/widgets/table_export.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/season_utils.dart';
import '../domain/ranking_row.dart';
import 'ranking_table.dart';

/// Exporta el ranking COMPLETO en imágenes de 12 jugadores cada una
/// (alta resolución, legibles en WhatsApp) y abre el menú de compartir.
Future<void> exportRankingImage(
  BuildContext context, {
  required Season season,
  required List<RankingRow> rows,
}) {
  final label = seasonLabel(season.year, season.quarter);
  return exportPagedTable<RankingRow>(
    context,
    heading: 'RANKING · TEMPORADA $label',
    items: rows,
    tableBuilder: (page, width) =>
        RankingTable(rows: page, fixedWidth: width, forExport: true),
    legend: '${rows.length} jugadores · PJ partidas jugadas · V/D/E victorias, derrotas, '
        'empates · WR% victorias/partidas · Torn torneos · Mejor posición alcanzada',
    fileBase: 'ranking_garage_tcg_${season.year}_T${season.quarter}',
    shareText: 'Ranking Garage TCG · Temporada $label',
  );
}
