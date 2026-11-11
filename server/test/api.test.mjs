// node --test test/  (Node 22+, sin dependencias)
import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/index.js';
import { makeD1 } from './d1_shim.mjs';

function setup({ mail = false } = {}) {
  const state = { now: Date.UTC(2026, 10, 9, 12), codes: ['111111', '222222', '333333', '444444', '555555'], sent: [] };
  const env = {
    DB: makeD1(),
    ADMIN_EMAIL: 'Lachy@gmail.com',
    DEV_CODES: mail ? '0' : '1',
    ...(mail ? { BREVO_API_KEY: 'k', MAIL_FROM: 'club@gmail.com' } : {}),
  };
  const opts = {
    now: () => state.now,
    newCode: () => state.codes.shift(),
    send: async (to, code, purpose) => state.sent.push({ to, code, purpose }),
    iterations: 1000,
  };
  const call = async (method, path, body, token) => {
    const res = await handle(
      new Request(`https://api.test${path}`, {
        method,
        headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: body ? JSON.stringify(body) : undefined,
      }),
      env,
      opts,
    );
    return { status: res.status, data: await res.json() };
  };
  const tick = (sec) => (state.now += sec * 1000);
  return { call, state, tick, env };
}

const reg = (call, username, email) =>
  call('POST', '/v1/auth/register', { username, email, password: 'clave1234', nickname: username });

test('health', async () => {
  const { call } = setup();
  const r = await call('GET', '/v1/health');
  assert.equal(r.status, 200);
  assert.equal(r.data.ok, true);
  assert.equal(r.data.db, 'ok');
});

test('registro, verificación, login con usuario o Gmail; ADMIN_EMAIL es admin', async () => {
  const { call } = setup();
  const r = await reg(call, 'Lachy', 'lachy@gmail.com');
  assert.equal(r.status, 200);
  assert.equal(r.data.devCode, '111111');

  let l = await call('POST', '/v1/auth/login', { identifier: 'lachy', password: 'clave1234' });
  assert.equal(l.status, 403);
  assert.equal(l.data.code, 'unverified');

  const v = await call('POST', '/v1/auth/verify', { email: 'lachy@gmail.com', code: '111111' });
  assert.equal(v.status, 200);
  assert.equal(v.data.session.account.role, 'admin');
  assert.equal(v.data.session.account.verified, true);

  l = await call('POST', '/v1/auth/login', { identifier: 'LACHY@gmail.com', password: 'clave1234' });
  assert.equal(l.status, 200);
  const me = await call('GET', '/v1/me', null, l.data.session.token);
  assert.equal(me.data.account.username, 'lachy');

  const wrong = await call('POST', '/v1/auth/login', { identifier: 'lachy', password: 'otra12345' });
  assert.equal(wrong.status, 401);

  // Ya confirmada: no se puede "confirmar" otra vez para entrar.
  const again = await call('POST', '/v1/auth/verify', { email: 'lachy@gmail.com', code: '000000' });
  assert.equal(again.status, 400);
});

test('únicos, validaciones y jugador por defecto', async () => {
  const { call, tick } = setup();
  await reg(call, 'lachy', 'lachy@gmail.com');
  tick(61);
  assert.equal((await reg(call, 'LACHY', 'x@gmail.com')).status, 409);
  assert.equal((await reg(call, 'otro', 'otro@nauta.cu')).status, 400);
  const dup = await reg(call, 'otro', 'lachy@gmail.com');
  assert.equal(dup.status, 403); // ya registrado sin confirmar → a confirmar
  const leo = await reg(call, 'leo', 'leo@gmail.com');
  const v = await call('POST', '/v1/auth/verify', { email: 'leo@gmail.com', code: leo.data.devCode });
  assert.equal(v.data.session.account.role, 'player');
});

