import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tournaments/application/tournament_service.dart';
import '../../features/tournaments/domain/game_score.dart';
import '../auth/account.dart';
import '../auth/auth_providers.dart';
import '../auth/http_auth_api.dart';
import '../db/app_database.dart';
import '../sync/sync_service.dart';

/// Marcador de un reporte, visto desde el jugador 1 de la mesa.
class ReportScore {
  const ReportScore(this.g1, this.gd, this.g2);

  factory ReportScore.fromJson(Map<String, Object?> j) => ReportScore(
        (j['g1'] as num).toInt(),
        (j['gd'] as num?)?.toInt() ?? 0,
        (j['g2'] as num).toInt(),
      );

  final int g1;
  final int gd;
  final int g2;

  GameScore get game => GameScore(g1, gd, g2);

  /// "2-1" visto desde quien pregunta ([asP1] = es el jugador 1).
  String label({required bool asP1}) {
    final mine = asP1 ? g1 : g2;
    final theirs = asP1 ? g2 : g1;
    return gd > 0 ? '$mine-$gd-$theirs' : '$mine-$theirs';
  }

  /// "Ganas 2-1" / "Pierdes 1-2" / "Empate 1-1-1".
  String outcome({required bool asP1}) {
    final mine = asP1 ? g1 : g2;
    final theirs = asP1 ? g2 : g1;
    if (mine == theirs) return 'Empate ${label(asP1: asP1)}';
    return '${mine > theirs ? 'Ganas' : 'Pierdes'} ${label(asP1: asP1)}';
  }

  @override
  bool operator ==(Object other) =>
      other is ReportScore && other.g1 == g1 && other.gd == gd && other.g2 == g2;

  @override
  int get hashCode => Object.hash(g1, gd, g2);
}

enum PlayKind { report, judge, drop }

enum PlayStatus { proposed, confirmed, disputed, open, done, cancelled }

/// Un aviso desde la mesa: resultado reportado, llamada al juez o drop.
class PlayAction {
  const PlayAction({
    required this.id,
    required this.tournamentId,
    required this.matchId,
    required this.playerId,
    required this.nickname,
    required this.kind,
    required this.score,
    required this.otherScore,
    required this.note,
    required this.status,
    required this.createdAt,
  });

  factory PlayAction.fromJson(Map<String, Object?> j) => PlayAction(
        id: j['id']! as String,
        tournamentId: j['tournamentId']! as String,
        matchId: j['matchId'] as String?,
        playerId: j['playerId']! as String,
        nickname: j['nickname'] as String?,
        kind: PlayKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => PlayKind.judge),
        score: j['score'] is Map ? ReportScore.fromJson((j['score']! as Map).cast<String, Object?>()) : null,
        otherScore: j['otherScore'] is Map
            ? ReportScore.fromJson((j['otherScore']! as Map).cast<String, Object?>())
            : null,
        note: j['note'] as String?,
        status: PlayStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => PlayStatus.open),
        createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? DateTime.now(),
      );

  final String id;
  final String tournamentId;
  final String? matchId;

  /// Ficha de quien lo envió.
  final String playerId;
  final String? nickname;
  final PlayKind kind;

  /// Lo que reportó quien lo envió (y lo que dice el rival si no coincide).
  final ReportScore? score;
  final ReportScore? otherScore;
  final String? note;
  final PlayStatus status;
  final DateTime createdAt;
}

class PlayApi {
  PlayApi(this._api, this._session);

  final HttpAuthApi _api;
  final Session _session;

  Future<Map<String, Object?>> _call(String method, String path, [Map<String, Object?>? body]) =>
      _api.request(method, path, body: body, token: _session.token);

  static PlayAction _one(Map<String, Object?> d) =>
      PlayAction.fromJson((d['action']! as Map).cast<String, Object?>());

  static List<PlayAction> _list(Map<String, Object?> d) => [
        for (final a in (d['actions'] as List?) ?? const []) PlayAction.fromJson((a as Map).cast<String, Object?>()),
      ];

  String _q(String s) => Uri.encodeQueryComponent(s);
  String _p(String s) => Uri.encodeComponent(s);

