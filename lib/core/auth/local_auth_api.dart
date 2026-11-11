import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../utils/ids.dart';
import 'account.dart';
import 'auth_api.dart';
import 'auth_rules.dart';

/// Dónde guarda la simulación sus datos (un JSON).
abstract interface class AuthStore {
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> data);
}

/// En memoria (tests).
class MemoryAuthStore implements AuthStore {
  Map<String, Object?>? _data;

  @override
  Future<Map<String, Object?>?> load() async =>
      _data == null ? null : jsonDecode(jsonEncode(_data)) as Map<String, Object?>;

  @override
  Future<void> save(Map<String, Object?> data) async =>
      _data = jsonDecode(jsonEncode(data)) as Map<String, Object?>;
}

/// En un archivo del teléfono (fuera de la base de datos de torneos: no va
/// en las copias .gtcg).
class FileAuthStore implements AuthStore {
  FileAuthStore(this.file);
  final File file;

  @override
  Future<Map<String, Object?>?> load() async {
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, Object?>;
    } catch (_) {
      return null; // archivo dañado: se empieza de cero
    }
  }

  @override
  Future<void> save(Map<String, Object?> data) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }
}

/// Servidor de cuentas SIMULADO dentro del teléfono, con las mismas reglas
/// que tendrá el real: usuario y Gmail únicos, contraseña cifrada (PBKDF2),
/// código de 6 dígitos válido 15 min, 5 intentos por código y 3 códigos por
/// hora, sesión de 30 días.
///
/// Diferencias con el real: los correos no se envían (quedan en [outbox] y
/// la app muestra el código) y las cuentas solo existen en este teléfono.
/// La primera cuenta creada en el teléfono del administrador es
/// Administrador; las demás empiezan como Jugador.
class LocalAuthApi implements AuthApi {
  LocalAuthApi(
    this._store, {
    DateTime Function()? now,
    String Function()? newCode,
    Future<bool> Function()? isAdminDevice,
    int hashIterations = 20000,
  })  : _now = now ?? DateTime.now,
        _newCode = newCode ?? _randomCode,
        _isAdminDevice = isAdminDevice,
        _iterations = hashIterations;

  final AuthStore _store;
  final DateTime Function() _now;
  final String Function() _newCode;
  final Future<bool> Function()? _isAdminDevice;
  final int _iterations;

  static final _rnd = Random.secure();

  static String _randomCode() =>
      List.generate(AuthRules.codeLength, (_) => _rnd.nextInt(10)).join();

  static String _randomToken() =>
      base64Url.encode(List.generate(32, (_) => _rnd.nextInt(256))).replaceAll('=', '');

  @override
  bool get isSimulated => true;

  @override
  Future<List<SentEmail>> outbox() async => (await _load()).outbox.reversed.toList();

  // ───────────────────────── Datos ─────────────────────────

  Future<_Db> _load() async => _Db.fromJson(await _store.load());
  Future<void> _save(_Db db) => _store.save(db.toJson());

