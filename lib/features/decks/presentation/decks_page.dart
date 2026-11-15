import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../../../app/widgets/sync_widgets.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/utils/season_utils.dart';
import '../../ranking/presentation/ranking_export.dart';
import '../../ranking/presentation/ranking_page.dart';
import '../../ranking/presentation/season_picker.dart';
import '../domain/deck_stats.dart';
import 'deck_picker.dart' show sortDecks;
import '../domain/tier_style.dart';
import 'deck_matrix.dart';
import '../../../core/auth/auth_providers.dart';
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

/// Datos: Ranking, Tier list y Enfrentamientos en una sola pestaña, con un
/// único selector de temporada arriba (el histórico vale para la tier list y
/// los enfrentamientos; el ranking es siempre de una temporada).
/// Compartir, gestionar mazos y cerrar la temporada: botón de ajustes.
class DecksPage extends ConsumerStatefulWidget {
  const DecksPage({super.key});

  @override
  ConsumerState<DecksPage> createState() => _DecksPageState();
}

class _DecksPageState extends ConsumerState<DecksPage> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));
  String? _seasonId;

  /// Histórico: todas las temporadas juntas.
  bool _all = false;
  bool _exporting = false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openDeck(String scopeId, DeckSeasonStats d) =>
      context.push('/mazos/ficha/${d.deckId}?t=$scopeId');

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _exporting = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo compartir: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareTier(Season season, List<DeckSeasonStats> decks) => _run(() => exportDeckTierImages(
        context,
        label: _all ? 'Histórico' : 'Temporada ${seasonLabel(season.year, season.quarter)}',
        fileTag: _all ? 'historico' : '${season.year}_T${season.quarter}',
        decks: decks,
        styles: ref.read(tierStylesProvider),
      ));

  @override
  Widget build(BuildContext context) {
    final seasons = ref.watch(seasonListProvider);
    final list = seasons.value;
    final current = list == null || list.isEmpty ? null : pickSeason(list, _seasonId);
    final scopeId = _all ? kAllSeasons : current?.id;
    final decks = scopeId == null ? null : ref.watch(seasonDecksProvider(scopeId)).value;
    final rows = current == null || _all ? null : ref.watch(seasonRankingProvider(current.id)).value;
    final perms = ref.watch(permissionsProvider);
    final tab = _tabs.index;

    // Opciones de la barra según la pestaña.
    final canShareRanking = tab == 0 && current != null && rows != null && rows.isNotEmpty;
    final canShareTier = tab == 1 && current != null && decks != null && decks.isNotEmpty;
    final canClose = tab == 0 &&
        current != null &&
        !_all &&
        rows != null &&
        rows.isNotEmpty &&
        current.status != SeasonStatus.closed &&
        perms.canCreateTournaments;
    final menu = [
      if (canShareRanking)
        const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share), title: Text('Compartir ranking'))),
      if (canShareTier)
        const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share), title: Text('Compartir tier list'))),
      if (perms.canCreateTournaments)
        const PopupMenuItem(value: 'manage', child: ListTile(leading: Icon(Icons.edit_note), title: Text('Gestionar mazos'))),
      if (canClose)
        PopupMenuItem(
          value: 'close',
          child: ListTile(
            leading: Icon(Icons.lock_outline, color: AppColors.loss),
            title: Text('Cerrar temporada ${seasonLabel(current.year, current.quarter)}'),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('DATOS'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (menu.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Opciones',
              icon: const Icon(Icons.settings_outlined),
              onSelected: (v) => switch (v) {
                'share' when tab == 0 => _run(() => exportRankingImage(context, season: current!, rows: rows!)),
                'share' => _shareTier(current!, decks!),
                'close' => closeSeason(context, ref, current!),
                _ => context.push('/mazos/gestionar'),
              },
              itemBuilder: (_) => menu,
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          // Con desplazamiento: "Enfrentamientos" no cabe cortado.
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          labelColor: AppColors.neon,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.neon,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Ranking'),
            Tab(text: 'Tier list'),
            Tab(text: 'Enfrentamientos'),
          ],
        ),
      ),
      body: AsyncView(
        value: seasons,
        builder: (all) {
          final season = pickSeason(all, _seasonId);
          final scope = _all ? kAllSeasons : season.id;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Un solo selector de temporada para las tres pestañas.
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
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    // 1) Ranking (siempre de una temporada).
                    _all
                        ? const EmptyState(
                            icon: Icons.leaderboard_outlined,
                            title: 'El ranking es por temporada',
                            subtitle: 'Elige una temporada arriba para ver su ranking.',
                          )
                        : RankingView(key: ValueKey(season.id), season: season),
                    // 2) Tier list y tabla de mazos.
                    _TierTab(
                      scope: scope,
                      closed: !_all && season.status == SeasonStatus.closed,
                      canEditTiers: perms.canCreateTournaments,
                      onTapDeck: (d) => _openDeck(scope, d),
                    ),
                    // 3) Matriz de enfrentamientos.
                    _MatrixTab(scope: scope, onTapDeck: (d) => _openDeck(scope, d)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

const _noDecks = EmptyState(
  icon: Icons.style_outlined,
  title: 'Sin datos de mazos',
  subtitle: 'La tabla se llena al finalizar torneos en los que los jugadores tengan mazo asignado.',
);

class _TierTab extends ConsumerWidget {
  const _TierTab({required this.scope, required this.closed, required this.canEditTiers, required this.onTapDeck});

  final String scope;
  final bool closed;
  final bool canEditTiers;
  final ValueChanged<DeckSeasonStats> onTapDeck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(seasonDecksProvider(scope)),
      builder: (decks) => SyncRefresh(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (closed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Temporada cerrada · tier list definitiva',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
            if (decks.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 48), child: _noDecks)
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TierBoardView(decks: decks),
              ),
              if (canEditTiers)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Toca el cuadro de color de un tier para cambiar su texto o su color.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              const SectionLabel('Tabla de mazos'),
              DeckTierTable(decks: decks, onTapDeck: onTapDeck),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
          ],
        ),
      ),
    );
  }
}

class _MatrixTab extends ConsumerWidget {
  const _MatrixTab({required this.scope, required this.onTapDeck});

  final String scope;
  final ValueChanged<DeckSeasonStats> onTapDeck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(seasonDecksProvider(scope)),
      // La matriz ocupa toda la pestaña para fijar su fila y columna de cabecera.
      builder: (decks) => decks.isEmpty
          ? _noDecks
          : DeckMatrixView(seasonId: scope, decks: decks, onTapDeck: onTapDeck),
    );
  }
}
