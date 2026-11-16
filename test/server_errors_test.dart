import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/auth/account.dart';
import 'package:garaje_tcg/core/auth/auth_api.dart';
import 'package:garaje_tcg/core/auth/http_auth_api.dart';

/// Un fallo del servidor NO debe cerrar la sesión: solo un 401/404.
void main() {
  late HttpServer server;
  late HttpAuthApi api;
  var status = 200;
  var body = '{}';
  var type = ContentType.json;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response
        ..statusCode = status
        ..headers.contentType = type
        ..write(body)
        ..close();
    });
    api = HttpAuthApi('http://127.0.0.1:${server.port}', timeout: const Duration(seconds: 3));
  });
  tearDownAll(() => server.close(force: true));
  setUp(HttpAuthApi.clearCache);

  Future<Object> fail() async {
    try {
      await api.request('GET', 'v1/me', token: 't');
    } catch (e) {
      return e;
    }
    throw StateError('no falló');
  }

  test('página de error de Cloudflare (CPU, límite del plan): temporal, sin cerrar sesión', () async {
    status = 503;
    type = ContentType.html;
    body = '<html>Error 1102 Worker exceeded resource limits</html>';
    final e = await fail();
    expect(e, isA<AuthNetworkException>());
  });

  test('error 500 del servidor: temporal', () async {
    status = 500;
    type = ContentType.json;
    body = '{"error":"Error del servidor. Inténtalo de nuevo."}';
    expect(await fail(), isA<AuthNetworkException>());
  });

  test('401 (sesión vencida o anulada): sí cierra la sesión', () async {
    status = 401;
    type = ContentType.json;
    body = '{"error":"La sesión venció."}';
    final e = await fail();
    expect(e, isA<AuthException>());
    expect((e as AuthException).sessionInvalid, isTrue);
  });

  test('429 (demasiados intentos): no cierra la sesión', () async {
    status = 429;
    type = ContentType.json;
    body = '{"error":"Demasiados intentos."}';
    final e = await fail() as AuthException;
    expect(e is AuthNetworkException, isFalse);
    expect(e.sessionInvalid, isFalse);
  });
}