  Future<String> _hash(String password, List<int> salt) async {
    final algo = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256);
    final key = await algo.deriveKeyFromPassword(password: password, nonce: salt);
    return base64Url.encode(await key.extractBytes());
  }

  _User? _find(_Db db, String identifier) {
    final id = identifier.trim().toLowerCase();
    if (AuthRules.looksLikeEmail(id)) {
      final email = AuthRules.normalizeEmail(id);
      return db.users.where((u) => u.account.email == email).firstOrNull;
    }
    return db.users.where((u) => u.account.username == id).firstOrNull;
  }

  _User _require(_Db db, String identifier) =>
      _find(db, identifier) ??
      (throw const AuthException('No hay ninguna cuenta con ese usuario o Gmail.'));

  /// Envía (simula) un código nuevo, respetando 3 por hora.
  void _sendCode(_Db db, String email, String purpose) {
    final now = _now();
    final hourAgo = now.subtract(const Duration(hours: 1));
    db.codeLog.removeWhere((c) => c.at.isBefore(hourAgo));
    final mine = db.codeLog.where((c) => c.email == email).toList();
    if (mine.length >= AuthRules.maxCodesPerHour) {
      throw const AuthException('Ya pediste 3 códigos en la última hora. Espera un poco.');
    }
    final last = mine.isEmpty ? null : mine.map((c) => c.at).reduce((a, b) => a.isAfter(b) ? a : b);
    if (last != null && now.difference(last).inSeconds < AuthRules.resendSeconds) {
      throw const AuthException('Espera un minuto antes de pedir otro código.');
    }
    final code = _newCode();
    db.codes.removeWhere((c) => c.email == email && c.purpose == purpose);
    db.codes.add(_Code(
      email: email,
      purpose: purpose,
      code: code,
      expiresAt: now.add(const Duration(minutes: AuthRules.codeMinutes)),
    ));
    db.codeLog.add(_CodeLog(email: email, at: now));
    db.outbox.add(SentEmail(to: email, code: code, purpose: purpose, at: now));
    if (db.outbox.length > 10) db.outbox.removeAt(0);
  }

  /// Comprueba un código (5 intentos) y lo consume si es correcto.
  void _checkCode(_Db db, String email, String purpose, String code) {
    final c = db.codes.where((c) => c.email == email && c.purpose == purpose).firstOrNull;
    if (c == null) throw const AuthException('Pide un código nuevo.');
    if (_now().isAfter(c.expiresAt)) {
      db.codes.remove(c);
      throw const AuthException('El código venció (dura 15 minutos). Pide uno nuevo.');
    }
    if (c.attempts >= AuthRules.maxCodeAttempts) {
      db.codes.remove(c);
      throw const AuthException('Demasiados intentos. Pide un código nuevo.');
    }
    if (c.code != code.trim()) {
      c.attempts++;
      final left = AuthRules.maxCodeAttempts - c.attempts;
      if (left <= 0) db.codes.remove(c);
      throw AuthException(left > 0
          ? 'Código incorrecto. Te quedan $left intento(s).'
          : 'Código incorrecto. Pide un código nuevo.');
    }
    db.codes.remove(c);
  }

  Session _newSession(_Db db, Account a) {
    final token = _randomToken();
    final expires = _now().add(const Duration(days: AuthRules.sessionDays));
    db.sessions[token] = _SessionRow(accountId: a.id, expiresAt: expires);
    return Session(token: token, account: a, expiresAt: expires);
  }

  /// Cuenta de la sesión (y que no haya vencido).
  _User _bySession(_Db db, Session s) {
    final row = db.sessions[s.token];
    if (row == null || _now().isAfter(row.expiresAt)) {
      throw const AuthException('La sesión venció. Vuelve a iniciar sesión.');
    }
    return db.users.firstWhere((u) => u.account.id == row.accountId,
        orElse: () => throw const AuthException('La cuenta ya no existe.'));
  }

  _User _admin(_Db db, Session s) {
    final u = _bySession(db, s);
    if (u.account.role != AppRole.admin) {
      throw const AuthException('Solo el administrador puede hacer esto.');
    }
    return u;
  }

  _User _target(_Db db, String accountId) => db.users.firstWhere(
        (u) => u.account.id == accountId,
        orElse: () => throw const AuthException('La cuenta ya no existe.'),
      );

  // ───────────────────────── Cuenta ─────────────────────────

  @override
  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required String nickname,
    String? phone,
  }) async {
    for (final error in [
      AuthRules.validateUsername(username),
      AuthRules.validateEmail(email),
      AuthRules.validatePassword(password),
      AuthRules.validateNickname(nickname),
      AuthRules.validatePhone(phone ?? ''),
    ]) {
      if (error != null) throw AuthException(error);
    }
    final user = AuthRules.normalizeUsername(username);
    final mail = AuthRules.normalizeEmail(email);
    final db = await _load();
    if (db.users.any((u) => u.account.username == user)) {
      throw const AuthException('Ese usuario ya existe. Elige otro.');
    }
    final existing = db.users.where((u) => u.account.email == mail).firstOrNull;
    if (existing != null) {
      throw existing.account.verified
          ? const AuthException('Ya hay una cuenta con ese Gmail. Inicia sesión.')
          : UnverifiedAccountException(mail);
    }
    final makeAdmin = !db.users.any((u) => u.account.role == AppRole.admin) &&
        (await _isAdminDevice?.call() ?? false);
    final salt = List<int>.generate(16, (_) => _rnd.nextInt(256));
    final phoneClean = phone?.replaceAll(RegExp(r'[\s-]'), '');
    db.users.add(_User(
      account: Account(
        id: newId(),
        username: user,
        email: mail,
        nickname: nickname.trim(),
        phone: (phoneClean?.isEmpty ?? true) ? null : phoneClean,
        role: makeAdmin ? AppRole.admin : AppRole.player,
        createdAt: _now(),
      ),
      salt: base64Url.encode(salt),
      hash: await _hash(password, salt),
    ));
    _sendCode(db, mail, 'verify');
    await _save(db);
    return true;
  }

  @override
  Future<String> adminResetCode(Session session, {required String accountId}) async {
    final db = await _load();
    _admin(db, session);
    final u = _target(db, accountId);
    final code = _newCode();
    db.codes.removeWhere((c) => c.email == u.account.email && c.purpose == 'reset');
    db.codes.add(_Code(
      email: u.account.email,
      purpose: 'reset',
      code: code,
      expiresAt: _now().add(const Duration(minutes: AuthRules.codeMinutes)),
    ));
    await _save(db);
    return code;
  }

  @override
  Future<void> resendVerification(String email) async {
    final db = await _load();
    final u = _require(db, email);
    if (u.account.verified) throw const AuthException('Esa cuenta ya está confirmada.');
    _sendCode(db, u.account.email, 'verify');
    await _save(db);
  }

  @override
  Future<Session> verifyEmail({required String email, required String code}) async {
    final db = await _load();
    final u = _require(db, email);
    // Ya confirmada: sin código válido no se da sesión (se entra con la
    // contraseña).
    if (u.account.verified) {
      throw const AuthException('Esa cuenta ya está confirmada. Inicia sesión.');
    }
    try {
      _checkCode(db, u.account.email, 'verify', code);
    } finally {
      await _save(db); // guarda los intentos aunque falle
    }
    u.account = u.account.copyWith(verified: true);
    final s = _newSession(db, u.account);
    await _save(db);
    return s;
  }

  @override
  Future<Session> login({required String identifier, required String password}) async {
    final db = await _load();
    final u = _find(db, identifier);
    // Mismo mensaje si no existe o la contraseña no coincide.
    const wrong = AuthException('Usuario, Gmail o contraseña incorrectos.');
    if (u == null) throw wrong;
    if (await _hash(password, base64Url.decode(u.salt)) != u.hash) throw wrong;
    if (!u.account.verified) throw UnverifiedAccountException(u.account.email);
    final s = _newSession(db, u.account);
    await _save(db);
    return s;
  }

  @override
  Future<String> requestPasswordReset(String identifier) async {
    final db = await _load();
    final u = _require(db, identifier);
    _sendCode(db, u.account.email, 'reset');
    await _save(db);
    return u.account.email;
  }

  @override
  Future<void> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    final error = AuthRules.validatePassword(newPassword);
    if (error != null) throw AuthException(error);
    final db = await _load();
    final u = _require(db, identifier);
    try {
      _checkCode(db, u.account.email, 'reset', code);
    } catch (_) {
      await _save(db);
      rethrow;
    }
    final salt = List<int>.generate(16, (_) => _rnd.nextInt(256));
    u
      ..salt = base64Url.encode(salt)
      ..hash = await _hash(newPassword, salt);
    // Por seguridad se cierran las demás sesiones; con el código también
    // queda confirmado el Gmail.
    db.sessions.removeWhere((_, s) => s.accountId == u.account.id);
    u.account = u.account.copyWith(verified: true);
    await _save(db);
  }

  @override
  Future<void> logout(Session session) async {
    final db = await _load();
    db.sessions.remove(session.token);
    await _save(db);
  }

  @override
  Future<Account> me(Session session) async => _bySession(await _load(), session).account;

  // ───────────────────────── Administrador ─────────────────────────

  @override
  Future<List<Account>> listAccounts(Session session) async {
    final db = await _load();
    _admin(db, session);
    return [for (final u in db.users) u.account]
      ..sort((a, b) => a.username.compareTo(b.username));
  }

  @override
  Future<Account> setRole(Session session, {required String accountId, required AppRole role}) async {
    final db = await _load();
    final me = _admin(db, session);
    final u = _target(db, accountId);
    if (u.account.id == me.account.id && role != AppRole.admin) {
      throw const AuthException('No puedes quitarte el rol de administrador a ti mismo.');
    }
    u.account = u.account.copyWith(role: role);
    await _save(db);
    return u.account;
  }

  @override
  Future<Account> linkPlayer(Session session, {required String accountId, String? playerId}) async {
    final db = await _load();
    _admin(db, session);
    if (playerId != null) {
      final other = db.users
          .where((u) => u.account.playerId == playerId && u.account.id != accountId)
          .firstOrNull;
      if (other != null) {
        throw AuthException('Esa ficha ya está vinculada a @${other.account.username}.');
      }
    }
    final u = _target(db, accountId);
    u.account = playerId == null
        ? u.account.copyWith(clearPlayer: true)
        : u.account.copyWith(playerId: playerId);
    await _save(db);
    return u.account;
  }

  @override
  Future<Account> verifyManually(Session session, {required String accountId}) async {
    final db = await _load();
    _admin(db, session);
    final u = _target(db, accountId);
    u.account = u.account.copyWith(verified: true);
    db.codes.removeWhere((c) => c.email == u.account.email && c.purpose == 'verify');
    await _save(db);
    return u.account;
  }
}

