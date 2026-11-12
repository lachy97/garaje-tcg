import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../core/db/app_database.dart';
import '../application/tournament_service.dart';
import '../domain/models.dart';
import 'my_table.dart' show RoundCountdown;
import 'providers.dart';

/// Pantalla para proyectar en una TV o un portátil (como el "Mirror" de
/// EventLink): cruces de la ronda, reloj grande y clasificación, en letra
/// grande y solo lectura. Cambia sola entre cruces y clasificación (o con un
/// toque). La pantalla no se apaga mientras está abierta.
class ProjectionPage extends ConsumerStatefulWidget {
  const ProjectionPage({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  ConsumerState<ProjectionPage> createState() => _ProjectionPageState();
}

class _ProjectionPageState extends ConsumerState<ProjectionPage> {
  static const _rotateEvery = Duration(seconds: 20);

  bool _standings = false;
  bool _auto = true;
  Timer? _rotate;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable().catchError((_) {});
    _rotate = Timer.periodic(_rotateEvery, (_) {
      if (mounted && _auto) setState(() => _standings = !_standings);
    });
  }

  @override
  void dispose() {
    _rotate?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // El reloj de la ronda vuelve a pedir la pantalla encendida si hace falta.
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tournamentProvider(widget.tournamentId)).value;
    final rounds = ref.watch(roundsProvider(widget.tournamentId)).value ?? const <Round>[];
    final registered = ref.watch(registeredProvider(widget.tournamentId)).value ?? const [];
    final names = {for (final r in registered) r.player.id: r.player.nickname};
    final round = rounds.isEmpty ? null : rounds.last;
    final matches = round == null
        ? const <Match>[]
        : ref.watch(roundMatchesProvider(round.id)).value ?? const <Match>[];
    final standings = ref.watch(standingsProvider(widget.tournamentId)).value ?? const [];
    final width = MediaQuery.sizeOf(context).width;
    // Escala del texto según el ancho (TV o portátil: más grande).
    final scale = (width / 900).clamp(0.8, 2.2);

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _standings = !_standings),
          child: Padding(
            padding: EdgeInsets.all(16 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    GlowLogo(size: 56 * scale),
                    SizedBox(width: 16 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t?.name ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 26 * scale, fontWeight: FontWeight.w900)),
                          Text(
                            round == null
                                ? 'Inscripción'
                                : '${roundLabel(round)} · ${_standings ? 'Clasificación' : 'Cruces'}',
                            style: TextStyle(fontSize: 18 * scale, color: AppColors.neon, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    if (round?.timerStartedAt != null && t != null)
                      RoundCountdown(
                          start: round!.timerStartedAt!, minutes: t.roundMinutes, fontSize: 44 * scale),
                    IconButton(
                      tooltip: _auto ? 'Dejar fija esta vista' : 'Cambiar sola cada 20 s',
                      onPressed: () => setState(() => _auto = !_auto),
                      icon: Icon(_auto ? Icons.sync : Icons.sync_disabled, color: AppColors.textSecondary),
                    ),
                    IconButton(
                      tooltip: 'Salir',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                SizedBox(height: 12 * scale),
                Expanded(
                  child: _standings
                      ? _StandingsGrid(standings: standings, names: names, scale: scale)
                      : _PairingsGrid(matches: matches, names: names, scale: scale),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Columnas según el ancho, para que quepa todo sin desplazarse.
int _columns(double width, int items, double minWidth) =>
    (width / minWidth).floor().clamp(1, items < 1 ? 1 : items);

class _PairingsGrid extends StatelessWidget {
  const _PairingsGrid({required this.matches, required this.names, required this.scale});

  final List<Match> matches;
  final Map<String, String> names;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return Center(child: Text('Aún no hay cruces', style: TextStyle(fontSize: 24 * scale)));
    }
    final sorted = [...matches]..sort((a, b) {
        if (a.isBye != b.isBye) return a.isBye ? 1 : -1;
        return (a.tableNumber ?? 1 << 20).compareTo(b.tableNumber ?? 1 << 20);
      });
    return LayoutBuilder(builder: (context, c) {
      final cols = _columns(c.maxWidth, sorted.length, 420 * scale);
      final perCol = (sorted.length / cols).ceil();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var col = 0; col < cols; col++)
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 6 * scale),
                children: [
                  for (final m in sorted.skip(col * perCol).take(perCol)) _pairing(m),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _pairing(Match m) {
    final p1 = names[m.player1Id] ?? '?';
    final p2 = m.player2Id == null ? null : names[m.player2Id] ?? '?';
    final done = m.result.isReported;
    final name = TextStyle(fontSize: 20 * scale, fontWeight: FontWeight.w700);
    return Container(
      margin: EdgeInsets.only(bottom: 6 * scale),
      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: done ? AppColors.neon : AppColors.outline),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56 * scale,
            child: Text(m.isBye ? 'BYE' : '${m.tableNumber ?? ''}',
                style: TextStyle(fontSize: 24 * scale, fontWeight: FontWeight.w900, color: AppColors.neon)),
          ),
          Expanded(child: Text(p1, maxLines: 1, overflow: TextOverflow.ellipsis, style: name)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8 * scale),
            child: Text(
              m.isBye
                  ? '2-0'
                  : done && m.games1 != null
                      ? '${m.games1}-${m.games2}'
                      : 'vs',
              style: TextStyle(fontSize: 16 * scale, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(p2 ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: name),
          ),
        ],
      ),
    );
  }
}

class _StandingsGrid extends StatelessWidget {
  const _StandingsGrid({required this.standings, required this.names, required this.scale});

  final List<Standing> standings;
  final Map<String, String> names;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (standings.isEmpty) {
      return Center(child: Text('Aún no hay clasificación', style: TextStyle(fontSize: 24 * scale)));
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = _columns(c.maxWidth, standings.length, 380 * scale);
      final perCol = (standings.length / cols).ceil();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var col = 0; col < cols; col++)
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 6 * scale),
                children: [
                  for (final s in standings.skip(col * perCol).take(perCol))
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 4 * scale),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44 * scale,
                            child: Text('${s.rank}',
                                style: TextStyle(
                                    fontSize: 20 * scale, fontWeight: FontWeight.w900, color: AppColors.neon)),
                          ),
                          Expanded(
                            child: Text(
                              '${names[s.playerId] ?? '?'}${s.dropped ? ' (drop)' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 20 * scale,
                                  fontWeight: FontWeight.w700,
                                  color: s.dropped ? AppColors.textDisabled : null),
                            ),
                          ),
                          Text('${s.wins}-${s.losses}-${s.draws}',
                              style: TextStyle(fontSize: 16 * scale, color: AppColors.textSecondary)),
                          SizedBox(width: 12 * scale),
                          SizedBox(
                            width: 52 * scale,
                            child: Text('${s.points} pts',
                                textAlign: TextAlign.end,
                                style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    });
  }
}
