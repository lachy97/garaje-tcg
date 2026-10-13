import 'package:flutter/material.dart';

import '../../../app/export/export_models.dart';
import '../../../app/export/export_sheet.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/season_utils.dart';
import '../domain/ranking_row.dart';
import 'ranking_table.dart';

/// Exporta el ranking completo como una sola imagen en alta calidad.
Future<void> exportRankingImage(
  BuildContext context, {
  required Season season,
  required List<RankingRow> rows,
}) {
  final label = seasonLabel(season.year, season.quarter);
  return runExport<RankingRow>(
    context,
    ExportSpec(
      heading: 'RANKING · TEMPORADA $label',
      items: rows,
      tableBuilder: (page, width) =>
          RankingTable(rows: page, fixedWidth: width, forExport: true),
      legend: '${rows.length} jugadores · PJ partidas jugadas · V/D/E victorias, derrotas, '
          'empates · WR% victorias/partidas · Torn torneos · Mejor posición alcanzada',
      fileBase: 'ranking_garage_tcg_${season.year}_T${season.quarter}',
      shareText: 'Ranking Garage TCG · Temporada $label',
      rowHeightEstimate: 46,
    ),
  );
}
