import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'account.dart';
import 'auth_api.dart';
import 'auth_rules.dart';

/// Cliente del servidor real (server/ · Cloudflare Workers + D1).
///
/// Si el servidor está en modo de pruebas (DEV_CODES = "1") devuelve los
/// códigos en la respuesta; se guardan en [outbox] para mostrarlos en la app
/// mientras los correos no estén configurados.
class HttpAuthApi implements AuthApi {
  HttpAuthApi(String baseUrl, {HttpClient? client, this.timeout = const Duration(seconds: 20)})
      : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _client = client ?? (HttpClient()..connectionTimeout = timeout);

  final Uri _base;
  final HttpClient _client;
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
    try {
      final req = await _client.openUrl(method, _base.resolve(path)).timeout(timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      Map<String, Object?> data;
      try {
        data = text.isEmpty ? {} : (jsonDecode(text) as Map).cast<String, Object?>();
      } on FormatException {
        throw AuthException('Respuesta inesperada del servidor (${res.statusCode}).');
      }
      if (res.statusCode >= 400) {
        if (data['code'] == 'unverified' && data['email'] is String) {
          throw UnverifiedAccountException(data['email']! as String);
        }
        throw AuthException((data['error'] as String?) ?? 'Error del servidor (${res.statusCode}).');
      }
      return data;
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw const AuthNetworkException('El servidor no responde. Revisa la conexión (o prueba con VPN).');
    } on HandshakeException {
      throw const AuthNetworkException('No se pudo conectar de forma segura con el servidor.');
    } on SocketException {
      throw const AuthNetworkException('Sin conexión con el servidor. Revisa los datos o el wifi.');
    } on HttpException catch (e) {
      throw AuthNetworkException('Error de conexión: ${e.message}');
    }
  }

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
  Future<void> register({
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
