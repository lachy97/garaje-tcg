import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/neon_table.dart';
import '../../../app/widgets/table_export.dart';
import '../domain/ranking_row.dart';

/// Colores por puesto: degradado de verdes de la marca, del más brillante
/// (1º) al más oscuro; del 5º al 8º un mismo verde. Del 9º en adelante, sin
/// color propio.
Color? rankingColor(int rank) => AppColors.isDark
    ? switch (rank) {
        1 => const Color(0xFFD1FFAD),
        2 => const Color(0xFFA8F56E),
        3 => const Color(0xFF7FD957),
        4 => const Color(0xFF4FC08D),
        >= 5 && <= 8 => const Color(0xFF3E9A63),
        _ => null,
      }
    // Modo claro: verdes más oscuros para que se lean sobre blanco.
    : switch (rank) {
        1 => const Color(0xFF1B5410),
        2 => const Color(0xFF2E7D1F),
        3 => const Color(0xFF3B8A47),
        4 => const Color(0xFF2F7D5B),
        >= 5 && <= 8 => const Color(0xFF4C8E66),
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

  /// Columnas de la imagen: más anchas para letra grande (720 + 24 + 4 ≤ 750).
  static const exportColumns = [
    NeonColumn('#', width: 40, align: TextAlign.start),
    NeonColumn('Jugador', width: 140, align: TextAlign.start, flex: true),
    NeonColumn('Pts', width: 62),
    NeonColumn('Mazo', width: 146, align: TextAlign.start),
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
                  style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.neon)),
              Text(r.lastDeck ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: forExport ? kExportFontSize - 2 : 12, color: secondary)),
              Text('${r.played}'),
              Text('${r.wins}', style: TextStyle(color: AppColors.win)),
              Text('${r.losses}', style: TextStyle(color: AppColors.loss)),
              Text('${r.draws}', style: TextStyle(color: AppColors.draw)),
              Text(r.played == 0 ? '—' : '${(r.winrate * 100).toStringAsFixed(0)}%'),
              Text('${r.tournaments}'),
              Text('${r.bestPosition}º'),
            ],
          ),
      ],
    );
  }
}
