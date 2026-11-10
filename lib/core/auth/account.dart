/// Cuentas y roles (preparación para Garage TCG online).
///
/// Por ahora el "servidor" es una simulación dentro del teléfono
/// ([LocalAuthApi]); cuando exista el servidor real solo cambia la
/// implementación de [AuthApi], no estos modelos.
library;

/// Comunidad por defecto. Cada cuenta (y más adelante cada dato) lleva su
/// comunidad desde el principio para poder añadir otras sin rehacer la base.
const kDefaultCommunity = 'garaje';

/// Rol de una cuenta. El administrador lo asigna.
enum AppRole {
  /// Todo: ver todos los jugadores y fichas, asignar roles, licencias…
  admin('Administrador'),

  /// Lleva torneos (con licencia activa).
  organizer('Organizador'),

  /// Ayuda en los torneos donde el organizador lo añade (usa la licencia del
  /// organizador del torneo).
  judge('Juez'),

  /// Toda la comunidad.
  player('Jugador');

  const AppRole(this.label);
  final String label;

  static AppRole fromName(String? name) =>
      AppRole.values.firstWhere((r) => r.name == name, orElse: () => AppRole.player);
}

/// Datos públicos de una cuenta (lo que el servidor devuelve; nunca la
/// contraseña).
class Account {
  const Account({
    required this.id,
    required this.username,
    required this.email,
    required this.nickname,
    required this.role,
    required this.createdAt,
    this.phone,
    this.playerId,
    this.verified = false,
    this.communityId = kDefaultCommunity,
  });

  final String id;

  /// Usuario único (se compara sin mayúsculas).
  final String username;

  /// Gmail, único y verificado.
  final String email;
  final String nickname;
  final String? phone;
  final AppRole role;

  /// Ficha de jugador vinculada (la vincula el administrador).
  final String? playerId;
  final bool verified;
  final String communityId;
  final DateTime createdAt;

  Account copyWith({
    AppRole? role,
    String? playerId,
    bool clearPlayer = false,
    bool? verified,
    String? nickname,
    String? phone,
  }) =>
      Account(
        id: id,
        username: username,
        email: email,
        nickname: nickname ?? this.nickname,
        phone: phone ?? this.phone,
        role: role ?? this.role,
        playerId: clearPlayer ? null : (playerId ?? this.playerId),
        verified: verified ?? this.verified,
        communityId: communityId,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'nickname': nickname,
        'phone': phone,
        'role': role.name,
        'playerId': playerId,
        'verified': verified,
        'communityId': communityId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Account.fromJson(Map<String, Object?> j) => Account(
        id: j['id']! as String,
        username: j['username']! as String,
        email: j['email']! as String,
        nickname: (j['nickname'] as String?) ?? j['username']! as String,
        phone: j['phone'] as String?,
        role: AppRole.fromName(j['role'] as String?),
        playerId: j['playerId'] as String?,
        verified: (j['verified'] as bool?) ?? false,
        communityId: (j['communityId'] as String?) ?? kDefaultCommunity,
        createdAt: DateTime.parse(j['createdAt']! as String),
      );
}

/// Sesión iniciada en el teléfono. Dura [AuthRules.sessionDays] días y
/// funciona sin conexión.
class Session {
  const Session({required this.token, required this.account, required this.expiresAt});

  final String token;
  final Account account;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  Session withAccount(Account a) => Session(token: token, account: a, expiresAt: expiresAt);

  Map<String, Object?> toJson() => {
        'token': token,
        'account': account.toJson(),
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory Session.fromJson(Map<String, Object?> j) => Session(
        token: j['token']! as String,
        account: Account.fromJson((j['account']! as Map).cast<String, Object?>()),
        expiresAt: DateTime.parse(j['expiresAt']! as String),
      );
}

/// Error de cuentas con un mensaje para mostrar tal cual.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
