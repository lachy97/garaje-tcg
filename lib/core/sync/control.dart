import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/account.dart';
import '../auth/http_auth_api.dart';
import '../utils/ids.dart';

/// Identificador de este teléfono para el servidor (qué teléfono lleva cada
/// torneo). Se crea una vez y se guarda.
class DeviceIdentity {
  DeviceIdentity._();

  static const _key = 'device.syncId';

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_key);
    if (id == null || id.isEmpty) {
      id = newId();
      await p.setString(_key, id);
    }
    HttpAuthApi.deviceId = id;
    // Nombre corto para reconocerlo: "Teléfono 3F2A".
    final hex = id.replaceAll('-', '');
    HttpAuthApi.deviceName = 'Teléfono ${hex.substring(hex.length - 4).toUpperCase()}';
  }
}

/// Quién lleva un torneo según el servidor.
class TournamentControl {
  const TournamentControl({
    required this.tournamentId,
    required this.mine,
    required this.canTake,
    this.deviceName,
    this.nickname,
    this.lastSeen,
  });

  factory TournamentControl.fromJson(Map<String, Object?> j) => TournamentControl(
        tournamentId: j['tournamentId']! as String,
        mine: j['mine'] == true,
        canTake: j['canTake'] != false,
        deviceName: j['deviceName'] as String?,
        nickname: j['nickname'] as String?,
        lastSeen: DateTime.tryParse((j['lastSeen'] as String?) ?? '')?.toLocal(),
      );

  Map<String, Object?> toJson() => {
        'tournamentId': tournamentId,
        'mine': mine,
        'canTake': canTake,
        'deviceName': deviceName,
        'nickname': nickname,
        'lastSeen': lastSeen?.toUtc().toIso8601String(),
      };

  final String tournamentId;

  /// Lo lleva este teléfono.
  final bool mine;

  /// Esta cuenta puede tomar el control (es su torneo o es administrador).
  /// Si no, es de otro organizador (p. ej. es juez): solo consulta.
  final bool canTake;
  final String? deviceName;
  final String? nickname;

  /// Última vez que el teléfono que lo lleva sincronizó.
  final DateTime? lastSeen;

  /// Este teléfono no puede cambiarlo.
  bool get locked => !mine;
}

/// Quién lleva cada torneo en juego, por id. Lo actualiza la sincronización
/// del organizador y se guarda para que, sin conexión, este teléfono no tome
/// por suyo un torneo que lleva otro.
class ControlsController extends Notifier<Map<String, TournamentControl>> {
  static const _key = 'sync.controls';

  @override
  Map<String, TournamentControl> build() {
    SharedPreferences.getInstance().then((p) {
      final raw = p.getString(_key);
      if (raw == null || !ref.mounted || state.isNotEmpty) return;
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, Object?>>();
        state = {for (final j in list) j['tournamentId']! as String: TournamentControl.fromJson(j)};
      } catch (_) {}
    });
    return const {};
  }

  Future<void> replace(Iterable<TournamentControl> list) async {
    state = {for (final c in list) c.tournamentId: c};
    await _save();
  }

  Future<void> put(TournamentControl c) async {
    state = {...state, c.tournamentId: c};
    await _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode([for (final c in state.values) c.toJson()]));
    } catch (_) {}
  }
}

final controlsProvider =
    NotifierProvider<ControlsController, Map<String, TournamentControl>>(ControlsController.new);

/// Control de un torneo (null: nadie lo reclamó o servidor sin esta función).
final tournamentControlProvider = Provider.family<TournamentControl?, String>(
  (ref, id) => ref.watch(controlsProvider)[id],
);

class ControlApi {
  ControlApi(this._api, this._session);

  final HttpAuthApi _api;
  final Session _session;

  Future<List<TournamentControl>> beat(List<String> tournamentIds) async {
    final d = await _api.request('POST', 'v1/control/beat',
        body: {'tournamentIds': tournamentIds}, token: _session.token);
    return [
      for (final c in (d['controls'] as List?) ?? const [])
        TournamentControl.fromJson((c as Map).cast<String, Object?>()),
    ];
  }

  Future<TournamentControl> take(String tournamentId) async {
    final d = await _api.request('POST', 'v1/control/take',
        body: {'tournamentId': tournamentId}, token: _session.token);
    return TournamentControl.fromJson((d['control']! as Map).cast<String, Object?>());
  }
}