test('códigos: 5 intentos, 60 s, 3 por hora, 15 minutos', async () => {
  const { call, tick } = setup();
  await reg(call, 'leo', 'leo@gmail.com'); // 111111
  for (let i = 0; i < 5; i++) {
    const r = await call('POST', '/v1/auth/verify', { email: 'leo@gmail.com', code: '000000' });
    assert.equal(r.status, 400);
  }
  assert.equal((await call('POST', '/v1/auth/verify', { email: 'leo@gmail.com', code: '111111' })).status, 400);
  assert.equal((await call('POST', '/v1/auth/resend', { email: 'leo@gmail.com' })).status, 429);
  tick(61);
  const r2 = await call('POST', '/v1/auth/resend', { email: 'leo@gmail.com' });
  assert.equal(r2.data.devCode, '222222');
  tick(16 * 60);
  assert.equal((await call('POST', '/v1/auth/verify', { email: 'leo@gmail.com', code: '222222' })).status, 400);
  const r3 = await call('POST', '/v1/auth/resend', { email: 'leo@gmail.com' });
  assert.equal(r3.data.devCode, '333333');
  tick(61);
  assert.equal((await call('POST', '/v1/auth/resend', { email: 'leo@gmail.com' })).status, 429);
  assert.equal((await call('POST', '/v1/auth/verify', { email: 'leo@gmail.com', code: '333333' })).status, 200);
});

test('olvido de contraseña cierra las sesiones', async () => {
  const { call, tick } = setup();
  const r = await reg(call, 'lachy', 'lachy@gmail.com');
  const s = (await call('POST', '/v1/auth/verify', { email: 'lachy@gmail.com', code: r.data.devCode })).data.session;
  tick(61);
  const req = await call('POST', '/v1/auth/password/request', { identifier: 'lachy' });
  assert.equal(req.data.email, 'lachy@gmail.com');
  const ok = await call('POST', '/v1/auth/password/reset', { identifier: 'lachy', code: req.data.devCode, newPassword: 'nueva9876' });
  assert.equal(ok.status, 200);
  assert.equal((await call('GET', '/v1/me', null, s.token)).status, 401);
  assert.equal((await call('POST', '/v1/auth/login', { identifier: 'lachy', password: 'nueva9876' })).status, 200);
});

test('administrador: roles, ficha, verificar a mano; jugador sin permiso', async () => {
  const { call, tick } = setup();
  const r = await reg(call, 'lachy', 'lachy@gmail.com');
  const admin = (await call('POST', '/v1/auth/verify', { email: 'lachy@gmail.com', code: r.data.devCode })).data.session;
  await reg(call, 'leo', 'leo@gmail.com');
  const list = await call('GET', '/v1/admin/accounts', null, admin.token);
  const leo = list.data.accounts.find((a) => a.username === 'leo');
  assert.equal(leo.verified, false);

  assert.equal((await call('POST', `/v1/admin/accounts/${leo.id}/verify`, {}, admin.token)).data.account.verified, true);
  assert.equal((await call('POST', `/v1/admin/accounts/${leo.id}/role`, { role: 'organizer' }, admin.token)).data.account.role, 'organizer');
  assert.equal((await call('POST', `/v1/admin/accounts/${leo.id}/player`, { playerId: 'p1' }, admin.token)).data.account.playerId, 'p1');
  assert.equal((await call('POST', `/v1/admin/accounts/${admin.account.id}/player`, { playerId: 'p1' }, admin.token)).status, 409);
  assert.equal((await call('POST', `/v1/admin/accounts/${admin.account.id}/role`, { role: 'player' }, admin.token)).status, 400);
  assert.equal((await call('POST', `/v1/admin/accounts/${leo.id}/player`, { playerId: null }, admin.token)).data.account.playerId, null);

  tick(1);
  const leoS = (await call('POST', '/v1/auth/login', { identifier: 'leo', password: 'clave1234' })).data.session;
  assert.equal((await call('GET', '/v1/admin/accounts', null, leoS.token)).status, 403);
  assert.equal((await call('GET', '/v1/admin/accounts')).status, 401);
});