// ───────────────────────── Datos guardados ─────────────────────────

class _User {
  _User({required this.account, required this.salt, required this.hash});
  Account account;
  String salt;
  String hash;

  Map<String, Object?> toJson() => {...account.toJson(), 'salt': salt, 'hash': hash};

  factory _User.fromJson(Map<String, Object?> j) =>
      _User(account: Account.fromJson(j), salt: j['salt']! as String, hash: j['hash']! as String);
}

class _Code {
  _Code({
    required this.email,
    required this.purpose,
    required this.code,
    required this.expiresAt,
    this.attempts = 0,
  });
  final String email;
  final String purpose;
  final String code;
  final DateTime expiresAt;
  int attempts;

  Map<String, Object?> toJson() => {
        'email': email,
        'purpose': purpose,
        'code': code,
        'expiresAt': expiresAt.toIso8601String(),
        'attempts': attempts,
      };

  factory _Code.fromJson(Map<String, Object?> j) => _Code(
        email: j['email']! as String,
        purpose: j['purpose']! as String,
        code: j['code']! as String,
        expiresAt: DateTime.parse(j['expiresAt']! as String),
        attempts: (j['attempts'] as int?) ?? 0,
      );
}

class _CodeLog {
  _CodeLog({required this.email, required this.at});
  final String email;
  final DateTime at;

