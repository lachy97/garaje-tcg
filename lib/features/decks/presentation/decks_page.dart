import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/utils/season_utils.dart';
import '../../ranking/presentation/season_picker.dart';
import '../domain/deck_stats.dart';
import 'deck_picker.dart' show sortDecks;
import '../domain/tier_style.dart';
import 'deck_matrix.dart';
import 'deck_tier_table.dart';
import 'tier_board.dart';

/// Todos los mazos registrados (inscripción, rondas, gestión).
/// Ordenados como en edisonformat.net (competitivos, rogue, casual) y luego
/// los añadidos a mano.
final decksProvider = StreamProvider.autoDispose<List<Deck>>((ref) {
  return ref.watch(decksDaoProvider).watchAll().map(sortDecks);
});

final seasonDecksProvider =
    StreamProvider.autoDispose.family<List<DeckSeasonStats>, String>((ref, seasonId) {
  return ref.watch(rankingDaoProvider).watchSeasonDecks(seasonId);
});

/// Tier list (tablero y tabla) y matriz de enfrentamientos, por temporada o
/// del histórico (todas las temporadas). Compartir: botón de la barra.
/// La gestión (crear, renombrar, fusionar) está en una pantalla aparte.
class DecksPage extends ConsumerStatefulWidget {
  const DecksPage({super.key});

  @override
  ConsumerState<DecksPage> createState() => _DecksPageState();
}

class _DecksPageState extends ConsumerState<DecksPage> {
  String? _seasonId;

  /// Histórico: todas las temporadas juntas.
  bool _all = false;
  bool _exporting = false;

  /// false = tier list y tabla · true = matriz de enfrentamientos.
  bool _matrix = false;

  void _openDeck(String scopeId, DeckSeasonStats d) =>
      context.push('/mazos/ficha/${d.deckId}?t=$scopeId');

  Future<void> _share(Season season, List<DeckSeasonStats> decks) async {
    setState(() => _exporting = true);
    try {
      await exportDeckTierImages(
        context,
        label: _all ? 'Histórico' : 'Temporada ${seasonLabel(season.year, season.quarter)}',
        fileTag: _all ? 'historico' : '${season.year}_T${season.quarter}',
        decks: decks,
        styles: ref.read(tierStylesProvider),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo compartir: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasons = ref.watch(seasonListProvider);
    final list = seasons.value;
    final current = list == null || list.isEmpty ? null : pickSeason(list, _seasonId);
    final scopeId = _all ? kAllSeasons : current?.id;
    final shareable = scopeId == null ? null : ref.watch(seasonDecksProvider(scopeId)).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MAZOS'),
        actions: [
          if (!_matrix && current != null && shareable != null && shareable.isNotEmpty)
            IconButton(
              tooltip: 'Compartir tier list',
              onPressed: _exporting ? null : () => _share(current, shareable),
              icon: _exporting
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.share),
            ),
          IconButton(
            tooltip: 'Gestionar mazos',
            onPressed: () => context.push('/mazos/gestionar'),
            icon: const Icon(Icons.edit_note),
          ),
        ],
      ),
      body: AsyncView(
        value: seasons,
        builder: (all) {
          final season = pickSeason(all, _seasonId);
          final scope = _all ? kAllSeasons : season.id;
          return AsyncView(
            value: ref.watch(seasonDecksProvider(scope)),
            builder: (decks) {
              final header = <Widget>[
                SeasonPicker(
                  seasons: all,
                  selected: season,
                  allowAll: true,
                  allSelected: _all,
                  onChanged: (v) => setState(() {
                    _all = v == null;
                    if (v != null) _seasonId = v.id;
                  }),
                ),
                if (!_all && season.status == SeasonStatus.closed)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text('Temporada cerrada · tier list definitiva',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Tier list')),
                      ButtonSegment(value: true, label: Text('Enfrentamientos')),
                    ],
                    selected: {_matrix},
                    onSelectionChanged: (v) => setState(() => _matrix = v.first),
                  ),
                ),
              ];
              if (decks.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    ...header,
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: EmptyState(
                        icon: Icons.style_outlined,
                        title: 'Sin datos de mazos',
                        subtitle: 'La tabla se llena al finalizar torneos en los que '
                            'los jugadores tengan mazo asignado.',
                      ),
                    ),
                  ],
                );
              }
              // Enfrentamientos: la matriz ocupa el resto de la pantalla para
              // poder fijar su fila y su columna de cabecera.
              if (_matrix) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...header,
                    const SectionLabel('Matriz de enfrentamientos'),
                    Expanded(
                      child: DeckMatrixView(
                        seasonId: scope,
                        decks: decks,
                        onTapDeck: (d) => _openDeck(scope, d),
                      ),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  ...header,
                  const SectionLabel('Tier list'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TierBoardView(decks: decks),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Toca el cuadro de color de un tier para cambiar su texto o su color.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  const SectionLabel('Tabla de mazos'),
                  DeckTierTable(decks: decks, onTapDeck: (d) => _openDeck(scope, d)),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      '$deckLegend.\n\n'
                      'En torneos sin Top Cut cuentan como Top los 4 primeros.\n'
                      'Tier según el Power del mejor mazo: S ≥ 70 % · A ≥ 40 % · B ≥ 15 % · C el resto · '
                      'Rogue/Local = sin Top.\n'
                      'Desempates: Conversión → Presencia. '
                      'Solo cuentan torneos terminados. Desliza la tabla para ver todas las columnas; '
                      'toca un mazo para ver su ficha.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
