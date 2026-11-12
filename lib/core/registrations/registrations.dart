import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/account.dart';
import '../auth/auth_providers.dart';
import '../auth/http_auth_api.dart';
import '../db/app_database.dart';
import '../sync/sync_service.dart';

/// Estado de una solicitud de inscripción desde la app.
enum RegistrationStatus {
  pending, // espera al organizador
  waitlist, // cupo lleno: espera a que se libere una plaza
  accepted, // aceptada; el teléfono del organizador la inscribe al sincronizar
  registered, // inscrito
  rejected,
  cancelRequested, // el jugador se borró; el organizador lo quita
  cancelled;

  static RegistrationStatus parse(String? s) => switch (s) {
        'accepted' => accepted,
        'waitlist' => waitlist,
        'registered' => registered,
        'rejected' => rejected,
        'cancel_requested' => cancelRequested,
        'cancelled' => cancelled,
        _ => pending,
      };

  /// Tiene la plaza pedida o concedida.
  bool get active =>
      this == pending || this == waitlist || this == accepted || this == registered || this == cancelRequested;
}

class RegistrationRequest {
  const RegistrationRequest({
    required this.id,
    required this.tournamentId,
    required this.accountId,
    required this.username,
    required this.nickname,
    required this.playerId,
    required this.linked,
    required this.deckName,
    required this.status,
    required this.reason,
    required this.createdAt,
    this.waitPosition,
  });

  factory RegistrationRequest.fromJson(Map<String, Object?> j) => RegistrationRequest(
        id: j['id']! as String,
        tournamentId: j['tournamentId']! as String,
        accountId: j['accountId']! as String,
        username: (j['username'] as String?) ?? '',
        nickname: (j['nickname'] as String?) ?? '',
        playerId: j['playerId'] as String?,
        linked: j['linked'] == true,
        deckName: j['deckName'] as String?,
        status: RegistrationStatus.parse(j['status'] as String?),
        reason: j['reason'] as String?,
        waitPosition: (j['waitPosition'] as num?)?.toInt(),
        createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? DateTime.now(),
      );

  final String id;
  final String tournamentId;
  final String accountId;
  final String username;
  final String nickname;

  /// Ficha con la que se inscribe (la vinculada a la cuenta, o la elegida al
  /// aceptar).
  final String? playerId;

  /// La cuenta tiene ficha vinculada.
  final bool linked;
  final String? deckName;
  final RegistrationStatus status;
  final String? reason;
  final DateTime createdAt;

  /// Puesto en la lista de espera (1 = la próxima plaza).
  final int? waitPosition;
}

/// Torneo con la inscripción desde la app abierta (según el servidor).
class OpenTournament {
  const OpenTournament({
    required this.id,
    required this.name,
    required this.date,
    required this.swissRounds,
    required this.topCutSize,
    required this.autoAccept,
    required this.enrolled,
    this.capacity,
  });

  factory OpenTournament.fromJson(Map<String, Object?> j) {
    // Las fechas de la base local se guardan en segundos desde 1970.
    final raw = j['date'];
    final date = raw is num
        ? DateTime.fromMillisecondsSinceEpoch(raw.toInt() * 1000)
        : DateTime.tryParse('$raw');
    return OpenTournament(
      id: j['id']! as String,
      name: (j['name'] as String?) ?? '',
      date: date,
      swissRounds: (j['swissRounds'] as num?)?.toInt(),
      topCutSize: (j['topCutSize'] as num?)?.toInt() ?? 0,
      autoAccept: j['autoAccept'] == true,
      enrolled: (j['enrolled'] as num?)?.toInt() ?? 0,
      capacity: (j['capacity'] as num?)?.toInt(),
    );
  }

  final String id;
  final String name;
  final DateTime? date;
  final int? swissRounds;
  final int topCutSize;
  final bool autoAccept;
  final int enrolled;

  /// Plazas (null = sin límite).
  final int? capacity;

  bool get full => capacity != null && enrolled >= capacity!;
}

class MyRegistrations {
  const MyRegistrations({required this.open, required this.requests, required this.playerId});

  final List<OpenTournament> open;

  /// Por torneo.
  final Map<String, RegistrationRequest> requests;
  final String? playerId;
}

/// Llamadas al servidor para la inscripción desde la app.
class RegistrationsApi {
  RegistrationsApi(this._api, this._session);

  final HttpAuthApi _api;
  final Session _session;

  Future<Map<String, Object?>> _call(String method, String path, [Map<String, Object?>? body]) =>
      _api.request(method, path, body: body, token: _session.token);

  static RegistrationRequest _one(Map<String, Object?> data) =>
      RegistrationRequest.fromJson((data['registration']! as Map).cast<String, Object?>());