  Map<String, Object?> toJson() => {'email': email, 'at': at.toIso8601String()};

  factory _CodeLog.fromJson(Map<String, Object?> j) =>
      _CodeLog(email: j['email']! as String, at: DateTime.parse(j['at']! as String));
}

class _SessionRow {
  _SessionRow({required this.accountId, required this.expiresAt});
  final String accountId;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {'accountId': accountId, 'expiresAt': expiresAt.toIso8601String()};

  factory _SessionRow.fromJson(Map<String, Object?> j) => _SessionRow(
      accountId: j['accountId']! as String, expiresAt: DateTime.parse(j['expiresAt']! as String));
}

class _Db {
  _Db({
    required this.users,
    required this.codes,
    required this.codeLog,
    required this.sessions,
    required this.outbox,
  });

  final List<_User> users;
  final List<_Code> codes;
  final List<_CodeLog> codeLog;
  final Map<String, _SessionRow> sessions;

  /// Correos simulados (los 10 últimos, del más antiguo al más reciente).
  final List<SentEmail> outbox;

  static List<Map<String, Object?>> _list(Object? v) =>
      [for (final e in (v as List?) ?? const []) (e as Map).cast<String, Object?>()];

  factory _Db.fromJson(Map<String, Object?>? j) => _Db(
        users: [for (final e in _list(j?['users'])) _User.fromJson(e)],
        codes: [for (final e in _list(j?['codes'])) _Code.fromJson(e)],
        codeLog: [for (final e in _list(j?['codeLog'])) _CodeLog.fromJson(e)],
        sessions: {
          for (final MapEntry(:key, :value)
              in ((j?['sessions'] as Map?) ?? const {}).cast<String, Object?>().entries)
            key: _SessionRow.fromJson((value! as Map).cast<String, Object?>()),
        },
        outbox: [for (final e in _list(j?['outbox'])) SentEmail.fromJson(e)],
      );

  Map<String, Object?> toJson() => {
        'version': 1,
        'users': [for (final u in users) u.toJson()],
        'codes': [for (final c in codes) c.toJson()],
        'codeLog': [for (final c in codeLog) c.toJson()],
        'sessions': {for (final e in sessions.entries) e.key: e.value.toJson()},
        'outbox': [for (final m in outbox) m.toJson()],
      };
}
