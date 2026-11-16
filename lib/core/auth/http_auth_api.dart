import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'account.dart';
import 'auth_api.dart';
import 'auth_rules.dart';
import '../platform/http_transport.dart' if (dart.library.js_interop) '../platform/http_transport_web.dart';

/// Cliente del servidor real (server/ · Cloudflare Workers + D1).
///
/// Si el servidor está en modo de pruebas (DEV_CODES = "1") devuelve los
/// códigos en la respuesta; se guardan en [outbox] para mostrarlos en la app
/// mientras los correos no estén configurados.
class HttpAuthApi implements AuthApi {
  HttpAuthApi(String baseUrl, {this.timeout = const Duration(seconds: 20)})
      : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _client = HttpTransport(timeout);

  /// Número de compilación de esta app (se envía en cada llamada para que el
  /// servidor pueda exigir una versión mínima). Lo pone main() al arrancar.
  static int appBuild = 0;

  /// Identificador y nombre de este teléfono (qué teléfono lleva cada torneo).
  static String? deviceId;
  static String? deviceName;

  /// El servidor pidió actualizar la app (versión demasiado vieja).
  static final updateRequired = ValueNotifier<bool>(false);

  final Uri _base;
  /// dart:io en Android; fetch del navegador en la versión web.
  final HttpTransport _client;
  final Duration timeout;
  final List<SentEmail> _dev = [];

  /// Dirección del servidor (para mostrarla en Ajustes).
  String get baseUrl => _base.toString().replaceFirst(RegExp(r'/$'), '');

  @override
  bool get isSimulated => false;

  @override
  Future<List<SentEmail>> outbox() async => _dev.reversed.toList();