test('sesión de 30 días y límite de inicios fallidos', async () => {
  const { call, tick } = setup();
  const r = await reg(call, 'lachy', 'lachy@gmail.com');
  const s = (await call('POST', '/v1/auth/verify', { email: 'lachy@gmail.com', code: r.data.devCode })).data.session;
  for (let i = 0; i < 10; i++) {
    await call('POST', '/v1/auth/login', { identifier: 'lachy', password: 'mala12345' });
  }
  assert.equal((await call('POST', '/v1/auth/login', { identifier: 'lachy', password: 'clave1234' })).status, 429);
  tick(16 * 60);
  assert.equal((await call('POST', '/v1/auth/login', { identifier: 'lachy', password: 'clave1234' })).status, 200);
  tick(31 * 24 * 3600);
  assert.equal((await call('GET', '/v1/me', null, s.token)).status, 401);
});

test('con correo configurado: se envía y no se devuelve el código', async () => {
  const { call, state } = setup({ mail: true });
  const r = await reg(call, 'leo', 'leo@gmail.com');
  assert.equal(r.status, 200);
  assert.equal(r.data.devCode, undefined);
  assert.deepEqual(state.sent, [{ to: 'leo@gmail.com', code: '111111', purpose: 'verify' }]);
});

test('sin correo ni modo pruebas: la cuenta se crea pero avisa; reenviar da 503', async () => {
  const { call, env, tick } = setup();
  env.DEV_CODES = '0';
  const r = await reg(call, 'leo', 'leo@gmail.com');
  assert.equal(r.status, 200);
  assert.equal(r.data.mailFailed, true);
  tick(61);
  assert.equal((await call('POST', '/v1/auth/resend', { email: 'leo@gmail.com' })).status, 503);
});

test('la raíz también responde como /v1/health', async () => {
  const { call } = setup();
  const r = await call('GET', '/');
  assert.equal(r.status, 200);
  assert.equal(r.data.ok, true);
});

test('si el correo falla la cuenta se crea igual; el admin la confirma y da código de contraseña', async () => {
  const { call, env, tick } = setup();
  const r = await reg(call, 'lachy', 'lachy@gmail.com');
  const admin = (await call('POST', '/v1/auth/verify', { email: 'lachy@gmail.com', code: r.data.devCode })).data.session;
  env.DEV_CODES = '0'; // sin modo pruebas ni correo configurado → el envío falla
  const leo = await reg(call, 'leo', 'leo@gmail.com');
  assert.equal(leo.status, 200);
  assert.equal(leo.data.mailFailed, true);
  assert.equal(leo.data.devCode, undefined);
  const list = await call('GET', '/v1/admin/accounts', null, admin.token);
  const acc = list.data.accounts.find((a) => a.username === 'leo');
  await call('POST', `/v1/admin/accounts/${acc.id}/verify`, {}, admin.token);
  assert.equal((await call('POST', '/v1/auth/login', { identifier: 'leo', password: 'clave1234' })).status, 200);

  tick(1);
  const rc = await call('POST', `/v1/admin/accounts/${acc.id}/reset-code`, {}, admin.token);
  assert.match(rc.data.code, /^\d{6}$/);
  const ok = await call('POST', '/v1/auth/password/reset', { identifier: 'leo', code: rc.data.code, newPassword: 'nueva9876' });
  assert.equal(ok.status, 200);
  assert.equal((await call('POST', '/v1/auth/login', { identifier: 'leo', password: 'nueva9876' })).status, 200);
});

test('prueba de correo del administrador devuelve el error exacto', async () => {
  const { call } = setup();
  const r = await reg(call, 'lachy', 'lachy@gmail.com');
  const admin = (await call('POST', '/v1/auth/verify', { email: 'lachy@gmail.com', code: r.data.devCode })).data.session;
  const t = await call('POST', '/v1/admin/mail-test', {}, admin.token);
  assert.equal(t.status, 200);
  assert.equal(t.data.ok, false);
  assert.match(t.data.error, /GMAIL_USER/);
});