  Future<List<PlayAction>> mine(String tournamentId) async =>
      _list(await _call('GET', 'v1/play/mine?tournament=${_q(tournamentId)}'));

  Future<PlayAction> report(String tournamentId, String matchId, GameScore s) async =>
      _one(await _call('POST', 'v1/play/report',
          {'tournamentId': tournamentId, 'matchId': matchId, 'g1': s.p1, 'gd': s.draws, 'g2': s.p2}));

  Future<PlayAction> answer(String id, {required bool ok}) async =>
      _one(await _call('POST', 'v1/play/${_p(id)}/${ok ? 'confirm' : 'dispute'}', const {}));

  Future<PlayAction> judge(String tournamentId, {String? matchId, String? note}) async =>
      _one(await _call('POST', 'v1/play/judge', {
        'tournamentId': tournamentId,
        if (matchId != null) 'matchId': matchId,
        if (note != null && note.isNotEmpty) 'note': note,
      }));

  Future<PlayAction> drop(String tournamentId) async =>
      _one(await _call('POST', 'v1/play/drop', {'tournamentId': tournamentId}));

  Future<PlayAction> cancel(String id) async => _one(await _call('POST', 'v1/play/${_p(id)}/cancel', const {}));

  Future<List<PlayAction>> forTournament(String tournamentId) async =>
      _list(await _call('GET', 'v1/play?tournament=${_q(tournamentId)}'));

  Future<List<PlayAction>> todo() async => _list(await _call('GET', 'v1/play/todo'));

  Future<PlayAction> done(String id) async => _one(await _call('POST', 'v1/play/${_p(id)}/done', const {}));
}

final playApiProvider = Provider<PlayApi?>((ref) {
  final api = ref.watch(authApiProvider);
  final session = ref.watch(sessionProvider).value;
  if (api is! HttpAuthApi || session == null) return null;
  return PlayApi(api, session);
});

/// Mis avisos y el reporte de mi mesa en un torneo (teléfono del jugador).
final myPlayProvider = FutureProvider.autoDispose.family<List<PlayAction>, String>((ref, tournamentId) async {
  final api = ref.watch(playApiProvider);
  if (api == null) return const [];
  ref.watch(syncControllerProvider.select((s) => s.lastSync));
  return api.mine(tournamentId);
});

/// Avisos abiertos de un torneo (teléfono del organizador).
final tournamentPlayProvider =
    FutureProvider.autoDispose.family<List<PlayAction>, String>((ref, tournamentId) async {
  final api = ref.watch(playApiProvider);
  if (api == null) return const [];
  ref.watch(syncControllerProvider.select((s) => s.lastSync));
  return api.forTournament(tournamentId);
});

/// Teléfono del organizador, en cada sincronización: pone los resultados
/// confirmados por los dos jugadores (si la mesa sigue sin resultado) y
/// aplica los drops pedidos desde el móvil.
Future<int> applyPlayActions(AppDatabase db, TournamentService service, PlayApi api) async {
  var n = 0;
  for (final a in await api.todo()) {
    try {
      final t = await db.tournamentsDao.getById(a.tournamentId);
      if (t == null) continue;
      if (a.kind == PlayKind.report && a.matchId != null && a.score != null) {
        final m = await db.tournamentsDao.matchById(a.matchId!);
        if (m == null) continue;
        if (!m.result.isReported) await service.reportScore(m.id, a.score!.game);
      } else if (a.kind == PlayKind.drop) {
        if (t.status != TournamentStatus.swiss && t.status != TournamentStatus.topCut) continue;
        final reg = await db.tournamentsDao.registeredPlayers(t.id);
        final me = reg.where((r) => r.player.id == a.playerId).firstOrNull;
        if (me != null && !me.entry.dropped) {
          await db.tournamentsDao.dropPlayer(t.id, a.playerId, t.currentRound);
        }
      } else {
        continue;
      }
      await api.done(a.id);
      n++;
    } on AuthException {
      rethrow;
    } catch (_) {
      // Se reintenta en la próxima sincronización.
    }
  }
  return n;
}
