import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/index.js';
import { makeD1 } from './d1_shim.mjs';

async function setup() {
  const state = { now: Date.UTC(2026, 10, 10, 12) };
  const env = { DB: makeD1(), ADMIN_EMAIL: 'lachy@gmail.com', DEV_CODES: '1' };
  const opts = { now: () => state.now, iterations: 1000 };
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
  const account = async (username, email) => {
    const r = await call('POST', '/v1/auth/register', { username, email, password: 'clave1234', nickname: username });
    const v = await call('POST', '/v1/auth/verify', { email, code: r.data.devCode });
    return v.data.session;
  };
  const admin = await account('lachy', 'lachy@gmail.com');
  const org = await account('org', 'org@gmail.com');
  const player = await account('jug', 'jug@gmail.com');
  await call('POST', `/v1/admin/accounts/${org.account.id}/role`, { role: 'organizer' }, admin.token);
  return { call, state, admin, org, player };
}

const row = (t, id, changedAt, data = { id, name: id }) => ({ t, id, changedAt, data });

test('subir, ganar el más reciente y bajar por seq', async () => {
  const { call, admin } = await setup();
  let r = await call('POST', '/v1/sync/push', {
    rows: [row('players', 'p1', 100, { id: 'p1', nickname: 'Leo' }), row('tournaments', 't1', 100)],
  }, admin.token);
  assert.equal(r.status, 200);
  assert.equal(r.data.accepted, 2);
  assert.equal(r.data.seq, 2);

  // Cambio más antiguo: se ignora.
  r = await call('POST', '/v1/sync/push', { rows: [row('players', 'p1', 50, { id: 'p1', nickname: 'Viejo' })] }, admin.token);
  assert.equal(r.data.accepted, 0);
  assert.equal(r.data.stale, 1);

  // Más reciente y borrado.
  r = await call('POST', '/v1/sync/push', {
    rows: [row('players', 'p1', 200, { id: 'p1', nickname: 'Leo B' }), { t: 'tournaments', id: 't1', changedAt: 300, deleted: true }],
  }, admin.token);
  assert.equal(r.data.accepted, 2);

  const all = await call('GET', '/v1/sync/pull?since=0', null, admin.token);
  assert.equal(all.data.rows.length, 2);
  const p1 = all.data.rows.find((x) => x.id === 'p1');
  assert.equal(p1.data.nickname, 'Leo B');
  const t1 = all.data.rows.find((x) => x.id === 't1');
  assert.equal(t1.deleted, true);
  assert.equal(t1.data, null);
  const after = await call('GET', `/v1/sync/pull?since=${p1.seq}`, null, admin.token);
  assert.deepEqual(after.data.rows.map((x) => x.id), t1.seq > p1.seq ? ['t1'] : []);

  const st = await call('GET', '/v1/sync/status', null, admin.token);
  assert.equal(st.data.tables.players.rows, 1);
  assert.equal(st.data.tables.tournaments.deleted, 1);
});

test('permisos: jugador no sube; organizador no pisa filas ajenas; admin sí', async () => {
  const { call, admin, org, player } = await setup();
  assert.equal((await call('POST', '/v1/sync/push', { rows: [] }, player.token)).status, 403);
  assert.equal((await call('POST', '/v1/sync/push', { rows: [] })).status, 401);

  await call('POST', '/v1/sync/push', { rows: [row('decks', 'd1', 10)] }, admin.token);
  const r = await call('POST', '/v1/sync/push', { rows: [row('decks', 'd1', 20), row('decks', 'd2', 20)] }, org.token);
  assert.equal(r.data.accepted, 1);
  assert.deepEqual(r.data.rejected, [{ t: 'decks', id: 'd1', reason: 'not_owner' }]);
  const r2 = await call('POST', '/v1/sync/push', { rows: [row('decks', 'd2', 30)] }, admin.token);
  assert.equal(r2.data.accepted, 1);
});

test('validación', async () => {
  const { call, admin } = await setup();
  const r = await call('POST', '/v1/sync/push', {
    rows: [{ t: 'accounts', id: 'x', changedAt: 1, data: {} }, { t: 'players', id: 'y', changedAt: 1 }, row('players', 'ok', 1)],
  }, admin.token);
  assert.equal(r.data.accepted, 1);
  assert.equal(r.data.rejected.length, 2);
  const big = await call('POST', '/v1/sync/push', { rows: Array.from({ length: 501 }, (_, i) => row('players', `p${i}`, 1)) }, admin.token);
  assert.equal(big.status, 400);
});
