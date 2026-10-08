import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/neon_table.dart';
import '../../../app/widgets/table_export.dart';
import '../domain/ranking_row.dart';

/// Colores por puesto: 1º oro, 2º plata, 3º bronce, 4º turquesa y del 5º al
/// 8º un mismo verde. Del 9º en adelante, sin color propio.
Color? rankingColor(int rank) => switch (rank) {
      1 => const Color(0xFFFFD54A),
      2 => const Color(0xFFD3DCE6),
      3 => const Color(0xFFE39A5C),
      4 => const Color(0xFF4FD8C4),
      >= 5 && <= 8 => AppColors.leaf,
      _ => null,
    };

/// Tabla del ranking trimestral. La usan la pantalla y las imágenes exportadas.
class RankingTable extends StatelessWidget {
  const RankingTable({super.key, required this.rows, this.fixedWidth, this.forExport = false});

  final List<RankingRow> rows;

  /// Ancho fijo (exportación). En pantalla es null y la tabla se adapta/desplaza.
  final double? fixedWidth;

  /// Letra más grande y colores más claros para la imagen.
  final bool forExport;

  static const columns = [
    NeonColumn('#', width: 36, align: TextAlign.start),
    NeonColumn('Jugador', width: 130, align: TextAlign.start, flex: true),
    NeonColumn('Pts', width: 56),
    NeonColumn('Mazo', width: 130, align: TextAlign.start),
    NeonColumn('PJ', width: 38),
    NeonColumn('V', width: 34),
    NeonColumn('D', width: 34),
    NeonColumn('E', width: 34),
    NeonColumn('WR%', width: 56),
    NeonColumn('Torn.', width: 46),
    NeonColumn('Mejor', width: 50),
  ];

  /// Columnas de la imagen: más anchas para letra grande (suman 724 + 24 ≤ 750).
  static const exportColumns = [
    NeonColumn('#', width: 40, align: TextAlign.start),
    NeonColumn('Jugador', width: 140, align: TextAlign.start, flex: true),
    NeonColumn('Pts', width: 62),
    NeonColumn('Mazo', width: 150, align: TextAlign.start),
    NeonColumn('PJ', width: 42),
    NeonColumn('V', width: 38),
    NeonColumn('D', width: 38),
    NeonColumn('E', width: 38),
    NeonColumn('WR%', width: 62),
    NeonColumn('Torn', width: 52),
    NeonColumn('Mejor', width: 62),
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
        for (final r in rows)
          NeonTableRow(
            accent: rankingColor(r.rank),
            cells: [
              Text(
                '${r.rank}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: rankingColor(r.rank) ?? secondary,
                  shadows: r.rank == 1
                      ? AppColors.textGlow(color: rankingColor(1)!, blur: 8)
                      : null,
                ),
              ),
              Text(r.nickname,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: r.rank <= 4 ? FontWeight.w800 : FontWeight.w700,
                    color: rankingColor(r.rank),
                  )),
              Text('${r.points}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.neon)),
              Text(r.lastDeck ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: forExport ? kExportFontSize - 2 : 13, color: secondary)),
              Text('${r.played}'),
              Text('${r.wins}', style: const TextStyle(color: AppColors.win)),
              Text('${r.losses}', style: const TextStyle(color: AppColors.loss)),
              Text('${r.draws}', style: const TextStyle(color: AppColors.draw)),
              Text(r.played == 0 ? '—' : '${(r.winrate * 100).toStringAsFixed(0)}%'),
              Text('${r.tournaments}'),
              Text('${r.bestPosition}º'),
            ],
          ),
      ],
    );
  }
}
