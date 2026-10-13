import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/database_provider.dart';
import '../domain/deck_matchups.dart';
import '../domain/deck_stats.dart';
import 'deck_image.dart';

final seasonMatchupsProvider =
    StreamProvider.autoDispose.family<DeckMatchups, String>((ref, seasonId) {
  return ref.watch(rankingDaoProvider).watchSeasonMatchups(seasonId);
});

/// Color de una celda según el % de victorias del mazo de la fila.
Color matchupColor(MatchupRecord r) {
  if (r.played == 0) return Colors.transparent;
  final w = r.winrate;
  if (w >= 0.6) return AppColors.win.withValues(alpha: 0.35);
  if (w > 0.4) return AppColors.draw.withValues(alpha: 0.28);
  return AppColors.loss.withValues(alpha: 0.32);
}

/// Matriz mazo contra mazo de la temporada. Filas y columnas en el orden de
/// la tier list (los [maxDecks] primeros con partidas). Cada celda: victorias-
/// derrotas del mazo de la fila contra el de la columna.
class DeckMatrixView extends ConsumerWidget {
  const DeckMatrixView({
    super.key,
    required this.seasonId,
    required this.decks,
    this.onTapDeck,
    this.maxDecks = 12,
  });

  final String seasonId;
  final List<DeckSeasonStats> decks;
  final void Function(DeckSeasonStats deck)? onTapDeck;
  final int maxDecks;

  static const _cell = 56.0;
  static const _head = 132.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(seasonMatchupsProvider(seasonId)),
      builder: (m) {
        final shown = decks.where((d) => m.table.containsKey(d.deckId)).take(maxDecks).toList();
        if (shown.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Aún no hay partidas entre mazos esta temporada.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabecera: imágenes de los mazos de las columnas.
                  Row(
                    children: [
                      const SizedBox(width: _head, child: Text('Fila vs columna',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                      for (final c in shown)
                        SizedBox(
                          width: _cell,
                          height: _cell,
                          child: Tooltip(
                            message: c.name,
                            child: Center(
                                child: DeckImage(path: c.imagePath, name: c.name, width: 36)),
                          ),
                        ),
                    ],
                  ),
                  for (final r in shown)
                    Row(
                      children: [
                        InkWell(
                          onTap: onTapDeck == null ? null : () => onTapDeck!(r),
                          child: SizedBox(
                            width: _head,
                            height: _cell,
                            child: Row(
                              children: [
                                DeckImage(path: r.imagePath, name: r.name, width: 28),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(r.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        for (final c in shown) _cellOf(context, m, r, c),
                      ],
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'Cada celda: victorias-derrotas(-empates) del mazo de la FILA contra el de '
                'la columna, en torneos terminados (Swiss y Top). Verde ≥ 60 % · amarillo · '
                'rojo ≤ 40 %. En la diagonal, los espejos. Toca una celda para ver el detalle '
                'o el nombre de un mazo para abrir su ficha.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _cellOf(BuildContext context, DeckMatchups m, DeckSeasonStats r, DeckSeasonStats c) {
    final rec = m.of(r.deckId, c.deckId);
    final mirror = r.deckId == c.deckId;
    return InkWell(
      onTap: rec == null
          ? null
          : () => showMessage(
                context,
                mirror
                    ? '${r.name}: ${rec.played} espejo(s)'
                    : '${r.name} vs ${c.name}: $rec '
                        '(${(rec.winrate * 100).round()} % de victorias en ${rec.played})',
              ),
      child: Container(
        width: _cell,
        height: _cell,
        decoration: BoxDecoration(
          color: rec == null || mirror ? null : matchupColor(rec),
          border: Border.all(color: AppColors.outlineVariant, width: 0.5),
        ),
        alignment: Alignment.center,
        child: Text(
          rec == null ? '·' : mirror ? '${rec.played}' : '$rec',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: rec == null || mirror ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
