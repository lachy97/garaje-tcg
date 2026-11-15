import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../auth/auth_api.dart';

/// Envío HTTP en Android (dart:io): el mismo que se usaba antes.
class HttpTransport {
  HttpTransport(Duration timeout) : _client = HttpClient()..connectionTimeout = timeout;

  final HttpClient _client;

  /// Devuelve (código, texto). Los fallos de red salen como
  /// [AuthNetworkException].
  Future<(int, String)> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    Duration timeout,
  ) async {
    try {
      final req = await _client.openUrl(method, uri).timeout(timeout);
      headers.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(body));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      return (res.statusCode, text);
    } on TimeoutException {
      throw const AuthNetworkException('El servidor no responde. Revisa la conexión (o prueba con VPN).');
    } on HandshakeException {
      throw const AuthNetworkException('No se pudo conectar de forma segura con el servidor.');
    } on SocketException {
      throw const AuthNetworkException(
          'Sin conexión con el servidor. Revisa los datos o el wifi, y que la VPN esté activada.');
    } on HttpException catch (e) {
      throw AuthNetworkException('Error de conexión: ${e.message}');
    }
  }
}
