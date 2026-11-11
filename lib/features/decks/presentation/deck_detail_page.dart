import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/utils/season_utils.dart';
import '../../ranking/presentation/season_picker.dart';
import '../../../app/widgets/neon_table.dart';
import '../../../core/db/app_database.dart';
import '../domain/deck_matchups.dart';
import '../domain/deck_profile.dart';
import '../domain/deck_stats.dart';
import 'deck_image.dart';
import 'deck_matrix.dart';
import 'deck_tier_table.dart' show TierBadge;
import 'decks_page.dart' show seasonDecksProvider;
import '../../../core/auth/auth_providers.dart';
import '../../account/locked.dart';

final _deckEntriesProvider = StreamProvider.autoDispose
    .family<List<DeckTournamentEntry>, (String, String)>((ref, key) {
  return ref.watch(rankingDaoProvider).watchDeckEntries(key.$1, key.$2);
});

final _deckProfileProvider =
    StreamProvider.autoDispose.family<DeckProfile, (String, String)>((ref, key) {
  return ref.watch(rankingDaoProvider).watchDeckProfile(key.$1, key.$2);
});

String _pct(double v) => '${(v * 100).round()} %';

/// Ficha de un mazo, como la de un jugador, en cuatro pestañas:
/// Resumen (Power, tier, partidas, mejor y peor piloto, mejor y peor
/// enfrentamiento), Pilotos (cómo le fue a cada jugador con el mazo),
/// Rivales (contra cada mazo y cada jugador) e Historial (torneos y
/// partidas). Arriba se elige la temporada o el histórico.
class DeckDetailPage extends ConsumerStatefulWidget {
  const DeckDetailPage({super.key, required this.deckId, required this.seasonId});

  final String deckId;
  final String seasonId;

  @override
  ConsumerState<DeckDetailPage> createState() => _DeckDetailPageState();
}

