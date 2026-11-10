// Lógica de cuentas sobre D1. La usa el router (index.js) y los tests.
import {
  hashPassword,
  randomCode,
  randomToken,
  safeEqual,
  sha256,
} from './crypto.js';
import { mailConfigured, sendCode } from './mail.js';
import * as R from './rules.js';

/** Error para mostrar al usuario tal cual. */
export class ApiError extends Error {
  constructor(status, message, extra = {}) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}

const bad = (m) => new ApiError(400, m);

const MIN = 60 * 1000;

/** Cuenta tal como la ve la app (lib/core/auth/account.dart). */
export function publicAccount(row) {
  return {
    id: row.id,
    username: row.username,
    email: row.email,
    nickname: row.nickname,
    phone: row.phone ?? null,
    role: row.role,
    playerId: row.player_id ?? null,
    verified: Boolean(row.verified),
    communityId: row.community_id,
    createdAt: row.created_at,
  };
}

export class AuthService {
  /**
   * @param {object} env  DB (D1), ADMIN_EMAIL, DEV_CODES, BREVO_API_KEY, MAIL_FROM…
   * @param {object} [opts] now(): ms; newCode(); send(to, code, purpose); iterations
   */
  constructor(env, opts = {}) {
    this.env = env;
    this.db = env.DB;
    this.now = opts.now ?? (() => Date.now());
    this.newCode = opts.newCode ?? (() => randomCode(R.CODE_LENGTH));
    this.send = opts.send ?? ((to, code, purpose) => sendCode(env, to, code, purpose));
    this.iterations = opts.iterations;
    this.devCodes = env.DEV_CODES === '1';
  }

  // ───────────────────── Datos ─────────────────────

  async findBy(identifier) {
    const id = String(identifier ?? '').trim().toLowerCase();
    if (!id) return null;
    if (R.looksLikeEmail(id)) {
      return this.db.prepare('SELECT * FROM accounts WHERE email = ?').bind(R.normalizeEmail(id)).first();
    }
    return this.db.prepare('SELECT * FROM accounts WHERE username = ?').bind(id).first();
  }

  async require(identifier) {
    const a = await this.findBy(identifier);
    if (!a) throw new ApiError(404, 'No hay ninguna cuenta con ese usuario o Gmail.');
    return a;
  }

  async byId(id) {
    const a = await this.db.prepare('SELECT * FROM accounts WHERE id = ?').bind(id).first();
    if (!a) throw new ApiError(404, 'La cuenta ya no existe.');
    return a;
  }

  hash(password, salt) {
    return hashPassword(password, salt, this.iterations);
  }

  iso() {
    return new Date(this.now()).toISOString();
  }

  // ───────────────────── Códigos ─────────────────────

  /** Crea y envía un código (3 por hora, 60 s entre uno y otro). Devuelve
   *  { devCode } si el servidor está en modo de pruebas. */
  async issueCode(email, purpose) {
    const now = this.now();
    await this.db.prepare('DELETE FROM code_log WHERE at < ?').bind(now - 60 * MIN).run();
    const log = await this.db
      .prepare('SELECT at FROM code_log WHERE email = ? ORDER BY at DESC')
      .bind(email)
      .all();
    const sent = log.results ?? [];
    if (sent.length >= R.MAX_CODES_PER_HOUR) {
      throw new ApiError(429, 'Ya pediste 3 códigos en la última hora. Espera un poco.');
    }
    if (sent.length && now - sent[0].at < R.RESEND_SECONDS * 1000) {
      throw new ApiError(429, 'Espera un minuto antes de pedir otro código.');
    }
    if (!this.devCodes && !mailConfigured(this.env)) {
      throw new ApiError(503, 'El envío de correos aún no está configurado en el servidor.');
    }
    const code = this.newCode();
    if (mailConfigured(this.env)) {
      try {
        await this.send(email, code, purpose);
      } catch (e) {
        console.error('mail', e);
        throw new ApiError(502, 'No se pudo enviar el correo. Inténtalo de nuevo en un rato.');
      }
    }
    await this.db.batch([
      this.db
        .prepare(
          'INSERT OR REPLACE INTO codes (email, purpose, code_hash, expires_at, attempts) VALUES (?, ?, ?, ?, 0)',
        )
        .bind(email, purpose, await sha256(`${email}|${purpose}|${code}`), now + R.CODE_MINUTES * MIN),
      this.db.prepare('INSERT INTO code_log (email, at) VALUES (?, ?)').bind(email, now),
    ]);
    return this.devCodes ? { devCode: code } : {};
  }

