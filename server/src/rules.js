// Reglas de las cuentas: las mismas que lib/core/auth/auth_rules.dart.

export const SESSION_DAYS = 30;
export const CODE_LENGTH = 6;
export const CODE_MINUTES = 15;
export const MAX_CODE_ATTEMPTS = 5;
export const MAX_CODES_PER_HOUR = 3;
export const RESEND_SECONDS = 60;
export const MAX_LOGIN_FAILS = 10;
export const LOGIN_FAIL_MINUTES = 15;

export const ROLES = ['admin', 'organizer', 'judge', 'player'];

export const normalizeUsername = (s) => String(s ?? '').trim().toLowerCase();
export const normalizeEmail = (s) =>
  String(s ?? '').trim().toLowerCase().replace(/@googlemail\.com$/, '@gmail.com');
export const looksLikeEmail = (s) => String(s ?? '').includes('@');

export function validateUsername(raw) {
  const s = normalizeUsername(raw);
  if (s.length < 3) return 'El usuario debe tener al menos 3 caracteres';
  if (s.length > 20) return 'El usuario puede tener como máximo 20 caracteres';
  if (!/^[a-z0-9_.]+$/.test(s)) return 'Usa solo letras sin tilde, números, punto o guion bajo';
  return null;
}

export function validateEmail(raw) {
  const s = normalizeEmail(raw);
  if (!s) return 'Escribe tu Gmail';
  if (!/^[a-z0-9.+_-]+@gmail\.com$/.test(s)) return 'Tiene que ser un correo de Gmail (…@gmail.com)';
  return null;
}

export function validatePassword(s) {
  s = String(s ?? '');
  if (s.length < 8) return 'La contraseña debe tener al menos 8 caracteres';
  if (s.length > 128) return 'La contraseña es demasiado larga';
  if (!/[A-Za-z]/.test(s) || !/[0-9]/.test(s)) return 'La contraseña debe tener letras y números';
  return null;
}

export function validateNickname(s) {
  const t = String(s ?? '').trim();
  if (!t) return 'Escribe tu apodo';
  if (t.length > 30) return 'El apodo puede tener como máximo 30 caracteres';
  return null;
}

export const cleanPhone = (s) => String(s ?? '').replace(/[\s-]/g, '');

export function validatePhone(s) {
  const t = cleanPhone(s);
  if (!t) return null;
  if (!/^\+?[0-9]{8,15}$/.test(t)) return 'Teléfono no válido';
  return null;
}

export function validateCode(s) {
  return /^[0-9]{6}$/.test(String(s ?? '').trim()) ? null : 'El código tiene 6 dígitos';
}