  /// Llama a la API. Lanza [AuthException] con el mensaje del servidor.
  Future<Map<String, Object?>> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
  }) async {
    final headers = <String, String>{
      'accept': 'application/json',
      'x-app-build': '$appBuild',
      if (deviceId != null) 'x-device-id': deviceId!,
      // Codificado: las cabeceras no admiten tildes.
      if (deviceName != null) 'x-device-name': Uri.encodeComponent(deviceName!),
      if (token != null) 'authorization': 'Bearer $token',
    };
    final (status, text) = await _client.send(
        method, _base.resolve(path), headers, body == null ? null : jsonEncode(body), timeout);
    Map<String, Object?> data;
    try {
      data = text.isEmpty ? {} : (jsonDecode(text) as Map).cast<String, Object?>();
    } on FormatException {
      // Página de error de Cloudflare (servidor saturado, límite del plan…):
      // es temporal, como no tener conexión. La sesión NO se toca.
      throw AuthNetworkException(
          'El servidor no responde bien ahora mismo ($status). Tu sesión sigue abierta: '
          'vuelve a intentarlo en unos minutos.');
    }
    // Fallo del propio servidor: también temporal (no cierra la sesión).
    if (status >= 500) {
      throw AuthNetworkException((data['error'] as String?) ??
          'Error del servidor ($status). Tu sesión sigue abierta: inténtalo en unos minutos.');
    }
    if (status >= 400) {
      if (data['code'] == 'update_required') {
        updateRequired.value = true;
        throw AuthException((data['error'] as String?) ?? 'Actualiza la app.');
      }
      if (data['code'] == 'unverified' && data['email'] is String) {
        throw UnverifiedAccountException(data['email']! as String);
      }
      throw AuthException((data['error'] as String?) ?? 'Error del servidor ($status).', status: status);
    }
    return data;
  }

  /// Llamada a cualquier ruta de la API (la usa la sincronización).
  /// Las consultas (GET) se contestan con lo que trajo el último
  /// [prime] si es reciente: así cada ciclo de sincronización es UNA sola
  /// petición al servidor (/v1/poll) en vez de una por pantalla.
  Future<Map<String, Object?>> request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
  }) async {
    final key = '${token ?? ''}|$path';
    if (method == 'GET') {
      final hit = _cache[key];
      if (hit != null && DateTime.now().difference(hit.at) < cacheTtl) {
        if (hit.status >= 400) {
          throw AuthException((hit.data['error'] as String?) ?? 'Error del servidor (${hit.status}).',
              status: hit.status);
        }
        return hit.data;
      }
    } else if (!_keepsCache(path)) {
      // Un cambio (reportar, aceptar, confirmar…): lo guardado ya no vale.
      _cache.clear();
    }
    return _call(method, path, body: body, token: token);
  }

  /// Cuánto valen las respuestas de /v1/poll.
  static const cacheTtl = Duration(seconds: 25);
  static final Map<String, ({DateTime at, int status, Map<String, Object?> data})> _cache = {};

  static bool _keepsCache(String path) =>
      path.startsWith('v1/sync/') || path == 'v1/poll' || path == 'v1/control/beat';

  /// Guarda las respuestas de /v1/poll ({ruta: {status, data}}).
  static void prime(String? token, Map<String, Object?> results) {
    final now = DateTime.now();
    results.forEach((path, v) {
      if (v is! Map) return;
      final status = (v['status'] as num?)?.toInt() ?? 500;
      final data = v['data'];
      _cache['${token ?? ''}|$path'] = (
        at: now,
        status: status,
        data: data is Map ? data.cast<String, Object?>() : const <String, Object?>{},
      );
    });
  }

  static void clearCache() => _cache.clear();

  /// Guarda el código si el servidor está en modo de pruebas.
  void _keepDevCode(Map<String, Object?> data, String email, String purpose) {
    final code = data['devCode'];
    if (code is String) {
      _dev.add(SentEmail(
        to: AuthRules.normalizeEmail((data['email'] as String?) ?? email),
        code: code,
        purpose: purpose,
        at: DateTime.now(),
      ));
      if (_dev.length > 10) _dev.removeAt(0);
    }
  }

  static Session _session(Map<String, Object?> data) =>
      Session.fromJson((data['session']! as Map).cast<String, Object?>());

  static Account _account(Map<String, Object?> data) =>
      Account.fromJson((data['account']! as Map).cast<String, Object?>());

  /// Prueba de conexión (fase 0): tiempo de respuesta y versión.
  Future<({Duration latency, String version})> health() async {
    final sw = Stopwatch()..start();
    final data = await _call('GET', 'v1/health');
    sw.stop();
    if (data['ok'] != true) throw const AuthException('El servidor respondió con un error.');
    return (latency: sw.elapsed, version: '${data['version'] ?? '?'}');
  }

  @override
  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required String nickname,
    String? phone,
  }) async {
    final data = await _call('POST', 'v1/auth/register', body: {
      'username': username,
      'email': email,
      'password': password,
      'nickname': nickname,
      'phone': phone,
    });
    _keepDevCode(data, email, 'verify');
    return data['mailFailed'] != true;
  }

  @override
  Future<String> adminResetCode(Session session, {required String accountId}) async {
    final data = await _call(
        'POST', 'v1/admin/accounts/${Uri.encodeComponent(accountId)}/reset-code',
        body: const {}, token: session.token);
    return '${data['code']}';
  }

  @override
  Future<void> resendVerification(String email) async =>
      _keepDevCode(await _call('POST', 'v1/auth/resend', body: {'email': email}), email, 'verify');

  @override
  Future<Session> verifyEmail({required String email, required String code}) async =>
      _session(await _call('POST', 'v1/auth/verify', body: {'email': email, 'code': code}));

  @override
  Future<Session> login({required String identifier, required String password}) async =>
      _session(await _call('POST', 'v1/auth/login',
          body: {'identifier': identifier, 'password': password}));

  @override
  Future<String> requestPasswordReset(String identifier) async {
    final data = await _call('POST', 'v1/auth/password/request', body: {'identifier': identifier});
    final email = (data['email'] as String?) ?? identifier;
    _keepDevCode(data, email, 'reset');
    return email;
  }

  @override
  Future<void> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    await _call('POST', 'v1/auth/password/reset',
        body: {'identifier': identifier, 'code': code, 'newPassword': newPassword});
  }

  @override
  Future<void> logout(Session session) async {
    await _call('POST', 'v1/auth/logout', token: session.token);
  }

  @override
  Future<Account> me(Session session) async =>
      _account(await _call('GET', 'v1/me', token: session.token));

  @override
  Future<Session> renew(Session session) async {
    final data = await _call('GET', 'v1/me', token: session.token);
    // Servidores anteriores no devuelven la fecha nueva: se mantiene la de antes.
    final until = DateTime.tryParse((data['expiresAt'] as String?) ?? '');
    return Session(
      token: session.token,
      account: _account(data),
      expiresAt: until ?? session.expiresAt,
    );
  }

  @override
  Future<List<Account>> listAccounts(Session session) async {
    final data = await _call('GET', 'v1/admin/accounts', token: session.token);
    return [
      for (final a in (data['accounts'] as List?) ?? const [])
        Account.fromJson((a as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<Account> setRole(Session session, {required String accountId, required AppRole role}) async =>
      _account(await _call('POST', 'v1/admin/accounts/${Uri.encodeComponent(accountId)}/role',
          body: {'role': role.name}, token: session.token));

  @override
  Future<Account> linkPlayer(Session session, {required String accountId, String? playerId}) async =>
      _account(await _call('POST', 'v1/admin/accounts/${Uri.encodeComponent(accountId)}/player',
          body: {'playerId': playerId}, token: session.token));

  @override
  Future<Account> verifyManually(Session session, {required String accountId}) async =>
      _account(await _call('POST', 'v1/admin/accounts/${Uri.encodeComponent(accountId)}/verify',
          body: const {}, token: session.token));
}
