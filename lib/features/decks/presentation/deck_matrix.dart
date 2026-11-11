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
///
/// Al desplazarse, la columna de nombres (izquierda) y la fila de imágenes
/// (arriba) quedan fijas. Necesita un alto acotado (p. ej. dentro de un
/// Expanded).
class DeckMatrixView extends ConsumerWidget {
  const DeckMatrixView({
    super.key,
    required this.seasonId,
    required this.decks,
    this.onTapDeck,
    this.maxDecks = 20,
  });

  final String seasonId;
  final List<DeckSeasonStats> decks;
  final void Function(DeckSeasonStats deck)? onTapDeck;
  final int maxDecks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(seasonMatchupsProvider(seasonId)),
      builder: (m) {
        final shown = decks.where((d) => m.table.containsKey(d.deckId)).take(maxDecks).toList();
        if (shown.isEmpty) {
          return Padding(
            padding: EdgeInsets.all(24),
            child: Text('Aún no hay partidas entre mazos esta temporada.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _StickyMatrix(matchups: m, decks: shown, onTapDeck: onTapDeck)),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Celda: victorias-derrotas(-empates) del mazo de la FILA contra el de la '
                'columna (Swiss y Top, torneos terminados). Verde ≥ 60 % · amarillo · '
                'rojo ≤ 40 %. Diagonal: espejos. Toca una celda para el detalle o un '
                'nombre para abrir la ficha.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StickyMatrix extends StatefulWidget {
  const _StickyMatrix({required this.matchups, required this.decks, this.onTapDeck});

  final DeckMatchups matchups;
  final List<DeckSeasonStats> decks;
  final void Function(DeckSeasonStats deck)? onTapDeck;

  @override
  State<_StickyMatrix> createState() => _StickyMatrixState();
}

class _StickyMatrixState extends State<_StickyMatrix> {
  static const _cell = 56.0;
  static const _head = 132.0;

  // Cuerpo y cabeceras se mueven juntos (en los dos sentidos).
  final _hHead = ScrollController();
  final _hBody = ScrollController();
  final _vLeft = ScrollController();
  final _vBody = ScrollController();
  bool _syncing = false;

  void _link(ScrollController from, ScrollController to) {
    from.addListener(() {
      if (_syncing || !to.hasClients) return;
      _syncing = true;
      to.jumpTo(from.offset.clamp(0.0, to.position.maxScrollExtent));
      _syncing = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _link(_hBody, _hHead);
    _link(_hHead, _hBody);
    _link(_vBody, _vLeft);
    _link(_vLeft, _vBody);
  }

  @override
  void dispose() {
    for (final c in [_hHead, _hBody, _vLeft, _vBody]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.decks;
    final m = widget.matchups;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          // Fila fija de arriba: imágenes de los mazos de las columnas.
          Row(
            children: [
              SizedBox(
                width: _head,
                height: _cell,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Fila vs columna',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _hHead,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
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
                ),
              ),
            ],
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Columna fija de la izquierda: imagen y nombre de cada mazo.
                SizedBox(
                  width: _head,
                  child: SingleChildScrollView(
                    controller: _vLeft,
                    child: Column(
                      children: [
                        for (final r in shown)
                          InkWell(
                            onTap: widget.onTapDeck == null ? null : () => widget.onTapDeck!(r),
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
                      ],
                    ),
                  ),
                ),
                // Celdas: se desplazan en los dos sentidos.
                Expanded(
                  child: SingleChildScrollView(
                    controller: _vBody,
                    child: SingleChildScrollView(
                      controller: _hBody,
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        children: [
                          for (final r in shown)
                            Row(children: [for (final c in shown) _cellOf(context, m, r, c)]),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
