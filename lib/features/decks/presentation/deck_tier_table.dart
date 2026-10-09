import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/neon_table.dart';
import '../../../app/export/export_models.dart';
import '../../../app/widgets/table_export.dart';
import '../domain/deck_stats.dart';
import '../domain/tier_style.dart';
import 'deck_image.dart';

Color tierColor(DeckTier t) => switch (t) {
      DeckTier.s => AppColors.neon,
      DeckTier.a => AppColors.leaf,
      DeckTier.b => AppColors.draw,
      DeckTier.c => AppColors.textSecondary,
    };

/// Cuadrado con la etiqueta del tier (texto y color editables; si el texto
/// es largo se muestra la letra).
class TierBadge extends ConsumerWidget {
  const TierBadge(this.tier, {super.key, this.size = 26});

  final DeckTier tier;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = tierStyleOf(ref.watch(tierStylesProvider), tier);
    final text = style.label.trim().isNotEmpty && style.label.trim().length <= 3
        ? style.label.trim()
        : tier.label;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.color,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            text,
            style: TextStyle(
              fontSize: size * 0.62,
              fontWeight: FontWeight.w900,
              color: style.textColor,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tabla de mazos de la temporada (pantalla e imágenes exportadas).
class DeckTierTable extends StatelessWidget {
  const DeckTierTable({super.key, required this.decks, this.fixedWidth, this.forExport = false});

  final List<DeckSeasonStats> decks;
  final double? fixedWidth;
  final bool forExport;

  static const columns = [
    NeonColumn('#', width: 32, align: TextAlign.start),
    NeonColumn('Tier', width: 44),
    NeonColumn('Mazo', width: 140, align: TextAlign.start, flex: true),
    NeonColumn('Score', width: 60),
    NeonColumn('Uso', width: 42),
    NeonColumn('Jug.', width: 42),
    NeonColumn('PJ', width: 38),
    NeonColumn('V', width: 34),
    NeonColumn('D', width: 34),
    NeonColumn('E', width: 34),
    NeonColumn('WR%', width: 52),
    NeonColumn('Top', width: 40),
    NeonColumn('V Top', width: 50),
    NeonColumn('Tít.', width: 40),
    NeonColumn('Mejor', width: 50),
  ];

  /// Suman 722 + 24 ≤ 750 (ancho útil de la imagen).
  static const exportColumns = [
    NeonColumn('#', width: 30, align: TextAlign.start),
    NeonColumn('Tier', width: 44),
    NeonColumn('Mazo', width: 130, align: TextAlign.start, flex: true),
    NeonColumn('Score', width: 58),
    NeonColumn('Uso', width: 42),
    NeonColumn('Jug', width: 40),
    NeonColumn('PJ', width: 40),
    NeonColumn('V', width: 36),
    NeonColumn('D', width: 36),
    NeonColumn('E', width: 34),
    NeonColumn('WR%', width: 54),
    NeonColumn('Top', width: 42),
    NeonColumn('VTop', width: 48),
    NeonColumn('Tít', width: 36),
    NeonColumn('Mejor', width: 52),
  ];

  @override
  Widget build(BuildContext context) {
    final secondary = forExport ? AppColors.textPrimary : AppColors.textSecondary;
    return NeonTable(
      fixedWidth: fixedWidth,
      columns: forExport ? exportColumns : columns,
      fontSize: forExport ? kExportFontSize : 14,
      rowPadding: forExport ? kExportRowPadding : 8,
      headerColor: forExport ? AppColors.neon : AppColors.textSecondary,
      rows: [
        for (final d in decks)
          NeonTableRow(
            highlight: d.tier == DeckTier.s,
            cells: [
              Text('${d.rank}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: secondary)),
              TierBadge(d.tier, size: forExport ? 28 : 24),
              Row(
                children: [
                  DeckImage(path: d.imagePath, name: d.name, width: forExport ? 28 : 24),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(d.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: d.tier == DeckTier.s ? AppColors.neon : null,
                        )),
                  ),
                ],
              ),
              Text(d.score.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.neon)),
              Text('${d.entries}'),
              Text('${d.pilots.length}'),
              Text('${d.played}'),
              Text('${d.wins}', style: const TextStyle(color: AppColors.win)),
              Text('${d.losses}', style: const TextStyle(color: AppColors.loss)),
              Text('${d.swissDraws}', style: const TextStyle(color: AppColors.draw)),
              Text(d.played == 0 ? '—' : '${(d.winrate * 100).toStringAsFixed(0)}%'),
              Text('${d.topEntries}'),
              Text('${d.topWins}'),
              Text('${d.titles}',
                  style: TextStyle(
                      fontWeight: d.titles > 0 ? FontWeight.w900 : null,
                      color: d.titles > 0 ? AppColors.neon : null)),
              Text(d.bestPosition == null ? '—' : '${d.bestPosition}º'),
            ],
          ),
      ],
    );
  }
}

const deckLegend = 'Uso = veces inscrito · Jug = jugadores distintos · PJ/V/D/E partidas '
    '(Swiss + Top) · Top = entradas al Top Cut · VTop = victorias en el Top · '
    'Tít = torneos ganados · Score = PP × (0.5 + WRp)';

ExportTableData deckPdfTable(List<DeckSeasonStats> decks) {
  final neon = AppColors.neon.toARGB32();
  final black = Colors.black.toARGB32();
  return ExportTableData(
    columns: const [
      ExportColumnData('#', 2.6, align: ExportAlign.start),
      ExportColumnData('Tier', 3.2),
      ExportColumnData('Mazo', 13, align: ExportAlign.start),
      ExportColumnData('Score', 4.6),
      ExportColumnData('Uso', 3.4),
      ExportColumnData('Jug', 3.4),
      ExportColumnData('PJ', 3.2),
      ExportColumnData('V', 3),
      ExportColumnData('D', 3),
      ExportColumnData('E', 3),
      ExportColumnData('WR%', 4.2),
      ExportColumnData('Top', 3.4),
      ExportColumnData('VTop', 3.8),
      ExportColumnData('Tít', 3),
      ExportColumnData('Mejor', 4.2),
    ],
    rows: [
      for (final d in decks)
        ExportRowData(
          highlight: d.tier == DeckTier.s,
          [
            ExportCellData('${d.rank}', bold: true),
            ExportCellData(d.tier.label,
                bold: true, color: black, background: tierColor(d.tier).toARGB32()),
            ExportCellData(d.name, bold: true, color: d.tier == DeckTier.s ? neon : null),
            ExportCellData(d.score.toStringAsFixed(1), bold: true, color: neon),
            ExportCellData('${d.entries}'),
            ExportCellData('${d.pilots.length}'),
            ExportCellData('${d.played}'),
            ExportCellData('${d.wins}', color: AppColors.win.toARGB32()),
            ExportCellData('${d.losses}', color: AppColors.loss.toARGB32()),
            ExportCellData('${d.swissDraws}', color: AppColors.draw.toARGB32()),
            ExportCellData(d.played == 0 ? '-' : '${(d.winrate * 100).toStringAsFixed(0)}%'),
            ExportCellData('${d.topEntries}'),
            ExportCellData('${d.topWins}'),
            ExportCellData('${d.titles}', bold: d.titles > 0, color: d.titles > 0 ? neon : null),
            ExportCellData(d.bestPosition == null ? '-' : '${d.bestPosition}º'),
          ],
        ),
    ],
  );
}