  /** Comprueba (5 intentos) y consume el código. */
  async checkCode(email, purpose, code) {
    const err = R.validateCode(code);
    if (err) throw bad(err);
    const row = await this.db
      .prepare('SELECT * FROM codes WHERE email = ? AND purpose = ?')
      .bind(email, purpose)
      .first();
    const del = () =>
      this.db.prepare('DELETE FROM codes WHERE email = ? AND purpose = ?').bind(email, purpose).run();
    if (!row) throw bad('Pide un código nuevo.');
    if (this.now() > row.expires_at) {
      await del();
      throw bad('El código venció (dura 15 minutos). Pide uno nuevo.');
    }
    if (row.attempts >= R.MAX_CODE_ATTEMPTS) {
      await del();
      throw bad('Demasiados intentos. Pide un código nuevo.');
    }
    const ok = safeEqual(row.code_hash, await sha256(`${email}|${purpose}|${String(code).trim()}`));
    if (!ok) {
      const attempts = row.attempts + 1;
      const left = R.MAX_CODE_ATTEMPTS - attempts;
      if (left <= 0) {
        await del();
      } else {
        await this.db
          .prepare('UPDATE codes SET attempts = ? WHERE email = ? AND purpose = ?')
          .bind(attempts, email, purpose)
          .run();
      }
      throw bad(
        left > 0
          ? `Código incorrecto. Te quedan ${left} intento(s).`
          : 'Código incorrecto. Pide un código nuevo.',
      );
    }
    await del();
  }

  // ───────────────────── Sesiones ─────────────────────

  async newSession(account) {
    const token = randomToken();
    const now = this.now();
    const expires = now + R.SESSION_DAYS * 24 * 60 * MIN;
    await this.db
      .prepare('INSERT INTO sessions (token_hash, account_id, expires_at, created_at) VALUES (?, ?, ?, ?)')
      .bind(await sha256(token), account.id, expires, now)
      .run();
    return { token, account: publicAccount(account), expiresAt: new Date(expires).toISOString() };
  }

  /** Cuenta de un token "Bearer". */
  async authenticate(token) {
    if (!token) throw new ApiError(401, 'Inicia sesión.');
    const s = await this.db
      .prepare('SELECT * FROM sessions WHERE token_hash = ?')
      .bind(await sha256(token))
      .first();
    if (!s || this.now() > s.expires_at) {
      throw new ApiError(401, 'La sesión venció. Vuelve a iniciar sesión.');
    }
    return this.byId(s.account_id);
  }

  async requireAdmin(token) {
    const a = await this.authenticate(token);
    if (a.role !== 'admin') throw new ApiError(403, 'Solo el administrador puede hacer esto.');
    return a;
  }

  // ───────────────────── Cuenta ─────────────────────

  async register({ username, email, password, nickname, phone }) {
    for (const e of [
      R.validateUsername(username),
      R.validateEmail(email),
      R.validatePassword(password),
      R.validateNickname(nickname),
      R.validatePhone(phone),
    ]) {
      if (e) throw bad(e);
    }
    const user = R.normalizeUsername(username);
    const mail = R.normalizeEmail(email);
    if (await this.db.prepare('SELECT 1 FROM accounts WHERE username = ?').bind(user).first()) {
      throw new ApiError(409, 'Ese usuario ya existe. Elige otro.');
    }
    const existing = await this.db.prepare('SELECT * FROM accounts WHERE email = ?').bind(mail).first();
    if (existing) {
      if (existing.verified) throw new ApiError(409, 'Ya hay una cuenta con ese Gmail. Inicia sesión.');
      throw new ApiError(403, 'Confirma tu Gmail con el código que te enviamos.', {
        code: 'unverified',
        email: mail,
      });
    }
    const admin = R.normalizeEmail(this.env.ADMIN_EMAIL ?? '');
    const role = admin && admin === mail ? 'admin' : 'player';
    const salt = randomToken(16);
    const now = this.iso();
    const phoneClean = R.cleanPhone(phone);
    // El código primero: si el correo falla, la cuenta no queda a medias.
    const dev = await this.issueCode(mail, 'verify');
    await this.db
      .prepare(
        `INSERT INTO accounts (id, username, email, nickname, phone, role, verified, salt, hash, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)`,
      )
      .bind(
        crypto.randomUUID(),
        user,
        mail,
        String(nickname).trim(),
        phoneClean || null,
        role,
        salt,
        await this.hash(String(password), salt),
        now,
        now,
      )
      .run();
    return { ok: true, email: mail, ...dev };
  }

  async resendVerification({ email }) {
    const a = await this.require(email);
    if (a.verified) throw bad('Esa cuenta ya está confirmada.');
    return { ok: true, ...(await this.issueCode(a.email, 'verify')) };
  }

