import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/index.js';
import { AuthService } from '../src/auth.js';
import { makeD1 } from './d1_shim.mjs';

function setup() {
  const state = { now: Date.UTC(2026, 10, 15, 12) };
  const env = { DB: makeD1(), ADMIN_EMAIL: 'lachy@gmail.com', DEV_CODES: '1' };
  const opts = { now: () => state.now, iterations: 1000 };
  const call = async (method, path, body, { token, ip } = {}) => {
    const res = await handle(
      new Request(`https://api.test${path}`, {
        method,
        headers: {
          'content-type': 'application/json',
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...(ip ? { 'cf-connecting-ip': ip } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
      }),
      env,
      opts,
    );
    return { status: res.status, data: await res.json() };
  };
  const account = async (u, e, ip = '9.9.9.9') => {
    const r = await call('POST', '/v1/auth/register', { username: u, email: e, password: 'clave1234', nickname: u }, { ip });
    return (await call('POST', '/v1/auth/verify', { email: e, code: r.data.devCode }, { ip })).data.session;
  };
  return { state, call, account };
}

test('quien prueba contraseñas se bloquea a sí mismo, no al dueño de la cuenta', async () => {
  const { call, account } = setup();
  await account('org', 'org@gmail.com');
  for (let i = 0; i < 10; i++) {
    const r = await call('POST', '/v1/auth/login', { identifier: 'org', password: 'mala1234' }, { ip: '6.6.6.6' });
    assert.equal(r.status, 401);
  }
  const atacante = await call('POST', '/v1/auth/login', { identifier: 'org', password: 'clave1234' }, { ip: '6.6.6.6' });
  assert.equal(atacante.status, 429);
  // El organizador, desde su conexión, entra sin problema.
  const dueño = await call('POST', '/v1/auth/login', { identifier: 'org', password: 'clave1234' }, { ip: '1.1.1.1' });
  assert.equal(dueño.status, 200);
});

test('una conexión no puede probar contraseñas de muchos usuarios', async () => {
  const { call, account } = setup();
  await account('ana', 'ana@gmail.com');
  for (let i = 0; i < 30; i++) {
    await call('POST', '/v1/auth/login', { identifier: `u${i}`, password: 'mala1234' }, { ip: '6.6.6.6' });
  }
  const r = await call('POST', '/v1/auth/login', { identifier: 'ana', password: 'clave1234' }, { ip: '6.6.6.6' });
  assert.equal(r.status, 429);
});

test('registro masivo desde una conexión: se corta a las 5 por hora', async () => {
  const { call } = setup();
  for (let i = 0; i < 5; i++) {
    const r = await call('POST', '/v1/auth/register', { username: `jug${i}`, email: `jug${i}@gmail.com`, password: 'clave1234', nickname: 'J' }, { ip: '7.7.7.7' });
    assert.equal(r.status, 200);
  }
  const r = await call('POST', '/v1/auth/register', { username: 'jug9', email: 'jug9@gmail.com', password: 'clave1234', nickname: 'J' }, { ip: '7.7.7.7' });
  assert.equal(r.status, 429);
});

test('cerrar sesión en todos los teléfonos', async () => {
  const { call, account } = setup();
  const s1 = await account('leo', 'leo@gmail.com');
  const s2 = (await call('POST', '/v1/auth/login', { identifier: 'leo', password: 'clave1234' }, { ip: '2.2.2.2' })).data.session;
  assert.equal((await call('POST', '/v1/auth/logout-all', {}, { token: s2.token })).status, 200);
  assert.equal((await call('GET', '/v1/me', null, { token: s1.token })).status, 401);
  assert.equal((await call('GET', '/v1/me', null, { token: s2.token })).status, 401);
});

test('al pedir un código con el usuario no se muestra el Gmail completo', () => {
  assert.equal(AuthService.maskEmail('lachyyuri@gmail.com'), 'l***i@gmail.com');
  assert.equal(AuthService.maskEmail('ab@gmail.com'), 'a@gmail.com');
});