  static List<RegistrationRequest> _list(Map<String, Object?> data) => [
        for (final r in (data['registrations'] as List?) ?? const [])
          RegistrationRequest.fromJson((r as Map).cast<String, Object?>()),
      ];

  // Jugador

  Future<MyRegistrations> mine() async {
    final data = await _call('GET', 'v1/registrations/mine');
    final requests = _list(data);
    return MyRegistrations(
      open: [
        for (final t in (data['open'] as List?) ?? const [])
          OpenTournament.fromJson((t as Map).cast<String, Object?>()),
      ],
      requests: {for (final r in requests) r.tournamentId: r},
      playerId: data['playerId'] as String?,
    );
  }

  Future<RegistrationRequest> request(String tournamentId, String deckName) async =>
      _one(await _call('POST', 'v1/registrations', {'tournamentId': tournamentId, 'deckName': deckName}));

  Future<RegistrationRequest> cancel(String id) async =>
      _one(await _call('POST', 'v1/registrations/${Uri.encodeComponent(id)}/cancel', const {}));

  // Organizador

  Future<List<RegistrationRequest>> forTournament(String tournamentId) async =>
      _list(await _call('GET', 'v1/registrations?tournament=${Uri.encodeQueryComponent(tournamentId)}'));

  Future<List<RegistrationRequest>> todo() async => _list(await _call('GET', 'v1/registrations/todo'));

  Future<RegistrationRequest> accept(String id, {String? playerId}) async => _one(await _call(
      'POST', 'v1/registrations/${Uri.encodeComponent(id)}/accept', {if (playerId != null) 'playerId': playerId}));

  Future<RegistrationRequest> reject(String id, {String? reason}) async => _one(await _call(
      'POST', 'v1/registrations/${Uri.encodeComponent(id)}/reject', {if (reason != null) 'reason': reason}));

  Future<RegistrationRequest> done(String id) async =>
      _one(await _call('POST', 'v1/registrations/${Uri.encodeComponent(id)}/done', const {}));
}

/// API de inscripciones si hay servidor real y sesión (null si no).
final registrationsApiProvider = Provider<RegistrationsApi?>((ref) {
  final api = ref.watch(authApiProvider);
  final session = ref.watch(sessionProvider).value;
  if (api is! HttpAuthApi || session == null) return null;
  return RegistrationsApi(api, session);
});

/// Torneos abiertos y mis solicitudes (teléfono del jugador).
final myRegistrationsProvider = FutureProvider.autoDispose<MyRegistrations?>((ref) async {
  final api = ref.watch(registrationsApiProvider);
  if (api == null) return null;
  // Se vuelve a pedir tras cada sincronización (cada 30 s con la app abierta).
  ref.watch(syncControllerProvider.select((s) => s.lastSync));
  final mine = await api.mine();
  // Si el organizador vinculó la ficha al aceptar, se actualiza la cuenta
  // (y el teléfono vuelve a bajar los datos con la ficha).
  final session = ref.read(sessionProvider).value;
  if (session != null && mine.playerId != session.account.playerId) {
    await ref.read(sessionProvider.notifier).refreshAccount();
  }
  return mine;
});

/// Solicitudes de un torneo (teléfono del organizador).
final tournamentRequestsProvider =
    FutureProvider.autoDispose.family<List<RegistrationRequest>, String>((ref, tournamentId) async {
  final api = ref.watch(registrationsApiProvider);
  if (api == null) return const [];
  ref.watch(syncControllerProvider.select((s) => s.lastSync));
  return api.forTournament(tournamentId);
});

/// Inscribe en la base local las solicitudes aceptadas y quita las bajas
/// (teléfono del organizador, en cada sincronización). Devuelve cuántas
/// procesó. Las que no se pueden (ficha que no está en este teléfono,
/// torneo ya empezado) se dejan para otra vez.
Future<int> applyAcceptedRegistrations(AppDatabase db, RegistrationsApi api) async {
  final todo = await api.todo();
  var n = 0;
  for (final r in todo) {
    try {
      final t = await db.tournamentsDao.getById(r.tournamentId);
      if (t == null || t.status != TournamentStatus.draft) continue;
      final playerId = r.playerId;
      if (playerId == null) continue;
      if (r.status == RegistrationStatus.accepted) {
        final player = await db.playersDao.getById(playerId);
        if (player == null || player.deletedAt != null) continue;
        await db.tournamentsDao.registerPlayer(t.id, playerId, deckName: r.deckName);
      } else if (r.status == RegistrationStatus.cancelRequested) {
        await db.tournamentsDao.unregisterPlayer(t.id, playerId);
      } else {
        continue;
      }
      await api.done(r.id);
      n++;
    } on AuthException {
      rethrow;
    } catch (_) {
      // Esta no se pudo: se reintenta en la próxima sincronización.
    }
  }
  return n;
}
