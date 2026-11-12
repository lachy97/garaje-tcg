import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/index.js';
import { makeD1 } from './d1_shim.mjs';

async function setup() {
  const env = { DB: makeD1(), ADMIN_EMAIL: 'lachy@gmail.com', DEV_CODES: '1' };
  const opts = { now: () => Date.UTC(2026, 10, 12, 12), iterations: 1000 };
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
    return (await call('POST', '/v1/auth/verify', { email, code: r.data.devCode })).data.session;
  };
  const admin = await account('lachy', 'lachy@gmail.com');
  const org = await account('org', 'org@gmail.com');
  const ana = await account('ana', 'ana@gmail.com');
  const leo = await account('leo', 'leo@gmail.com');
  const eva = await account('eva', 'eva@gmail.com');
  await call('POST', `/v1/admin/accounts/${org.account.id}/role`, { role: 'organizer' }, admin.token);
  for (const [s, p] of [[ana, 'pa'], [leo, 'pl'], [eva, 'pe']]) {
    await call('POST', `/v1/admin/accounts/${s.account.id}/player`, { playerId: p }, admin.token);
  }
  const r = (t, id, data) => ({ t, id, changedAt: 1, data: { id, ...data } });
  await call('POST', '/v1/sync/push', {
    rows: [
      r('tournaments', 't1', { status: 'swiss' }),
      r('tournament_players', 'e1', { tournament_id: 't1', player_id: 'pa', dropped: 0 }),
      r('tournament_players', 'e2', { tournament_id: 't1', player_id: 'pl', dropped: 0 }),
      r('tournament_players', 'e3', { tournament_id: 't1', player_id: 'pe', dropped: 0 }),
      r('matches', 'm1', { tournament_id: 't1', player1_id: 'pa', player2_id: 'pl', result: 'pending', is_bye: 0 }),
    ],
  }, org.token);
  return { call, org, ana, leo, eva };
}

test('reportar: el rival confirma y el organizador lo aplica', async () => {
  const { call, org, ana, leo, eva } = await setup();
  const score = { tournamentId: 't1', matchId: 'm1', g1: 2, gd: 0, g2: 1 };
  assert.equal((await call('POST', '/v1/play/report', score, eva.token)).status, 403, 'no es su mesa');
  assert.equal((await call('POST', '/v1/play/report', { ...score, g1: 3 }, ana.token)).status, 400);
  let r = await call('POST', '/v1/play/report', score, ana.token);
  assert.equal(r.data.action.status, 'proposed');
  const id = r.data.action.id;
  // Leo lo ve en su mesa y lo confirma (Ana no puede confirmarse sola).
  const mine = await call('GET', '/v1/play/mine?tournament=t1', null, leo.token);
  assert.equal(mine.data.actions[0].id, id);
  assert.equal((await call('POST', `/v1/play/${id}/confirm`, null, ana.token)).status, 403);
  r = await call('POST', `/v1/play/${id}/confirm`, null, leo.token);
  assert.equal(r.data.action.status, 'confirmed');
  const todo = await call('GET', '/v1/play/todo', null, org.token);
  assert.deepEqual(todo.data.actions.map((a) => a.id), [id]);
  await call('POST', `/v1/play/${id}/done`, null, org.token);
  assert.equal((await call('GET', '/v1/play/todo', null, org.token)).data.actions.length, 0);
});

test('reportes que no coinciden quedan en disputa; juez y drop', async () => {
  const { call, org, ana, leo } = await setup();
  await call('POST', '/v1/play/report', { tournamentId: 't1', matchId: 'm1', g1: 2, gd: 0, g2: 0 }, ana.token);
  let r = await call('POST', '/v1/play/report', { tournamentId: 't1', matchId: 'm1', g1: 0, gd: 0, g2: 2 }, leo.token);
  assert.equal(r.data.action.status, 'disputed');
  assert.deepEqual(r.data.action.otherScore, { g1: 0, gd: 0, g2: 2 });
  // Ana corrige y ahora coincide: confirmado.
  r = await call('POST', '/v1/play/report', { tournamentId: 't1', matchId: 'm1', g1: 0, gd: 0, g2: 2 }, ana.token);
  assert.equal(r.data.action.status, 'confirmed');

  r = await call('POST', '/v1/play/judge', { tournamentId: 't1', matchId: 'm1', note: 'regla' }, leo.token);
  assert.equal(r.data.action.kind, 'judge');
  r = await call('POST', '/v1/play/drop', { tournamentId: 't1' }, ana.token);
  const list = await call('GET', '/v1/play?tournament=t1', null, org.token);
  assert.deepEqual(list.data.actions.map((a) => a.kind).sort(), ['drop', 'judge', 'report']);
  assert.equal((await call('GET', '/v1/play?tournament=t1', null, leo.token)).status, 403);
  const todo = await call('GET', '/v1/play/todo', null, org.token);
  assert.deepEqual(todo.data.actions.map((a) => a.kind).sort(), ['drop', 'report']);
});
