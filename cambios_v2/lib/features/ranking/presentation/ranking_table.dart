import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/neon_table.dart';
import '../domain/ranking_row.dart';

/// Tabla del ranking trimestral. La usan la pantalla y la imagen exportada.
class RankingTable extends StatelessWidget {
  const RankingTable({super.key, required this.rows, this.fixedWidth});

  final List<RankingRow> rows;

  /// Ancho fijo (exportación). En pantalla es null y la tabla se adapta/desplaza.
  final double? fixedWidth;

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

  @override
  Widget build(BuildContext context) {
    return NeonTable(
      fixedWidth: fixedWidth,
      columns: columns,
      rows: [
        for (final r in rows)
          NeonTableRow(
            highlight: r.rank <= 3,
            cells: [
              Text(
                '${r.rank}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: r.rank <= 3 ? AppColors.neon : AppColors.textSecondary,
                  shadows: r.rank == 1 ? AppColors.textGlow(blur: 8) : null,
                ),
              ),
              Text(r.nickname,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: r.rank <= 3 ? AppColors.neon : null,
                  )),
              Text('${r.points}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.neon)),
              Text(r.lastDeck ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
