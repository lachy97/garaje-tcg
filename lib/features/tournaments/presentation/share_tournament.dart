import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/export/export_models.dart';
import '../../../app/export/export_sheet.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../../../app/widgets/neon_table.dart';
import '../../../app/widgets/table_export.dart';
import '../../../core/db/app_database.dart';
import '../domain/models.dart';
import '../domain/share_text.dart';

/// Marcador de un match visto desde el jugador 1, para compartir.
String? shareScoreOf(Match m) {
  if (!m.result.isReported) return null;
  final g1 = m.games1 ?? 0, gd = m.gamesDraw ?? 0, g2 = m.games2 ?? 0;
  return switch (m.result) {
    MatchResult.doubleLoss => 'Doble derrota',
    MatchResult.draw when g1 + gd + g2 == 0 => 'ID',
    MatchResult.draw => 'Empate $g1-$gd-$g2',
    _ => '$g1-$g2',
  };
}

int _winnerOf(Match m) => switch (m.result) {
      MatchResult.p1Win => 1,
      MatchResult.p2Win => 2,
      _ => 0,
    };

/// Pregunta si compartir como imagen o como texto (el texto es más ligero
/// para la conexión y se lee directo en el chat).
Future<_ShareKind?> _askKind(BuildContext context) => showModalBottomSheet<_ShareKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Texto'),
              subtitle: const Text('Ligero, se lee directo en el chat de WhatsApp'),
              onTap: () => Navigator.pop(context, _ShareKind.text),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Imagen'),
              subtitle: const Text('Tabla con el diseño de la app'),
              onTap: () => Navigator.pop(context, _ShareKind.image),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

enum _ShareKind { text, image }

Future<void> _shareText(BuildContext context, String text) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } catch (e) {
    if (context.mounted) showMessage(context, 'No se pudo compartir: $e', error: true);
  }
}

