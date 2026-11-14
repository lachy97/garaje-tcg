// Garage TCG · API (Cloudflare Workers + D1).
// Rutas en /v1. Cuerpos y respuestas en JSON. Errores: { error, code? }.
import { ApiError, AuthService } from './auth.js';
import { PlayService } from './play.js';
import { RegistrationService } from './registrations.js';
import { SyncService } from './sync.js';

export const VERSION = '1.8.0';

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });

async function readBody(request) {
  if (request.method !== 'POST') return {};
  try {
    const text = await request.text();
    return text ? JSON.parse(text) : {};
  } catch {
    throw new ApiError(400, 'Petición mal formada.');
  }
}

const bearer = (request) => {
  const h = request.headers.get('authorization') ?? '';
  return h.startsWith('Bearer ') ? h.slice(7).trim() : null;
};

/** Atiende una petición. [opts] solo para tests (reloj, códigos, correo). */
export async function handle(request, env, opts) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, '') || '/';
  const m = request.method;
  const auth = new AuthService(env, opts);
  const sync = new SyncService(env, auth);
  const regs = new RegistrationService(env, auth);
  const play = new PlayService(env, auth);
  try {
    // Fase 0: prueba de conexión desde Cuba.
    if ((path === '/v1/health' || path === '/') && m === 'GET') {
      const db = await env.DB.prepare('SELECT COUNT(*) AS n FROM accounts').first();
      return json({ ok: true, service: 'garage-tcg', version: VERSION, time: new Date().toISOString(), db: db ? 'ok' : 'error' });
    }

    // Versión mínima de la app (secreto o variable MIN_APP_BUILD = número de
    // compilación de GitHub Actions). Las versiones viejas reciben un aviso
    // para actualizar en vez de fallar a medias.
    const minBuild = Number(env.MIN_APP_BUILD ?? 0);
    if (minBuild > 0) {
      const build = Number(request.headers.get('x-app-build') ?? 0) || 0;
      if (build < minBuild) {
        return json({
          error: 'Hay una versión nueva de Garage TCG: instálala para seguir usando la app en línea.',
          code: 'update_required',
        }, 426);
      }
    }

    const body = await readBody(request);
    const token = bearer(request);

    if (m === 'POST') {
      switch (path) {
        case '/v1/auth/register': return json(await auth.register(body));
        case '/v1/auth/resend': return json(await auth.resendVerification(body));
        case '/v1/auth/verify': return json(await auth.verifyEmail(body));
        case '/v1/auth/login': return json(await auth.login(body));
        case '/v1/auth/password/request': return json(await auth.requestPasswordReset(body));
        case '/v1/auth/password/reset': return json(await auth.resetPassword(body));
        case '/v1/auth/logout': return json(await auth.logout(token));
        case '/v1/sync/push': return json(await sync.push(token, body));
        case '/v1/admin/mail-test': return json(await auth.mailTest(token));
        case '/v1/registrations': return json(await regs.request(token, body));
        case '/v1/play/report': return json(await play.report(token, body));
        case '/v1/play/judge': return json(await play.judge(token, body));
        case '/v1/play/drop': return json(await play.drop(token, body));
        case '/v1/play/checkin': return json(await play.checkin(token, body));
        case '/v1/play/judge-result': return json(await play.judgeResult(token, body));
        case '/v1/play/extension': return json(await play.extension(token, body));
        case '/v1/play/penalty': return json(await play.penalty(token, body));
      }
      const st = path.match(/^\/v1\/tournaments\/([^/]+)\/judges(?:\/([^/]+)\/remove)?$/);
      if (st) {
        const [, tid, acc] = st;
        return json(acc ? await play.removeJudge(token, tid, acc) : await play.addJudge(token, tid, body));
      }
      const pa = path.match(/^\/v1\/play\/([^/]+)\/(confirm|dispute|cancel|done)$/);
      if (pa) {
        const [, id, what] = pa;
        if (what === 'confirm') return json(await play.answer(token, id, true));
        if (what === 'dispute') return json(await play.answer(token, id, false));
        if (what === 'cancel') return json(await play.cancel(token, id));
        return json(await play.done(token, id));
      }
      const reg = path.match(/^\/v1\/registrations\/([^/]+)\/(accept|reject|done|cancel)$/);
      if (reg) {
        const [, id, what] = reg;
        if (what === 'accept') return json(await regs.accept(token, id, body));
        if (what === 'reject') return json(await regs.reject(token, id, body));
        if (what === 'done') return json(await regs.done(token, id));
        return json(await regs.cancel(token, id));
      }
      const admin = path.match(/^\/v1\/admin\/accounts\/([^/]+)\/(role|player|verify|reset-code)$/);
      if (admin) {
        const [, id, what] = admin;
        if (what === 'role') return json(await auth.setRole(token, id, body));
        if (what === 'player') return json(await auth.linkPlayer(token, id, body));
        if (what === 'reset-code') return json(await auth.adminResetCode(token, id));
        return json(await auth.verifyManually(token, id));
      }
    }
    if (m === 'GET') {
      if (path === '/v1/me') return json(await auth.me(token));
      if (path === '/v1/admin/accounts') return json(await auth.listAccounts(token));
      if (path === '/v1/sync/pull') return json(await sync.pull(token, url.searchParams));
      if (path === '/v1/sync/status') return json(await sync.status(token));
      if (path === '/v1/registrations/mine') return json(await regs.mine(token));
      if (path === '/v1/play/mine') return json(await play.mine(token, url.searchParams.get('tournament')));
      if (path === '/v1/play/todo') return json(await play.todo(token));
      if (path === '/v1/staff/candidates') return json(await play.candidates(token));
      if (path === '/v1/me/judging') return json(await play.judging(token));
      const gj = path.match(/^\/v1\/tournaments\/([^/]+)\/judges$/);
      if (gj) return json(await play.judges(token, gj[1]));
      if (path === '/v1/play') return json(await play.forTournament(token, url.searchParams.get('tournament')));
      if (path === '/v1/registrations/todo') return json(await regs.todo(token));
      if (path === '/v1/registrations') {
        return json(await regs.forTournament(token, url.searchParams.get('tournament')));
      }
    }
    return json({ error: 'Ruta no encontrada.' }, 404);
  } catch (e) {
    if (e instanceof ApiError) return json({ error: e.message, ...e.extra }, e.status);
    console.error(e);
    return json({ error: 'Error del servidor. Inténtalo de nuevo.' }, 500);
  }
}

export default {
  fetch: (request, env) => handle(request, env),
};
