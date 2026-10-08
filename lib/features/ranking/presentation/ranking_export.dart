import 'package:flutter/material.dart';

import '../../../app/export/export_models.dart';
import '../../../app/export/export_sheet.dart';
import '../../../app/theme.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/season_utils.dart';
import '../domain/ranking_row.dart';
import 'ranking_table.dart';

/// Exporta el ranking completo. Pregunta el formato: imagen única en alta
/// calidad (como documento), PDF o imágenes de 12 jugadores para el chat.
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
      pdfTable: () => rankingPdfTable(rows),
      legend: '${rows.length} jugadores · PJ partidas jugadas · V/D/E victorias, derrotas, '
          'empates · WR% victorias/partidas · Torn torneos · Mejor posición alcanzada',
      fileBase: 'ranking_garage_tcg_${season.year}_T${season.quarter}',
      shareText: 'Ranking Garage TCG · Temporada $label',
      rowHeightEstimate: 46,
    ),
  );
}

/// Color del puesto mezclado sobre negro (fondo suave de la fila en el PDF).
int? _rowBackground(int rank) {
  final c = rankingColor(rank);
  if (c == null) return null;
  return Color.lerp(AppColors.background, c, 0.16)!.toARGB32();
}

ExportTableData rankingPdfTable(List<RankingRow> rows) {
  final neon = AppColors.neon.toARGB32();
  final secondary = AppColors.textSecondary.toARGB32();
  return ExportTableData(
    columns: const [
      ExportColumnData('#', 3, align: ExportAlign.start),
      ExportColumnData('Jugador', 14, align: ExportAlign.start),
      ExportColumnData('Pts', 5),
      ExportColumnData('Mazo', 13, align: ExportAlign.start),
      ExportColumnData('PJ', 3.5),
      ExportColumnData('V', 3.2),
      ExportColumnData('D', 3.2),
      ExportColumnData('E', 3.2),
      ExportColumnData('WR%', 4.6),
      ExportColumnData('Torn', 4.2),
      ExportColumnData('Mejor', 4.6),
    ],
    rows: [
      for (final r in rows)
        ExportRowData(
          background: _rowBackground(r.rank),
          [
            ExportCellData('${r.rank}',
                bold: true, color: rankingColor(r.rank)?.toARGB32() ?? secondary),
            ExportCellData(r.nickname, bold: true, color: rankingColor(r.rank)?.toARGB32()),
            ExportCellData('${r.points}', bold: true, color: neon),
            ExportCellData(r.lastDeck ?? '-'),
            ExportCellData('${r.played}'),
            ExportCellData('${r.wins}', color: AppColors.win.toARGB32()),
            ExportCellData('${r.losses}', color: AppColors.loss.toARGB32()),
            ExportCellData('${r.draws}', color: AppColors.draw.toARGB32()),
            ExportCellData(r.played == 0 ? '-' : '${(r.winrate * 100).toStringAsFixed(0)}%'),
            ExportCellData('${r.tournaments}'),
            ExportCellData('${r.bestPosition}º'),
          ],
        ),
    ],
  );
}
