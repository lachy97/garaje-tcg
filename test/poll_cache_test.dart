import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/auth/account.dart';
import 'package:garaje_tcg/core/auth/auth_api.dart';
import 'package:garaje_tcg/core/auth/http_auth_api.dart';

/// Lo que trae /v1/poll contesta las consultas del ciclo sin salir a internet.
void main() {
  // Servidor inalcanzable: si una consulta sale a la red, falla.
  final api = HttpAuthApi('http://127.0.0.1:9', timeout: const Duration(seconds: 2));

  setUp(HttpAuthApi.clearCache);

  test('las consultas del ciclo salen de lo guardado', () async {
    HttpAuthApi.prime('tok', {
      'v1/me/judging': {'status': 200, 'data': {'tournaments': ['t1']}},
      'v1/play?tournament=t2': {'status': 403, 'data': {'error': 'No es tuyo.'}},
    });
    expect((await api.request('GET', 'v1/me/judging', token: 'tok'))['tournaments'], ['t1']);
    // Los errores también se guardan (y se lanzan igual que del servidor).
    expect(() => api.request('GET', 'v1/play?tournament=t2', token: 'tok'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', 'No es tuyo.')));
    // Otra sesión no ve lo de esta.
    expect(() => api.request('GET', 'v1/me/judging', token: 'otro'), throwsA(isA<AuthNetworkException>()));
  });

  test('un cambio (reportar, aceptar…) borra lo guardado; subir datos no', () async {
    HttpAuthApi.prime('tok', {
      'v1/me/judging': {'status': 200, 'data': {'tournaments': <String>[]}},
    });
    await expectLater(api.request('POST', 'v1/sync/push', token: 'tok', body: const {}),
        throwsA(isA<AuthNetworkException>()));
    expect(await api.request('GET', 'v1/me/judging', token: 'tok'), isNotNull);
    await expectLater(api.request('POST', 'v1/play/report', token: 'tok', body: const {}),
        throwsA(isA<AuthNetworkException>()));
    expect(() => api.request('GET', 'v1/me/judging', token: 'tok'), throwsA(isA<AuthNetworkException>()));
  });
}
