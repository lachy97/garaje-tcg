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
  const jue = await account('jue', 'jue@gmail.com');
  const ana = await account('ana', 'ana@gmail.com');
  await call('POST', `/v1/admin/accounts/${org.account.id}/role`, { role: 'organizer' }, admin.token);
  await call('POST', `/v1/admin/accounts/${jue.account.id}/role`, { role: 'judge' }, admin.token);
  await call('POST', `/v1/admin/accounts/${ana.account.id}/player`, { playerId: 'pa' }, admin.token);
  const r = (t, id, data) => ({ t, id, changedAt: 1, data: { id, ...data } });
  await call('POST', '/v1/sync/push', {
    rows: [
      r('tournaments', 't1', { status: 'draft', check_in: 1, checkin_code: 'GT42', notes: 'x' }),
      r('tournament_players', 'e1', { tournament_id: 't1', player_id: 'pa', paid: 1 }),
      r('tournament_players', 'e2', { tournament_id: 't1', player_id: 'pb', paid: 0 }),
      r('matches', 'm1', { tournament_id: 't1', player1_id: 'pa', player2_id: 'pb', result: 'pending', is_bye: 0 }),
      r('penalties', 'pen1', { tournament_id: 't1', player_id: 'pb', reason: 'x' }),
    ],
  }, org.token);
  return { call, org, jue, ana };
}

test('check-in con código', async () => {
  const { call, org, ana } = await setup();
  assert.equal((await call('POST', '/v1/play/checkin', { tournamentId: 't1', code: 'nope' }, ana.token)).status, 400);
  const r = await call('POST', '/v1/play/checkin', { tournamentId: 't1', code: ' gt42 ' }, ana.token);
  assert.equal(r.data.action.kind, 'checkin');
  const todo = await call('GET', '/v1/play/todo', null, org.token);
  assert.deepEqual(todo.data.actions.map((a) => a.kind), ['checkin']);
  // El código no llega a los jugadores.
  const pull = await call('GET', '/v1/sync/pull?since=0', null, ana.token);
  const t1 = pull.data.rows.find((x) => x.id === 't1');
  assert.ok(t1 && !('checkin_code' in t1.data));
});

test('jueces: asignar, ver el torneo y poner resultado, tiempo y penalización', async () => {
  const { call, org, jue, ana } = await setup();
  const cands = await call('GET', '/v1/staff/candidates', null, org.token);
  assert.ok(cands.data.accounts.some((a) => a.username === 'jue'));
  assert.equal((await call('POST', '/v1/play/extension', { tournamentId: 't1', matchId: 'm1', minutes: 5 }, jue.token)).status, 403);
  let r = await call('POST', '/v1/tournaments/t1/judges', { accountId: jue.account.id }, org.token);
  assert.deepEqual(r.data.judges.map((j) => j.username), ['jue']);
  assert.equal((await call('POST', '/v1/tournaments/t1/judges', { accountId: ana.account.id }, org.token)).status, 400);
  assert.deepEqual((await call('GET', '/v1/me/judging', null, jue.token)).data.tournaments, ['t1']);

  // El juez baja el torneo con penalizaciones de todos, sin cover ni notas.
  const pull = (await call('GET', '/v1/sync/pull?since=0', null, jue.token)).data.rows;
  assert.ok(pull.some((x) => x.id === 'pen1'));
  assert.ok(!('paid' in pull.find((x) => x.id === 'e1').data));
  assert.ok(!('notes' in pull.find((x) => x.id === 't1').data));

  await call('POST', '/v1/play/judge-result', { tournamentId: 't1', matchId: 'm1', g1: 2, gd: 0, g2: 1 }, jue.token);
  await call('POST', '/v1/play/judge-result', { tournamentId: 't1', matchId: 'm1', doubleLoss: true }, jue.token);
  await call('POST', '/v1/play/extension', { tournamentId: 't1', matchId: 'm1', minutes: 5 }, jue.token);
  r = await call('POST', '/v1/play/penalty', { tournamentId: 't1', playerId: 'pb', penalty: 'gameLoss', reason: 'Lento' }, jue.token);
  assert.equal(r.data.action.penalty, 'gameLoss');
  const todo = (await call('GET', '/v1/play/todo', null, org.token)).data.actions;
  const res = todo.filter((a) => a.kind === 'jresult');
  assert.equal(res.length, 1, 'vale el último resultado del juez');
  assert.equal(res[0].doubleLoss, true);
  assert.equal(todo.find((a) => a.kind === 'extension').extra, 5);

  r = await call('POST', `/v1/tournaments/t1/judges/${jue.account.id}/remove`, null, org.token);
  assert.equal(r.data.judges.length, 0);
});