class _DeckDetailPageState extends ConsumerState<DeckDetailPage> {
  late String _scope = widget.seasonId;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(permissionsProvider).canSeeDeckStats) {
      return Scaffold(appBar: AppBar(), body: const LockedFeature.license());
    }
    final deckId = widget.deckId;
    final seasons = ref.watch(seasonListProvider).value ?? const <Season>[];
    final season = seasons.where((s) => s.id == _scope).firstOrNull;
    final stats = ref.watch(seasonDecksProvider(_scope));
    final profile = ref.watch(_deckProfileProvider((_scope, deckId)));
    final picker = seasons.isEmpty
        ? const SizedBox.shrink()
        : SeasonPicker(
            seasons: seasons,
            selected: season ?? pickSeason(seasons, null),
            allowAll: true,
            allSelected: _scope == kAllSeasons,
            onChanged: (v) => setState(() => _scope = v?.id ?? kAllSeasons),
          );
    final label = season == null
        ? (_scope == kAllSeasons ? 'Histórico' : '')
        : 'Temporada ${seasonLabel(season.year, season.quarter)}';

    return AsyncView(
      value: stats,
      builder: (all) {
        final d = all.where((x) => x.deckId == deckId).firstOrNull;
        final names = {for (final x in all) x.deckId: x.name};
        final title = d?.name ?? names[deckId] ?? 'Mazo';
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text(title.toUpperCase(), overflow: TextOverflow.ellipsis),
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                labelColor: AppColors.neon,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.neon,
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(text: 'Resumen'),
                  Tab(text: 'Pilotos'),
                  Tab(text: 'Rivales'),
                  Tab(text: 'Historial'),
                ],
              ),
            ),
            body: AsyncView(
              value: profile,
              builder: (p) {
                if (d == null && p.games.isEmpty) {
                  return ListView(
                    children: [
                      picker,
                      const Padding(
                        padding: EdgeInsets.only(top: 48),
                        child: EmptyState(
                            icon: Icons.style_outlined,
                            title: 'Este mazo no jugó en este periodo'),
                      ),
                    ],
                  );
                }
                return TabBarView(
                  children: [
                    // 1) Resumen
                    ListView(
                      padding: const EdgeInsets.only(bottom: 40),
                      children: [
                        picker,
                        if (d != null) _Header(deck: d, season: label),
                        _GamesGrid(profile: p),
                        const SectionLabel('Destacados'),
                        _Highlights(profile: p, names: names),
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(
                            'Winrate = victorias ÷ partidas (los empates cuentan como no '
                            'ganadas). Sin espejos. Mejor y peor: con al menos '
                            '${DeckProfile.minGames} partidas.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    // 2) Pilotos
                    ListView(
                      padding: const EdgeInsets.only(bottom: 40),
                      children: [
                        picker,
                        SectionLabel('Pilotos (${p.pilots.length})'),
                        if (p.pilots.isEmpty)
                          const _Empty('Nadie jugó con este mazo en este periodo.')
                        else
                          _PilotsTable(pilots: p.pilots),
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(
                            'Partidas de cada jugador con el mazo (con espejos). '
                            'T = torneos · Top = entradas al Top · Mejor = mejor puesto.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    // 3) Rivales
                    ListView(
                      padding: const EdgeInsets.only(bottom: 40),
                      children: [
                        picker,
                        SectionLabel('Contra cada mazo (${p.vsDecks.length})'),
                        if (p.vsDecks.isEmpty)
                          const _Empty('Sin partidas contra otros mazos.')
                        else
                          _VsDecksTable(profile: p, names: names),
                        if (p.mirrors > 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                            child: Text('Espejos: ${p.mirrors} partida(s).',
                                style: TextStyle(color: AppColors.textSecondary)),
                          ),
                        SectionLabel('Contra cada jugador (${p.opponents.length})'),
                        if (p.opponents.isEmpty)
                          const _Empty('Sin rivales.')
                        else
                          _OpponentsTable(opponents: p.opponents),
                      ],
                    ),
                    // 4) Historial
                    ListView(
                      padding: const EdgeInsets.only(bottom: 40),
                      children: [
                        picker,
                        const SectionLabel('Torneos'),
                        _Entries(seasonId: _scope, deckId: deckId),
                        SectionLabel('Partidas (${p.games.length})'),
                        if (p.games.isEmpty)
                          const _Empty('Sin partidas.')
                        else
                          _GamesList(games: p.games),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(text, style: TextStyle(color: AppColors.textSecondary)),
      );
}

/// Cuadrícula de cifras de partidas.
class _GamesGrid extends StatelessWidget {
  const _GamesGrid({required this.profile});

  final DeckProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    String wr(Record3 r) => r.played == 0 ? '—' : _pct(r.winrate);
    final tiles = [
      ('Partidas', '${p.total.played}'),
      ('V-D-E', '${p.total}'),
      ('Winrate', wr(p.total)),
      ('Swiss', '${p.swiss} · ${wr(p.swiss)}'),
      ('Top Cut', p.topCut.played == 0 ? '—' : '${p.topCut} · ${wr(p.topCut)}'),
      ('Torneos', '${p.tournaments}'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.5,
        children: [
          for (final (label, value) in tiles)
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.outline),
              ),
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.neon)),
                  ),
                  const SizedBox(height: 2),
                  Text(label,
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Mejor y peor piloto; mejor y peor enfrentamiento.
class _Highlights extends StatelessWidget {
  const _Highlights({required this.profile, required this.names});

  final DeckProfile profile;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final best = p.bestPilot, worst = p.worstPilot;
    final bm = p.bestMatchup, wm = p.worstMatchup;
    String deckName(String id) => names[id] ?? p.vsDeckNames[id] ?? 'Otro mazo';
    Widget tile(IconData icon, Color color, String title, String name, String detail,
            {VoidCallback? onTap}) =>
        ListTile(
          dense: true,
          onTap: onTap,
          leading: Icon(icon, color: color),
          title: Text(title, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          subtitle: Text(name,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          trailing: Text(detail, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        );
    final items = [
      if (best != null)
        tile(Icons.emoji_events, AppColors.win, 'Mejor piloto', best.name,
            '${best.record} · ${_pct(best.record.winrate)}',
            onTap: () => context.push('/jugadores/${best.playerId}')),
      if (worst != null)
        tile(Icons.trending_down, AppColors.loss, 'Peor piloto', worst.name,
            '${worst.record} · ${_pct(worst.record.winrate)}',
            onTap: () => context.push('/jugadores/${worst.playerId}')),
      if (bm != null)
        tile(Icons.thumb_up_alt_outlined, AppColors.win, 'Mejor enfrentamiento',
            deckName(bm.$1), '${bm.$2} · ${_pct(bm.$2.winrate)}'),
      if (wm != null && wm.$1 != bm?.$1)
        tile(Icons.thumb_down_alt_outlined, AppColors.loss, 'Peor enfrentamiento',
            deckName(wm.$1), '${wm.$2} · ${_pct(wm.$2.winrate)}'),
    ];
    if (items.isEmpty) return const _Empty('Aún no hay partidas suficientes.');
    return NeonCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: items),
    );
  }
}

class _PilotsTable extends StatelessWidget {
  const _PilotsTable({required this.pilots});

  final List<DeckPilot> pilots;

  @override
  Widget build(BuildContext context) {
    return NeonTable(
      columns: const [
        NeonColumn('Jugador', width: 110, align: TextAlign.start, flex: true),
        NeonColumn('T', width: 30),
        NeonColumn('PJ', width: 36),
        NeonColumn('V', width: 30),
        NeonColumn('D', width: 30),
        NeonColumn('E', width: 30),
        NeonColumn('WR%', width: 50),
        NeonColumn('Top', width: 36),
        NeonColumn('Mejor', width: 46),
      ],
      rows: [
        for (final p in pilots)
          NeonTableRow(
            onTap: () => context.push('/jugadores/${p.playerId}'),
            cells: [
              Text(p.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${p.tournaments.length}'),
              Text('${p.record.played}'),
              Text('${p.record.wins}', style: TextStyle(color: AppColors.win)),
              Text('${p.record.losses}', style: TextStyle(color: AppColors.loss)),
              Text('${p.record.draws}', style: TextStyle(color: AppColors.draw)),
              Text(p.record.played == 0 ? '—' : '${(p.record.winrate * 100).round()}%'),
              Text('${p.tops}', style: TextStyle(color: AppColors.neon)),
              Text(p.bestPosition == null ? '—' : '${p.bestPosition}º'),
            ],
          ),
      ],
    );
  }
}

class _VsDecksTable extends StatelessWidget {
  const _VsDecksTable({required this.profile, required this.names});

  final DeckProfile profile;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    return NeonTable(
      columns: const [
        NeonColumn('Mazo rival', width: 120, align: TextAlign.start, flex: true),
        NeonColumn('PJ', width: 36),
        NeonColumn('V-D-E', width: 64),
        NeonColumn('WR%', width: 50),
      ],
      rows: [
        for (final (id, r) in profile.vsDecks)
          NeonTableRow(
            accent: r.played == 0 ? null : matchupColor(r),
            cells: [
              Text(names[id] ?? profile.vsDeckNames[id] ?? 'Otro mazo',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${r.played}'),
              Text('${r.wins}-${r.losses}-${r.draws}'),
              Text('${(r.winrate * 100).round()}%'),
            ],
          ),
      ],
    );
  }
}

class _OpponentsTable extends StatefulWidget {
  const _OpponentsTable({required this.opponents});

  final List<DeckOpponent> opponents;

  @override
  State<_OpponentsTable> createState() => _OpponentsTableState();
}

class _OpponentsTableState extends State<_OpponentsTable> {
  static const _initial = 10;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final list = _all ? widget.opponents : widget.opponents.take(_initial).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeonTable(
          columns: const [
            NeonColumn('Rival', width: 120, align: TextAlign.start, flex: true),
            NeonColumn('PJ', width: 36),
            NeonColumn('V-D-E', width: 64),
            NeonColumn('WR%', width: 50),
          ],
          rows: [
            for (final o in list)
              NeonTableRow(
                onTap: () => context.push('/jugadores/${o.playerId}'),
                accent: o.record.wins > o.record.losses
                    ? AppColors.win
                    : o.record.losses > o.record.wins
                        ? AppColors.loss
                        : null,
                cells: [
                  Text(o.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${o.record.played}'),
                  Text('${o.record}'),
                  Text('${(o.record.winrate * 100).round()}%'),
                ],
              ),
          ],
        ),
        if (widget.opponents.length > _initial)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Ver menos' : 'Ver todos (${widget.opponents.length})'),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('Récord del mazo contra cada jugador (en verde, el mazo le gana).',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

/// Partidas del mazo, de la más reciente a la más antigua (las 30 últimas,
/// con "Ver todas").
class _GamesList extends StatefulWidget {
  const _GamesList({required this.games});

  final List<DeckGameRow> games;

  @override
  State<_GamesList> createState() => _GamesListState();
}

class _GamesListState extends State<_GamesList> {
  static const _initial = 30;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final day = DateFormat('dd/MM', 'es');
    final list = _all ? widget.games : widget.games.take(_initial).toList();
    return Column(
      children: [
        for (final g in list)
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: switch (g.outcome) {
                'W' => AppColors.win,
                'L' => AppColors.loss,
                _ => AppColors.draw,
              },
              child: Text(switch (g.outcome) { 'W' => 'V', 'L' => 'D', _ => 'E' },
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onPrimary)),
            ),
            title: Text('${g.playerName} vs ${g.opponentName}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${g.opponentDeckName ?? 'Sin mazo'} · ${g.tournamentName} · '
              '${g.isTopCut ? 'Top' : 'R${g.round}'} · ${day.format(g.date)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (widget.games.length > _initial)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Ver menos' : 'Ver todas (${widget.games.length})'),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.deck, required this.season});

  final DeckSeasonStats deck;
  final String season;

  @override
  Widget build(BuildContext context) {
    String pct(double v) => '${(v * 100).round()} %';
    Widget stat(String label, String value) => Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.neon)),
            Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        );
    return NeonCard(
      child: Column(
        children: [
          Row(
            children: [
              DeckImage(path: deck.imagePath, name: deck.name, width: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deck.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(season.isEmpty ? 'Puesto ${deck.rank}' : '$season · puesto ${deck.rank}',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              TierBadge(deck.tier, size: 36),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              stat('Power', '${deck.power}'),
              stat('Presencia', pct(deck.presence)),
              stat('Conversión', pct(deck.conversion)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              stat('Inscripciones', '${deck.entries}'),
              stat('Pilotos', '${deck.pilots.length}'),
              stat('Tops', '${deck.topEntries}'),
              stat('Títulos', '${deck.titles}'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Partidas: ${deck.wins}-${deck.losses}-${deck.swissDraws} '
            '(${deck.played == 0 ? '-' : pct(deck.winrate)} de victorias)',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Entries extends ConsumerWidget {
  const _Entries({required this.seasonId, required this.deckId});

  final String seasonId;
  final String deckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = DateFormat('dd/MM/yyyy');
    return AsyncView(
      value: ref.watch(_deckEntriesProvider((seasonId, deckId))),
      builder: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sin torneos terminados con este mazo.',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return Column(
          children: [
            for (final e in list)
              ListTile(
                dense: true,
                onTap: () => context.push('/jugadores/${e.playerId}'),
                leading: SizedBox(
                  width: 40,
                  child: Text(e.finalPosition == null ? '-' : '${e.finalPosition}º',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: e.madeTop ? AppColors.neon : AppColors.textSecondary,
                      )),
                ),
                title: Text(e.playerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${e.tournamentName} · ${day.format(e.date)}'),
                trailing: e.power > 0
                    ? Text('+${e.power}',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, color: AppColors.neon))
                    : null,
              ),
          ],
        );
      },
    );
  }
}