String _fileSafe(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

// ───────────────────────── Ronda ─────────────────────────

Future<void> shareRound(
  BuildContext context, {
  required Tournament tournament,
  required String roundTitle,
  required bool isTopCut,
  required List<Match> matches,
  required Map<String, String> names,
}) async {
  final kind = await _askKind(context);
  if (kind == null || !context.mounted) return;
  final sorted = [...matches]..sort((a, b) {
      // BYE al final; el resto por mesa.
      if (a.isBye != b.isBye) return a.isBye ? 1 : -1;
      return (a.tableNumber ?? 1 << 20).compareTo(b.tableNumber ?? 1 << 20);
    });
  final lines = [
    for (final m in sorted)
      ShareMatchLine(
        table: m.tableNumber,
        player1: names[m.player1Id] ?? '?',
        player2: m.isBye || m.player2Id == null ? null : names[m.player2Id] ?? '?',
        score: m.isBye ? null : shareScoreOf(m),
        winner: _winnerOf(m),
        isThirdPlace: m.isThirdPlace,
      ),
  ];
  if (kind == _ShareKind.text) {
    await _shareText(
      context,
      roundShareText(
          tournament: tournament.name, roundTitle: roundTitle, lines: lines, isTopCut: isTopCut),
    );
    return;
  }
  await runExport<ShareMatchLine>(
    context,
    ExportSpec(
      heading: '${tournament.name.toUpperCase()} · ${roundTitle.toUpperCase()}',
      items: lines,
      tableBuilder: (rows, width) => _RoundTable(lines: rows, width: width, isTopCut: isTopCut),
      legend: 'Marcador visto desde el jugador de la izquierda · en verde, el ganador',
      fileBase: 'ronda_${_fileSafe(tournament.name)}_${_fileSafe(roundTitle)}',
      shareText: '${tournament.name} · $roundTitle',
      rowHeightEstimate: 46,
    ),
  );
}

class _RoundTable extends StatelessWidget {
  const _RoundTable({required this.lines, required this.width, required this.isTopCut});

  final List<ShareMatchLine> lines;
  final double width;
  final bool isTopCut;

  @override
  Widget build(BuildContext context) {
    TextStyle nameStyle(bool winner) => TextStyle(
          fontWeight: winner ? FontWeight.w900 : FontWeight.w600,
          color: winner ? AppColors.neon : AppColors.textPrimary,
        );
    return NeonTable(
      fixedWidth: width,
      fontSize: kExportFontSize,
      rowPadding: kExportRowPadding,
      headerColor: AppColors.neon,
      columns: [
        NeonColumn(isTopCut ? 'Match' : 'Mesa', width: 64),
        const NeonColumn('Jugador 1', width: 240, align: TextAlign.end, flex: true),
        const NeonColumn('', width: 130),
        const NeonColumn('Jugador 2', width: 240, align: TextAlign.start, flex: true),
      ],
      rows: [
        for (final l in lines)
          NeonTableRow(
            highlight: l.winner != 0,
            cells: [
              Text(l.isThirdPlace ? '3º' : l.table == null ? '—' : '${l.table}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(l.player1, overflow: TextOverflow.ellipsis, style: nameStyle(l.winner == 1)),
              Text(
                l.player2 == null ? 'BYE' : l.score ?? 'vs',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: l.score == null && l.player2 != null
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
              Text(l.player2 ?? '', overflow: TextOverflow.ellipsis, style: nameStyle(l.winner == 2)),
            ],
          ),
      ],
    );
  }
}

// ───────────────────────── Clasificación ─────────────────────────

Future<void> shareStandings(
  BuildContext context, {
  required Tournament tournament,
  required List<Standing> standings,
  required Map<String, String> names,
  required Map<String, String?> decks,
  required int cut,
}) async {
  final kind = await _askKind(context);
  if (kind == null || !context.mounted) return;
  final swissPlayed = tournament.status == TournamentStatus.swiss ||
          tournament.status == TournamentStatus.draft
      ? tournament.currentRound
      : tournament.swissRounds;
  final subtitle = 'Clasificación · ronda $swissPlayed';
  if (kind == _ShareKind.text) {
    await _shareText(
      context,
      standingsShareText(
        tournament: tournament.name,
        subtitle: subtitle,
        cut: cut,
        rows: [
          for (final s in standings)
            ShareStandingLine(
              rank: s.rank,
              name: names[s.playerId] ?? '?',
              points: s.points,
              wins: s.wins,
              losses: s.losses,
              draws: s.draws,
              dropped: s.dropped,
            ),
        ],
      ),
    );
    return;
  }
  final activeIds = [for (final s in standings) if (!s.dropped) s.playerId];
  final qualified = activeIds.take(cut).toSet();
  await runExport<Standing>(
    context,
    ExportSpec(
      heading: '${tournament.name.toUpperCase()} · ${subtitle.toUpperCase()}',
      items: standings,
      tableBuilder: (rows, width) => _StandingsTable(
          rows: rows, width: width, names: names, decks: decks, qualified: qualified),
      legend: '${cut > 0 ? 'En verde, los que entran al Top $cut · ' : ''}'
          'Desempates: Puntos → OMW% → OOMW% → GW%',
      fileBase: 'clasificacion_${_fileSafe(tournament.name)}',
      shareText: '${tournament.name} · $subtitle',
      rowHeightEstimate: 46,
    ),
  );
}

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({
    required this.rows,
    required this.width,
    required this.names,
    required this.decks,
    required this.qualified,
  });

  final List<Standing> rows;
  final double width;
  final Map<String, String> names;
  final Map<String, String?> decks;
  final Set<String> qualified;

  @override
  Widget build(BuildContext context) {
    String pct(double v) => (v * 100).toStringAsFixed(1);
    return NeonTable(
      fixedWidth: width,
      fontSize: kExportFontSize,
      rowPadding: kExportRowPadding,
      headerColor: AppColors.neon,
      columns: const [
        NeonColumn('#', width: 40, align: TextAlign.start),
        NeonColumn('Jugador', width: 150, align: TextAlign.start, flex: true),
        NeonColumn('Mazo', width: 150, align: TextAlign.start),
        NeonColumn('V-D-E', width: 70),
        NeonColumn('Pts', width: 48),
        NeonColumn('OMW%', width: 66),
        NeonColumn('OOMW%', width: 72),
        NeonColumn('GW%', width: 60),
      ],
      rows: [
        for (final s in rows)
          NeonTableRow(
            highlight: qualified.contains(s.playerId),
            dim: s.dropped,
            cells: [
              Text('${s.rank}', style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(
                s.dropped ? '${names[s.playerId] ?? '?'} (drop)' : names[s.playerId] ?? '?',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: qualified.contains(s.playerId) ? AppColors.neon : null,
                ),
              ),
              Text(decks[s.playerId] ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: kExportFontSize - 2)),
              Text('${s.wins}-${s.losses}-${s.draws}'),
              Text('${s.points}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.neon)),
              Text(pct(s.omw)),
              Text(pct(s.oomw)),
              Text(s.gwp == 0 ? '-' : pct(s.gwp)),
            ],
          ),
      ],
    );
  }
}
