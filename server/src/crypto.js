// Utilidades de cifrado con Web Crypto (Workers y Node 22).

const enc = new TextEncoder();

/** Bytes aleatorios en base64url. */
export function randomToken(bytes = 32) {
  const b = new Uint8Array(bytes);
  crypto.getRandomValues(b);
  return b64url(b);
}

/** Código numérico de [length] dígitos. */
export function randomCode(length = 6) {
  const b = new Uint32Array(length);
  crypto.getRandomValues(b);
  return Array.from(b, (x) => x % 10).join('');
}

export function b64url(bytes) {
  let s = '';
  for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function fromB64url(s) {
  const t = s.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(t + '='.repeat((4 - (t.length % 4)) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

export async function sha256(text) {
  return b64url(new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(text))));
}

/** Máximo que admite Cloudflare Workers para PBKDF2. */
export const PBKDF2_ITERATIONS = 100000;

export async function hashPassword(password, saltB64, iterations = PBKDF2_ITERATIONS) {
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, [
    'deriveBits',
  ]);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt: fromB64url(saltB64), iterations },
    key,
    256,
  );
  return b64url(new Uint8Array(bits));
}

/** Comparación en tiempo constante. */
export function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
