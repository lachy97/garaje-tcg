import 'account.dart';

/// Correo que el "servidor" habría enviado. Solo existe en la simulación
/// ([AuthApi.isSimulated]): la app lo muestra en pantalla porque todavía no
/// se envían correos de verdad.
class SentEmail {
  const SentEmail({required this.to, required this.code, required this.purpose, required this.at});

  final String to;
  final String code;

  /// 'verify' (confirmar la cuenta) o 'reset' (cambiar la contraseña).
  final String purpose;
  final DateTime at;

  Map<String, Object?> toJson() =>
      {'to': to, 'code': code, 'purpose': purpose, 'at': at.toIso8601String()};

  factory SentEmail.fromJson(Map<String, Object?> j) => SentEmail(
        to: j['to']! as String,
        code: j['code']! as String,
        purpose: j['purpose']! as String,
        at: DateTime.parse(j['at']! as String),
      );
}

/// Lo que la app necesita del servidor de cuentas. Hoy lo implementa
/// [LocalAuthApi] (simulación en el teléfono); más adelante, el cliente del
/// servidor real (Cloudflare Workers + D1) con las mismas reglas.
///
/// Todos los errores para el usuario se lanzan como [AuthException].
abstract interface class AuthApi {
  /// true = servidor simulado: los códigos no llegan al correo, se muestran.
  bool get isSimulated;

  /// Crea la cuenta (sin verificar) y envía el código al Gmail.
  /// Devuelve false si la cuenta se creó pero el correo no se pudo enviar
  /// (el administrador puede confirmarla a mano).
  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required String nickname,
    String? phone,
  });

  /// Vuelve a enviar el código de verificación.
  Future<void> resendVerification(String email);

  /// Confirma la cuenta con el código y deja la sesión iniciada.
  Future<Session> verifyEmail({required String email, required String code});

  /// Inicia sesión con usuario o Gmail y contraseña.
  Future<Session> login({required String identifier, required String password});

  /// Envía al Gmail de la cuenta un código para poner una contraseña nueva.
  /// Devuelve el Gmail (para decir a dónde llegó).
  Future<String> requestPasswordReset(String identifier);

  /// Pone la contraseña nueva con el código recibido.
  Future<void> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  });

  /// Cierra la sesión en el servidor (la del teléfono la borra la app).
  Future<void> logout(Session session);

  /// Datos actualizados de la cuenta de la sesión (rol, ficha vinculada).
  Future<Account> me(Session session);

  /// Como [me], y además renueva la sesión (vuelve a durar 30 días).
  Future<Session> renew(Session session);

  // ───────── Administrador ─────────

  Future<List<Account>> listAccounts(Session session);

  Future<Account> setRole(Session session, {required String accountId, required AppRole role});

  /// Vincula la cuenta con la ficha de jugador que ya existe (null = quitar).
  Future<Account> linkPlayer(Session session, {required String accountId, String? playerId});

  /// Código para poner contraseña nueva, para mandárselo al jugador por
  /// WhatsApp cuando el correo no llega (vale 15 minutos).
  Future<String> adminResetCode(Session session, {required String accountId});

  /// Verifica a mano una cuenta cuyo código no llegó.
  Future<Account> verifyManually(Session session, {required String accountId});

  /// Últimos correos "enviados", el más reciente primero (solo simulación;
  /// vacío en el servidor real).
  Future<List<SentEmail>> outbox();
}

/// La cuenta existe pero aún no confirmó su Gmail: hay que pedir el código.
class UnverifiedAccountException extends AuthException {
  const UnverifiedAccountException(this.email)
      : super('Confirma tu Gmail con el código que te enviamos.');
  final String email;
}

/// No se pudo hablar con el servidor (sin conexión, tiempo agotado…). La
/// sesión guardada sigue valiendo.
class AuthNetworkException extends AuthException {
  const AuthNetworkException(super.message);
}
