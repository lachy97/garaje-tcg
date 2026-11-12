import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/index.js';
import { makeD1 } from './d1_shim.mjs';

async function setup() {
  const state = { now: Date.UTC(2026, 10, 11, 12) };
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
  const ana = await account('ana', 'ana@gmail.com');
  const leo = await account('leo', 'leo@gmail.com');
  await call('POST', `/v1/admin/accounts/${org.account.id}/role`, { role: 'organizer' }, admin.token);
  // Ana tiene ficha vinculada; Leo no.
  await call('POST', `/v1/admin/accounts/${ana.account.id}/player`, { playerId: 'p-ana' }, admin.token);
  const tour = (data, changedAt = 100) => call('POST', '/v1/sync/push', {
    rows: [{ t: 'tournaments', id: 't1', changedAt, data: { id: 't1', name: 'Liga', status: 'draft', swiss_rounds: 4, top_cut_size: 8, ...data } }],
  }, org.token);
  return { call, state, admin, org, ana, leo, tour };
}

test('inscripción a mano: pedir, aceptar con ficha, inscribir y borrarse', async () => {
  const { call, org, ana, leo, tour } = await setup();
  await tour({ online_registration: 0, auto_accept: 0 });
  let r = await call('POST', '/v1/registrations', { tournamentId: 't1', deckName: 'Zombie' }, ana.token);
  assert.equal(r.status, 400, 'cerrada');

  await tour({ online_registration: 1, auto_accept: 0 }, 200);
  // El jugador ve el torneo abierto (aunque no esté inscrito).
  let mine = await call('GET', '/v1/registrations/mine', null, ana.token);
  assert.deepEqual(mine.data.open.map((t) => t.id), ['t1']);
  const pull = await call('GET', '/v1/sync/pull?since=0', null, ana.token);
  assert.ok(pull.data.rows.some((x) => x.t === 'tournaments' && x.id === 't1'));

  r = await call('POST', '/v1/registrations', { tournamentId: 't1', deckName: 'Zombie' }, ana.token);
  assert.equal(r.data.registration.status, 'pending');
  const anaReq = r.data.registration.id;
  r = await call('POST', '/v1/registrations', { tournamentId: 't1', deckName: 'Goat' }, leo.token);
  const leoReq = r.data.registration.id;
  assert.equal(r.data.registration.linked, false);

  // Otro jugador no puede ver ni aceptar.
  assert.equal((await call('GET', '/v1/registrations?tournament=t1', null, leo.token)).status, 403);
  r = await call('GET', '/v1/registrations?tournament=t1', null, org.token);
  assert.equal(r.data.registrations.length, 2);

  // Leo sin ficha: hay que elegirla; queda vinculada.
  assert.equal((await call('POST', `/v1/registrations/${leoReq}/accept`, {}, org.token)).status, 400);
  assert.equal((await call('POST', `/v1/registrations/${leoReq}/accept`, { playerId: 'p-ana' }, org.token)).status, 400,
    'ficha de otra cuenta');
  r = await call('POST', `/v1/registrations/${leoReq}/accept`, { playerId: 'p-leo' }, org.token);
  assert.equal(r.data.registration.status, 'accepted');
  assert.equal((await call('GET', '/v1/me', null, leo.token)).data.account.playerId, 'p-leo');

  r = await call('POST', `/v1/registrations/${anaReq}/reject`, { reason: 'Cupo lleno' }, org.token);
  assert.equal(r.data.registration.status, 'rejected');

  // El teléfono del organizador inscribe a Leo.
  let todo = await call('GET', '/v1/registrations/todo', null, org.token);
  assert.deepEqual(todo.data.registrations.map((x) => x.id), [leoReq]);
  r = await call('POST', `/v1/registrations/${leoReq}/done`, null, org.token);
  assert.equal(r.data.registration.status, 'registered');
  todo = await call('GET', '/v1/registrations/todo', null, org.token);
  assert.equal(todo.data.registrations.length, 0);

  // Leo se borra: el organizador lo quita.
  r = await call('POST', `/v1/registrations/${leoReq}/cancel`, null, leo.token);
  assert.equal(r.data.registration.status, 'cancel_requested');
  todo = await call('GET', '/v1/registrations/todo', null, org.token);
  assert.equal(todo.data.registrations[0].status, 'cancel_requested');
  r = await call('POST', `/v1/registrations/${leoReq}/done`, null, org.token);
  assert.equal(r.data.registration.status, 'cancelled');

  // Ana, rechazada, vuelve a pedir: pendiente otra vez.
  r = await call('POST', '/v1/registrations', { tournamentId: 't1', deckName: 'Chaos' }, ana.token);
  assert.equal(r.data.registration.status, 'pending');
  assert.equal(r.data.registration.deckName, 'Chaos');
  mine = await call('GET', '/v1/registrations/mine', null, ana.token);
  assert.equal(mine.data.registrations.length, 1);
});

test('aceptar solas: con ficha al momento; sin ficha queda para el organizador', async () => {
  const { call, org, ana, leo, tour } = await setup();
  await tour({ online_registration: 1, auto_accept: 1 });
  let r = await call('POST', '/v1/registrations', { tournamentId: 't1', deckName: 'Zombie' }, ana.token);
  assert.equal(r.data.registration.status, 'accepted');
  assert.equal(r.data.registration.playerId, 'p-ana');
  r = await call('POST', '/v1/registrations', { tournamentId: 't1', deckName: 'Goat' }, leo.token);
  assert.equal(r.data.registration.status, 'pending');
  const todo = await call('GET', '/v1/registrations/todo', null, org.token);
  assert.deepEqual(todo.data.registrations.map((x) => x.nickname), ['ana']);

  // Ya inscrita (fila subida por el organizador): no puede volver a pedir.
  await call('POST', '/v1/sync/push', {
    rows: [{ t: 'tournament_players', id: 'tp1', changedAt: 300, data: { id: 'tp1', tournament_id: 't1', player_id: 'p-ana' } }],
  }, org.token);
  r = await call('POST', '/v1/registrations', { tournamentId: 't1', deckName: 'Zombie' }, ana.token);
  assert.equal(r.status, 400);

  // Al empezar el torneo se cierra.
  await tour({ online_registration: 1, auto_accept: 1, status: 'swiss' }, 400);
  r = await call('POST', '/v1/registrations', { tournamentId: 't1', deckName: 'Goat' }, leo.token);
  assert.equal(r.status, 400);
  const mine = await call('GET', '/v1/registrations/mine', null, leo.token);
  assert.equal(mine.data.open.length, 0);
});

test('activar "aceptar solas" después acepta las pendientes con ficha', async () => {
  const { call, org, ana, tour } = await setup();
  await tour({ online_registration: 1, auto_accept: 0 });
  await call('POST', '/v1/registrations', { tournamentId: 't1', deckName: 'Zombie' }, ana.token);
  await tour({ online_registration: 1, auto_accept: 1 }, 200);
  const todo = await call('GET', '/v1/registrations/todo', null, org.token);
  assert.equal(todo.data.registrations[0].status, 'accepted');
});
