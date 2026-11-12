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

enum PlayKind { report, judge, drop, checkin, jresult, extension, penalty }

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
    this.extra,
    this.targetPlayer,
    this.penalty,
    this.doubleLoss = false,
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
        extra: (j['extra'] as num?)?.toInt(),
        targetPlayer: j['targetPlayer'] as String?,
        penalty: j['penalty'] as String?,
        doubleLoss: j['doubleLoss'] == true,
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

  /// Tiempo extra (minutos), jugador penalizado, tipo de penalización y
  /// resultado de juez "doble derrota".
  final int? extra;
  final String? targetPlayer;
  final String? penalty;
  final bool doubleLoss;
}

/// Cuenta que puede ser juez de un torneo.
class StaffAccount {
  const StaffAccount({required this.id, required this.username, required this.nickname, required this.role});

  factory StaffAccount.fromJson(Map<String, Object?> j) => StaffAccount(
        id: j['id']! as String,
        username: (j['username'] as String?) ?? '',
        nickname: (j['nickname'] as String?) ?? '',
        role: (j['role'] as String?) ?? '',
      );

  final String id;
  final String username;
  final String nickname;
  final String role;
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

  // Check-in y jueces

  Future<PlayAction> checkin(String tournamentId, String code) async =>
      _one(await _call('POST', 'v1/play/checkin', {'tournamentId': tournamentId, 'code': code}));

  Future<PlayAction> judgeResult(String tournamentId, String matchId, {GameScore? score, bool doubleLoss = false}) async =>
      _one(await _call('POST', 'v1/play/judge-result', {
        'tournamentId': tournamentId,
        'matchId': matchId,
        if (doubleLoss) 'doubleLoss': true,
        if (score != null) ...{'g1': score.p1, 'gd': score.draws, 'g2': score.p2},
      }));

  Future<PlayAction> extension(String tournamentId, String matchId, int minutes) async =>
      _one(await _call('POST', 'v1/play/extension',
          {'tournamentId': tournamentId, 'matchId': matchId, 'minutes': minutes}));

  Future<PlayAction> penalty(String tournamentId, String playerId, String kind, {String? reason, String? matchId}) async =>
      _one(await _call('POST', 'v1/play/penalty', {
        'tournamentId': tournamentId,
        'playerId': playerId,
        'penalty': kind,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (matchId != null) 'matchId': matchId,
      }));

  static List<StaffAccount> _staff(Object? l) => [
        for (final a in (l as List?) ?? const []) StaffAccount.fromJson((a as Map).cast<String, Object?>()),
      ];

  Future<List<StaffAccount>> candidates() async => _staff((await _call('GET', 'v1/staff/candidates'))['accounts']);

  Future<List<StaffAccount>> judges(String tournamentId) async =>
      _staff((await _call('GET', 'v1/tournaments/${_p(tournamentId)}/judges'))['judges']);

  Future<List<StaffAccount>> addJudge(String tournamentId, String accountId) async => _staff(
      (await _call('POST', 'v1/tournaments/${_p(tournamentId)}/judges', {'accountId': accountId}))['judges']);

  Future<List<StaffAccount>> removeJudge(String tournamentId, String accountId) async => _staff((await _call(
          'POST', 'v1/tournaments/${_p(tournamentId)}/judges/${_p(accountId)}/remove', const {}))['judges']);

  Future<Set<String>> judging() async => {
        for (final t in ((await _call('GET', 'v1/me/judging'))['tournaments'] as List?) ?? const []) '$t',
      };
}

/// Torneos donde esta cuenta es juez.
final judgingProvider = FutureProvider<Set<String>>((ref) async {
  final api = ref.watch(playApiProvider);
  if (api == null) return const {};
  ref.watch(syncControllerProvider.select((s) => s.lastSync));
  try {
    return await api.judging();
  } catch (_) {
    return const {};
  }
});

/// Jueces de un torneo (organizador).
final tournamentJudgesProvider =
    FutureProvider.autoDispose.family<List<StaffAccount>, String>((ref, tournamentId) async {
  final api = ref.watch(playApiProvider);
  if (api == null) return const [];
  return api.judges(tournamentId);
});

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
      } else if (a.kind == PlayKind.jresult && a.matchId != null) {
        // Lo que decide el juez manda (también sobre un resultado ya puesto).
        if (await db.tournamentsDao.matchById(a.matchId!) == null) continue;
        if (a.doubleLoss) {
          await service.reportDoubleLoss(a.matchId!);
        } else if (a.score != null) {
          await service.reportScore(a.matchId!, a.score!.game);
        }
      } else if (a.kind == PlayKind.extension && a.matchId != null) {
        if (await db.tournamentsDao.matchById(a.matchId!) == null) continue;
        await db.tournamentsDao.setExtraMinutes(a.matchId!, a.extra ?? 0);
      } else if (a.kind == PlayKind.penalty && a.targetPlayer != null) {
        final kind = PenaltyKind.values.where((k) => k.name == a.penalty).firstOrNull;
        if (kind == null) continue;
        await db.tournamentsDao.addPenalty(
          tournamentId: t.id,
          playerId: a.targetPlayer!,
          round: t.currentRound,
          kind: kind,
          reason: a.note,
        );
      } else if (a.kind == PlayKind.checkin) {
        if (t.status == TournamentStatus.draft) {
          await db.tournamentsDao.setCheckedIn(t.id, a.playerId, true);
        }
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
