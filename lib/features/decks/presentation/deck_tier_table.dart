import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/neon_table.dart';
import '../../../app/widgets/table_export.dart';
import '../domain/deck_stats.dart';
import '../domain/tier_style.dart';
import 'deck_image.dart';

Color tierColor(DeckTier t) => switch (t) {
      DeckTier.s => AppColors.neon,
      DeckTier.a => AppColors.leaf,
      DeckTier.b => AppColors.draw,
      DeckTier.c => AppColors.textSecondary,
      DeckTier.rogue => AppColors.textDisabled,
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
  const DeckTierTable({
    super.key,
    required this.decks,
    this.fixedWidth,
    this.forExport = false,
    this.onTapDeck,
  });

  final List<DeckSeasonStats> decks;

  /// Al tocar un mazo (abre su ficha). Solo en pantalla.
  final void Function(DeckSeasonStats deck)? onTapDeck;
  final double? fixedWidth;
  final bool forExport;

  static const columns = [
    NeonColumn('#', width: 32, align: TextAlign.start),
    NeonColumn('Tier', width: 44),
    NeonColumn('Mazo', width: 140, align: TextAlign.start, flex: true),
    NeonColumn('Power', width: 58),
    NeonColumn('Pres.', width: 52),
    NeonColumn('Conv.', width: 54),
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

  /// Columnas para imagen (la tier list ya no exporta la tabla, se mantiene
  /// por si se vuelve a usar).
  static const exportColumns = [
    NeonColumn('#', width: 30, align: TextAlign.start),
    NeonColumn('Tier', width: 44),
    NeonColumn('Mazo', width: 130, align: TextAlign.start, flex: true),
    NeonColumn('Power', width: 56),
    NeonColumn('Pres', width: 50),
    NeonColumn('Conv', width: 52),
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
            onTap: onTapDeck == null ? null : () => onTapDeck!(d),
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
              Text('${d.power}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.neon)),
              Text(_pct(d.presence)),
              Text(_pct(d.conversion)),
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

String _pct(double v) => '${(v * 100).round()}%';

const deckLegend = 'Power = puntos por resultados en el Top (Campeón 8 · Finalista 6 · '
    '3º-4º 4 · Top 8 2 · Top 16 1) · Pres = % de inscripciones con el mazo · '
    'Conv = % de sus pilotos que entraron al Top · Uso = veces inscrito · '
    'Jug = jugadores distintos · PJ/V/D/E partidas (Swiss + Top) · '
    'Top = entradas al Top · VTop = victorias en el Top · Tít = torneos ganados';
