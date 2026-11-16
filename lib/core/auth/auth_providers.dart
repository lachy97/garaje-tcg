import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'auth_api.dart';
import 'http_auth_api.dart';
import 'local_auth_api.dart';
import 'permissions.dart';
import 'server_config.dart';

/// Servidor de cuentas: el real si [kServerUrl] tiene dirección; si no, la
/// simulación dentro del teléfono.
final authApiProvider = Provider<AuthApi>((ref) {
  if (kServerUrl.isNotEmpty) return HttpAuthApi(kServerUrl);
  return LocalAuthApi(
    _LazyFileStore(),
    isAdminDevice: () async => false,
  );
});

/// Archivo de la simulación en la carpeta de soporte de la app.
class _LazyFileStore implements AuthStore {
  FileAuthStore? _inner;

  Future<FileAuthStore> _get() async =>
      _inner ??= FileAuthStore(File('${(await getApplicationSupportDirectory()).path}/auth_sim.json'));

  @override
  Future<Map<String, Object?>?> load() async => (await _get()).load();

  @override
  Future<void> save(Map<String, Object?> data) async => (await _get()).save(data);
}

const _kSession = 'auth.session';

/// Último usuario o Gmail con el que se inició sesión en este teléfono.
const kLastLoginKey = 'auth.lastLogin';

/// Sesión iniciada en este teléfono (null = sin cuenta, modo local).
/// Se guarda 30 días y funciona sin conexión.
class SessionController extends AsyncNotifier<Session?> {
  DateTime? _lastRefresh;

  @override
  Future<Session?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSession);
    if (raw == null) return null;
    try {
      final s = Session.fromJson(jsonDecode(raw) as Map<String, Object?>);
      if (s.isExpired(DateTime.now())) {
        await prefs.remove(_kSession);
        return null;
      }
      // Al abrir la app: rol y ficha al día (si hay conexión).
      Future(refreshAccount);
      return s;
    } catch (_) {
      await prefs.remove(_kSession);
      return null;
    }
  }

  Future<void> _store(Session? s) async {
    final prefs = await SharedPreferences.getInstance();
    if (s == null) {
      await prefs.remove(_kSession);
    } else {
      await prefs.setString(_kSession, jsonEncode(s.toJson()));
    }
    state = AsyncData(s);
  }

  AuthApi get _api => ref.read(authApiProvider);

  Future<void> login(String identifier, String password) async {
    final session = await _api.login(identifier: identifier, password: password);
    // Para rellenar "Usuario o Gmail" la próxima vez.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLastLoginKey, identifier.trim());
    await _store(session);
  }

  Future<void> verify(String email, String code) async =>
      _store(await _api.verifyEmail(email: email, code: code));

  Future<void> logout() async {
    final s = state.value;
    if (s != null) {
      try {
        await _api.logout(s);
      } catch (_) {
        // Sin conexión: la sesión del teléfono se borra igual.
      }
    }
    ref.read(rolePreviewProvider.notifier).set(null);
    // Al cerrar sesión se vuelve a la pantalla de inicio.
    await VisitorMode.set(false);
    await _store(null);
  }

  /// Cierra la sesión en todos los teléfonos de la cuenta (necesita
  /// conexión) y en este.
  Future<void> logoutAll() async {
    final s = state.value;
    final api = _api;
    if (s != null && api is HttpAuthApi) {
      await api.request('POST', 'v1/auth/logout-all', body: const {}, token: s.token);
    }
    await logout();
  }

  /// Trae del servidor el rol y la ficha vinculada y renueva la sesión por
  /// 30 días más (si hay conexión). Se llama al abrir la app y al volver a ella.
  Future<void> refreshAccount({bool onlyIfStale = false}) async {
    final s = state.value;
    if (s == null) return;
    // Al volver a la app: como mucho una vez por hora.
    final now = DateTime.now();
    if (onlyIfStale && _lastRefresh != null && now.difference(_lastRefresh!).inMinutes < 60) {
      return;
    }
    _lastRefresh = now;
    try {
      await _store(await _api.renew(s));
    } on AuthNetworkException {
      // Sin conexión: se sigue con los datos guardados.
    } on AuthException catch (e) {
      // Solo si el servidor dice que la sesión ya no vale (401/404) se cierra.
      // Cualquier otro fallo (servidor caído, saturado, límite del plan,
      // versión mínima) deja la sesión como está: antes, un fallo del
      // servidor cerraba la sesión a todos a la vez.
      if (e.sessionInvalid && !HttpAuthApi.updateRequired.value) await _store(null);
    } catch (_) {
      // Sin conexión: se sigue con los datos guardados.
    }
  }

  /// Tras cambios del administrador sobre su propia cuenta.
  Future<void> updateAccount(Account a) async {
    final s = state.value;
    if (s != null && s.account.id == a.id) await _store(s.withAccount(a));
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

/// "Ver la app como…" (solo administrador): rol con el que se prueba la app.
/// null = su rol real.
class RolePreview extends Notifier<AppRole?> {
  @override
  AppRole? build() => null;

  void set(AppRole? role) => state = role;
}

final rolePreviewProvider = NotifierProvider<RolePreview, AppRole?>(RolePreview.new);

/// Permisos de quien usa el teléfono ahora.
final permissionsProvider = Provider<Permissions>((ref) {
  final session = ref.watch(sessionProvider).value;
  // Sin sesión: visitante (solo consulta).
  if (session == null) return const Permissions.visitor();
  final real = session.account.role;
  final preview = real == AppRole.admin ? ref.watch(rolePreviewProvider) : null;
  return Permissions(
    role: preview ?? real,
    playerId: session.account.playerId,
    webReadOnly: kIsWeb,
  );
});

/// Entrar sin cuenta ("Entrar como visitante"): solo consulta lo público.
/// Se lee al arrancar ([init]) para que no parpadee la pantalla de inicio.
class VisitorMode {
  VisitorMode._();

  static const _key = 'visitor.mode';
  static final on = ValueNotifier<bool>(false);

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    on.value = p.getBool(_key) ?? false;
  }

  static Future<void> set(bool v) async {
    on.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, v);
  }
}
