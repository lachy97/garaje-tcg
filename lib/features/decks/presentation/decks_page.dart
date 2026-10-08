import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../ranking/presentation/season_picker.dart';
import '../domain/deck_stats.dart';
import 'deck_tier_table.dart';

/// Todos los mazos registrados (inscripción, rondas, gestión).
final decksProvider = StreamProvider.autoDispose<List<Deck>>((ref) {
  return ref.watch(decksDaoProvider).watchAll();
});

final seasonDecksProvider =
    StreamProvider.autoDispose.family<List<DeckSeasonStats>, String>((ref, seasonId) {
  return ref.watch(rankingDaoProvider).watchSeasonDecks(seasonId);
});

/// Mazos de la temporada en tabla + tier list (S/A/B/C) para el final del
/// trimestre. La gestión (crear, renombrar, fusionar) está en una pantalla aparte.
class DecksPage extends ConsumerStatefulWidget {
  const DecksPage({super.key});

  @override
  ConsumerState<DecksPage> createState() => _DecksPageState();
}

class _DecksPageState extends ConsumerState<DecksPage> {
  String? _seasonId;
  bool _exporting = false;

  Future<void> _export(Season season, List<DeckSeasonStats> decks) async {
    setState(() => _exporting = true);
    try {
      await exportDeckTierImages(context, season: season, decks: decks);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo exportar: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasons = ref.watch(seasonListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MAZOS'),
        actions: [
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
          return AsyncView(
            value: ref.watch(seasonDecksProvider(season.id)),
            builder: (decks) => ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                SeasonPicker(
                  seasons: all,
                  selected: season,
                  onChanged: (v) => setState(() => _seasonId = v.id),
                ),
                if (decks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: EmptyState(
                      icon: Icons.style_outlined,
                      title: 'Sin datos de mazos este trimestre',
                      subtitle: 'La tabla se llena al finalizar torneos en los que '
                          'los jugadores tengan mazo asignado.',
                    ),
                  )
                else ...[
                  const SectionLabel('Tier list'),
                  NeonCard(
                    padding: EdgeInsets.zero,
                    child: TierSummary(decks: decks),
                  ),
                  const SectionLabel('Tabla de mazos'),
                  DeckTierTable(decks: decks),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      '$deckLegend.\n\n'
                      'PP = 3·V Swiss + 1·E + 6·V Top + 3·Entradas Top + 5·Títulos\n'
                      'WRp = (V Swiss + 2·V Top + 0.5·E + 5) / (PJ Swiss + 2·PJ Top + 10)\n'
                      'Tier según el Score del mejor mazo: S ≥ 70 % · A ≥ 45 % · B ≥ 20 % · C resto.\n'
                      'Desempates: títulos → V Top → WRp → mejor resultado. '
                      'Solo cuentan torneos terminados. Desliza la tabla para ver todas las columnas.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: OutlinedButton.icon(
                      onPressed: _exporting ? null : () => _export(season, decks),
                      icon: _exporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.image_outlined),
                      label: const Text('EXPORTAR TIER LIST COMO IMAGEN'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