  async verifyEmail({ email, code }) {
    const a = await this.require(email);
    if (a.verified) throw bad('Esa cuenta ya está confirmada. Inicia sesión.');
    await this.checkCode(a.email, 'verify', code);
    await this.db
      .prepare('UPDATE accounts SET verified = 1, updated_at = ? WHERE id = ?')
      .bind(this.iso(), a.id)
      .run();
    return { session: await this.newSession({ ...a, verified: 1 }) };
  }

  async login({ identifier, password }) {
    const id = String(identifier ?? '').trim().toLowerCase();
    const now = this.now();
    const since = now - R.LOGIN_FAIL_MINUTES * MIN;
    await this.db.prepare('DELETE FROM login_fail WHERE at < ?').bind(since).run();
    const fails = await this.db
      .prepare('SELECT COUNT(*) AS n FROM login_fail WHERE identifier = ?')
      .bind(id)
      .first();
    if ((fails?.n ?? 0) >= R.MAX_LOGIN_FAILS) {
      throw new ApiError(429, 'Demasiados intentos. Espera 15 minutos o cambia la contraseña.');
    }
    const a = await this.findBy(id);
    const ok = a && safeEqual(await this.hash(String(password ?? ''), a.salt), a.hash);
    if (!ok) {
      await this.db.prepare('INSERT INTO login_fail (identifier, at) VALUES (?, ?)').bind(id, now).run();
      throw new ApiError(401, 'Usuario, Gmail o contraseña incorrectos.');
    }
    if (!a.verified) {
      throw new ApiError(403, 'Confirma tu Gmail con el código que te enviamos.', {
        code: 'unverified',
        email: a.email,
      });
    }
    await this.db.prepare('DELETE FROM login_fail WHERE identifier = ?').bind(id).run();
    return { session: await this.newSession(a) };
  }

  async requestPasswordReset({ identifier }) {
    const a = await this.require(identifier);
    return { ok: true, email: a.email, ...(await this.issueCode(a.email, 'reset')) };
  }

  async resetPassword({ identifier, code, newPassword }) {
    const e = R.validatePassword(newPassword);
    if (e) throw bad(e);
    const a = await this.require(identifier);
    await this.checkCode(a.email, 'reset', code);
    const salt = randomToken(16);
    await this.db.batch([
      this.db
        .prepare('UPDATE accounts SET salt = ?, hash = ?, verified = 1, updated_at = ? WHERE id = ?')
        .bind(salt, await this.hash(String(newPassword), salt), this.iso(), a.id),
      // Por seguridad se cierran todas las sesiones.
      this.db.prepare('DELETE FROM sessions WHERE account_id = ?').bind(a.id),
    ]);
    return { ok: true };
  }

  async logout(token) {
    if (token) {
      await this.db.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await sha256(token)).run();
    }
    return { ok: true };
  }

  async me(token) {
    return { account: publicAccount(await this.authenticate(token)) };
  }

  // ───────────────────── Administrador ─────────────────────

  async listAccounts(token) {
    await this.requireAdmin(token);
    const r = await this.db.prepare('SELECT * FROM accounts ORDER BY username').all();
    return { accounts: (r.results ?? []).map(publicAccount) };
  }

  async setRole(token, id, { role }) {
    const me = await this.requireAdmin(token);
    if (!R.ROLES.includes(role)) throw bad('Rol no válido.');
    if (id === me.id && role !== 'admin') {
      throw bad('No puedes quitarte el rol de administrador a ti mismo.');
    }
    await this.byId(id);
    await this.db
      .prepare('UPDATE accounts SET role = ?, updated_at = ? WHERE id = ?')
      .bind(role, this.iso(), id)
      .run();
    return { account: publicAccount(await this.byId(id)) };
  }

  async linkPlayer(token, id, { playerId }) {
    await this.requireAdmin(token);
    await this.byId(id);
    const pid = playerId ? String(playerId) : null;
    if (pid) {
      const other = await this.db
        .prepare('SELECT username FROM accounts WHERE player_id = ? AND id <> ?')
        .bind(pid, id)
        .first();
      if (other) throw new ApiError(409, `Esa ficha ya está vinculada a @${other.username}.`);
    }
    await this.db
      .prepare('UPDATE accounts SET player_id = ?, updated_at = ? WHERE id = ?')
      .bind(pid, this.iso(), id)
      .run();
    return { account: publicAccount(await this.byId(id)) };
  }

  async verifyManually(token, id) {
    await this.requireAdmin(token);
    const a = await this.byId(id);
    await this.db.batch([
      this.db.prepare('UPDATE accounts SET verified = 1, updated_at = ? WHERE id = ?').bind(this.iso(), id),
      this.db.prepare("DELETE FROM codes WHERE email = ? AND purpose = 'verify'").bind(a.email),
    ]);
    return { account: publicAccount(await this.byId(id)) };
  }
}
