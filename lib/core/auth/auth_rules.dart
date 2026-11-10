/// Reglas de las cuentas (las mismas que aplicará el servidor).
abstract final class AuthRules {
  /// La sesión guardada en el teléfono dura 30 días, aunque no haya conexión.
  static const sessionDays = 30;

  /// Código de 6 dígitos al Gmail, válido 15 minutos.
  static const codeLength = 6;
  static const codeMinutes = 15;

  /// Máximo 5 intentos por código y 3 códigos por hora.
  static const maxCodeAttempts = 5;
  static const maxCodesPerHour = 3;

  /// Espera mínima entre "Reenviar código".
  static const resendSeconds = 60;

  static const minPassword = 8;
  static const minUsername = 3;
  static const maxUsername = 20;

  static final _username = RegExp(r'^[a-z0-9_.]+$');
  static final _gmail = RegExp(r'^[a-z0-9.+_-]+@gmail\.com$');

  /// Usuario tal como se guarda y se compara: sin espacios y en minúsculas.
  static String normalizeUsername(String s) => s.trim().toLowerCase();

  /// Gmail normalizado (minúsculas, sin espacios; googlemail → gmail).
  static String normalizeEmail(String s) =>
      s.trim().toLowerCase().replaceFirst(RegExp(r'@googlemail\.com$'), '@gmail.com');

  /// ¿Parece un correo (para el inicio de sesión con usuario o Gmail)?
  static bool looksLikeEmail(String s) => s.contains('@');

  static String? validateUsername(String raw) {
    final s = normalizeUsername(raw);
    if (s.length < minUsername) return 'El usuario debe tener al menos $minUsername caracteres';
    if (s.length > maxUsername) return 'El usuario puede tener como máximo $maxUsername caracteres';
    if (!_username.hasMatch(s)) {
      return 'Usa solo letras sin tilde, números, punto o guion bajo';
    }
    return null;
  }

  static String? validateEmail(String raw) {
    final s = normalizeEmail(raw);
    if (s.isEmpty) return 'Escribe tu Gmail';
    if (!_gmail.hasMatch(s)) return 'Tiene que ser un correo de Gmail (…@gmail.com)';
    return null;
  }

  static String? validatePassword(String s) {
    if (s.length < minPassword) {
      return 'La contraseña debe tener al menos $minPassword caracteres';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'[0-9]').hasMatch(s)) {
      return 'La contraseña debe tener letras y números';
    }
    return null;
  }

  static String? validateNickname(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'Escribe tu apodo';
    if (t.length > 30) return 'El apodo puede tener como máximo 30 caracteres';
    return null;
  }

  /// Teléfono opcional: vacío o solo dígitos (con + delante), 8 a 15.
  static String? validatePhone(String s) {
    final t = s.replaceAll(RegExp(r'[\s-]'), '');
    if (t.isEmpty) return null;
    if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(t)) return 'Teléfono no válido';
    return null;
  }

  static String? validateCode(String s) {
    if (!RegExp('^[0-9]{$codeLength}\$').hasMatch(s.trim())) {
      return 'El código tiene $codeLength dígitos';
    }
    return null;
  }
}
