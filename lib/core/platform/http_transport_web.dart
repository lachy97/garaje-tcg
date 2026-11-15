import 'dart:async';

import 'package:http/http.dart' as http;

import '../auth/auth_api.dart';

/// Envío HTTP en la versión web (navegador del iPhone): fetch del navegador.
class HttpTransport {
  HttpTransport(Duration timeout);

  final http.Client _client = http.Client();

  Future<(int, String)> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    Duration timeout,
  ) async {
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        req.headers['content-type'] = 'application/json; charset=utf-8';
        req.body = body;
      }
      final res = await http.Response.fromStream(await _client.send(req).timeout(timeout)).timeout(timeout);
      return (res.statusCode, res.body);
    } on TimeoutException {
      throw const AuthNetworkException('El servidor no responde. Revisa la conexión (o prueba con VPN).');
    } on http.ClientException {
      throw const AuthNetworkException(
          'Sin conexión con el servidor. Revisa los datos o el wifi, y que la VPN esté activada.');
    }
  }
}
