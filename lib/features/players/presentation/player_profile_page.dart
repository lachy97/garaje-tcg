import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../app/widgets/neon_table.dart';
import '../../../core/db/app_database.dart';
import '../data/player_profile_repository.dart';
import '../domain/player_profile.dart';
import 'players_page.dart' show showPlayerForm;

/// Perfil del jugador: datos personales, resumen, mazos usados y el historial
/// completo de partidas (rival, fase y resultado), agrupado por torneo.
class PlayerProfilePage extends ConsumerWidget {
  const PlayerProfilePage({super.key, required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerByIdProvider(playerId));
    final profile = ref.watch(playerProfileProvider(playerId));

    return AsyncView(
      value: player,
      builder: (p) {
        if (p == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.person_off, title: 'Jugador no encontrado'),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(p.nickname.toUpperCase(), overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Editar datos',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showPlayerForm(context, ref, player: p),
              ),
            ],
          ),
          body: AsyncView(
            value: profile,
            builder: (data) => ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _Header(player: p),
                _StatsGrid(totals: data.totals),
                const SectionLabel('Mazos usados'),
                if (data.decks.isEmpty)
                  const _Empty('Todavía no ha jugado con ningún mazo.')
                else
                  _DecksTable(decks: data.decks),
                const SectionLabel('Historial de partidas'),
                if (data.tournaments.isEmpty)
                  const _Empty('Aún no ha participado en torneos.')
                else
                  for (final t in data.tournaments)
                    _TournamentHistory(
                      tournament: t,
                      matches: data.historyByTournament[t.tournamentId] ?? const [],
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────── Cabecera ─────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final since = DateFormat.yMMMd('es').format(p.createdAt);
    return NeonCard(
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.forest,
                foregroundColor: AppColors.neon,
                child: Text(p.nickname.characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nickname,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.neon,
                          shadows: AppColors.textGlow(blur: 8),
                        )),
                    if (p.fullName != null)
                      Text(p.fullName!, style: const TextStyle(fontSize: 15)),
                    Text('Registrado desde $since',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (p.konamiId != null || p.phone != null || p.notes != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
          ],
          if (p.konamiId != null) _InfoLine(icon: Icons.badge_outlined, text: 'Konami ID: ${p.konamiId}'),
          if (p.phone != null) _InfoLine(icon: Icons.phone_outlined, text: p.phone!),
          if (p.notes != null) _InfoLine(icon: Icons.notes, text: p.notes!),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.leaf),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

// ───────────────────────── Resumen ─────────────────────────

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.totals});

  final ProfileTotals totals;

  @override
  Widget build(BuildContext context) {
    final t = totals;
    final tiles = [
      ('Torneos', '${t.tournaments}'),
      ('Partidas', '${t.played}'),
      ('V-D-E', '${t.wins}-${t.losses}-${t.draws}'),
      ('Winrate', t.played == 0 ? '—' : '${(t.winrate * 100).toStringAsFixed(0)}%'),
      ('Títulos', '${t.titles}'),
      ('Mejor puesto', t.bestPosition == null ? '—' : '${t.bestPosition}º'),
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
                border: Border.all(color: AppColors.outline, width: 0.8),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.neon)),
                  const SizedBox(height: 2),
                  Text(label.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── Mazos ─────────────────────────

class _DecksTable extends StatelessWidget {
  const _DecksTable({required this.decks});

  final List<DeckUsage> decks;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy', 'es');
    return NeonTable(
      columns: const [
        NeonColumn('Mazo', width: 120, align: TextAlign.start, flex: true),
        NeonColumn('Usado', width: 50),
        NeonColumn('PJ', width: 36),
        NeonColumn('V', width: 30),
        NeonColumn('D', width: 30),
        NeonColumn('E', width: 30),
        NeonColumn('WR%', width: 50),
        NeonColumn('Último', width: 70),
      ],
      rows: [
        for (final d in decks)
          NeonTableRow(cells: [
            Text(d.deck,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${d.tournaments}×', style: const TextStyle(color: AppColors.neon)),
            Text('${d.played}'),
            Text('${d.wins}', style: const TextStyle(color: AppColors.win)),
            Text('${d.losses}', style: const TextStyle(color: AppColors.loss)),
            Text('${d.draws}', style: const TextStyle(color: AppColors.draw)),
            Text(d.played == 0 ? '—' : '${(d.winrate * 100).toStringAsFixed(0)}%'),
            Text(d.lastUsed == null ? '—' : fmt.format(d.lastUsed!),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
      ],
    );
  }
}

// ───────────────────────── Historial ─────────────────────────

class _TournamentHistory extends StatelessWidget {
  const _TournamentHistory({required this.tournament, required this.matches});

  final TournamentEntry tournament;
  final List<HistoryEntry> matches;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final date = DateFormat.yMMMd('es').format(t.date);
    final String place;
    if (t.finished && t.finalPosition != null) {
      place = t.finalPosition == 1 ? 'Campeón' : '${t.finalPosition}º puesto';
    } else if (t.dropped) {
      place = 'Drop';
    } else {
      place = t.finished ? '—' : 'En juego';
    }

    return NeonCard(
      glow: t.finished && t.finalPosition == 1,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text('$date · ${t.deck ?? 'Sin mazo'}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text(place,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: t.finished && (t.finalPosition ?? 99) <= 4
                        ? AppColors.neon
                        : AppColors.textSecondary,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          if (matches.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Sin partidas registradas',
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            for (final m in matches) _MatchLine(entry: m),
        ],
      ),
    );
  }
}

class _MatchLine extends StatelessWidget {
  const _MatchLine({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final (label, color) = switch (e.outcome) {
      Outcome.win => ('V', AppColors.win),
      Outcome.loss => ('D', AppColors.loss),
      Outcome.draw => ('E', AppColors.draw),
      Outcome.bye => ('BYE', AppColors.leaf),
      Outcome.pending => ('…', AppColors.textDisabled),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.outlineVariant, width: 0.6)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(e.phaseLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: e.phase == RoundPhase.topCut ? AppColors.neon : AppColors.textSecondary,
                )),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.opponentName == null ? 'BYE (sin rival)' : 'vs ${e.opponentName}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (e.opponentDeck != null)
                  Text(e.opponentDeck!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (e.score != null && e.outcome != Outcome.bye)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(e.score.toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}
