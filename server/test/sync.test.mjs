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

test('jugador: baja solo lo que puede ver', async () => {
  const { call, admin, player } = await setup();
  // Vincular la cuenta del jugador con su ficha p1.
  await call('POST', `/v1/admin/accounts/${player.account.id}/player`, { playerId: 'p1' }, admin.token);
  const T = (id, status) => ({ t: 'tournaments', id, changedAt: 1, data: { id, status } });
  await call('POST', '/v1/sync/push', {
    rows: [
      { t: 'players', id: 'p1', changedAt: 1, data: { id: 'p1', nickname: 'Yo', phone: '555', full_name: 'Mi Nombre' } },
      { t: 'players', id: 'p2', changedAt: 1, data: { id: 'p2', nickname: 'Otro', phone: '666', full_name: 'Otro Nombre' } },
      { t: 'decks', id: 'd1', changedAt: 1, data: { id: 'd1', name: 'Goat' } },
      T('fin', 'finished'),
      T('vivo', 'swiss'),
      T('ajeno', 'swiss'),
      { t: 'tournament_players', id: 'tp1', changedAt: 1, data: { id: 'tp1', tournament_id: 'vivo', player_id: 'p1' } },
      { t: 'matches', id: 'm-fin', changedAt: 1, data: { id: 'm-fin', tournament_id: 'fin' } },
      { t: 'matches', id: 'm-vivo', changedAt: 1, data: { id: 'm-vivo', tournament_id: 'vivo' } },
      { t: 'matches', id: 'm-ajeno', changedAt: 1, data: { id: 'm-ajeno', tournament_id: 'ajeno' } },
      { t: 'penalties', id: 'pen-mia', changedAt: 1, data: { id: 'pen-mia', tournament_id: 'fin', player_id: 'p1' } },
      { t: 'penalties', id: 'pen-otro', changedAt: 1, data: { id: 'pen-otro', tournament_id: 'fin', player_id: 'p2' } },
    ],
  }, admin.token);

  // El jugador recarga su cuenta (ahora con ficha) y baja.
  let r = await call('GET', '/v1/sync/pull?since=0', null, player.token);
  assert.equal(r.status, 200);
  const ids = r.data.rows.map((x) => x.id).sort();
  assert.deepEqual(ids, ['d1', 'fin', 'm-fin', 'm-vivo', 'p1', 'p2', 'pen-mia', 'tp1', 'vivo'].sort());
  const p2 = r.data.rows.find((x) => x.id === 'p2');
  assert.equal(p2.data.nickname, 'Otro');
  assert.equal(p2.data.phone, null);
  assert.equal(p2.data.full_name, null);
  assert.equal(r.data.rows.find((x) => x.id === 'p1').data.phone, '555');

  // Sin cambios: nada.
  const since = r.data.seq;
  r = await call('GET', `/v1/sync/pull?since=${since}`, null, player.token);
  assert.equal(r.data.rows.length, 0);

  // El torneo ajeno termina: llega entero (aunque sus filas sean anteriores).
  await call('POST', '/v1/sync/push', { rows: [T('ajeno', 'finished')].map((x) => ({ ...x, changedAt: 5 })) }, admin.token);
  r = await call('GET', `/v1/sync/pull?since=${since}`, null, player.token);
  assert.deepEqual(r.data.rows.map((x) => x.id).sort(), ['ajeno', 'm-ajeno']);

  // El administrador baja todo sin filtrar.
  const all = await call('GET', '/v1/sync/pull?since=0', null, admin.token);
  assert.equal(all.data.rows.length, 12);
  assert.equal(all.data.rows.find((x) => x.id === 'p2').data.phone, '666');
});

test('privacidad: cover y notas solo para quien lleva el torneo; el organizador ve teléfonos', async () => {
  const { call, admin, org, player } = await setup();
  // El jugador tiene ficha p1; el torneo t1 (terminado) es del organizador.
  await call('POST', `/v1/admin/accounts/${player.account.id}/player`, { playerId: 'p1' }, admin.token);
  await call('POST', '/v1/sync/push', {
    rows: [
      row('players', 'p1', 1, { id: 'p1', nickname: 'Jug', phone: '5551' }),
      row('players', 'p2', 1, { id: 'p2', nickname: 'Otro', phone: '5552' }),
      row('tournaments', 't1', 1, { id: 't1', name: 'T1', status: 'finished', notes: 'secreto' }),
      row('tournament_players', 'e1', 1, { id: 'e1', tournament_id: 't1', player_id: 'p1', paid: 1 }),
      row('penalties', 'pen2', 1, { id: 'pen2', tournament_id: 't1', player_id: 'p2', reason: 'x' }),
    ],
  }, org.token);
  // Torneo de otro (admin), en juego, donde no está nadie.
  await call('POST', '/v1/sync/push', {
    rows: [row('tournaments', 't9', 2, { id: 't9', name: 'T9', status: 'swiss', notes: 'privado' })],
  }, admin.token);

  const pj = (await call('GET', '/v1/sync/pull?since=0', null, player.token)).data.rows;
  const t1 = pj.find((x) => x.id === 't1');
  assert.ok(!('notes' in t1.data), 'sin notas del organizador');
  assert.ok(!('paid' in pj.find((x) => x.id === 'e1').data), 'sin cover');
  assert.equal(pj.find((x) => x.id === 'p2').data.phone, null);
  assert.equal(pj.find((x) => x.id === 'p1').data.phone, '5551', 'lo suyo sí');
  assert.ok(!pj.some((x) => x.id === 'pen2'), 'penalizaciones ajenas no');

  const og = (await call('GET', '/v1/sync/pull?since=0', null, org.token)).data.rows;
  assert.equal(og.find((x) => x.id === 't1').data.notes, 'secreto', 'su torneo completo');
  assert.equal(og.find((x) => x.id === 'e1').data.paid, 1);
  assert.ok(og.some((x) => x.id === 'pen2'));
  assert.equal(og.find((x) => x.id === 'p2').data.phone, '5552', 'el organizador ve teléfonos');
  assert.ok(!og.some((x) => x.id === 't9'), 'torneos en juego de otros no');

  const ad = (await call('GET', '/v1/sync/pull?since=0', null, admin.token)).data.rows;
  assert.equal(ad.find((x) => x.id === 't9').data.notes, 'privado');
});

test('listas de mazo: solo arquetipo o al terminar', async () => {
  const { call, admin, org, player } = await setup();
  await call('POST', `/v1/admin/accounts/${player.account.id}/player`, { playerId: 'p1' }, admin.token);
  const push = (rows) => call('POST', '/v1/sync/push', { rows }, org.token);
  await push([
    row('tournaments', 'ta', 1, { id: 'ta', status: 'finished', list_visibility: 'archetype' }),
    row('tournaments', 'tb', 1, { id: 'tb', status: 'topCut', list_visibility: 'after' }),
    row('tournament_players', 'ea', 1, { id: 'ea', tournament_id: 'ta', player_id: 'p1' }),
    row('tournament_players', 'eb', 1, { id: 'eb', tournament_id: 'tb', player_id: 'p1' }),
    row('deck_lists', 'la', 1, { id: 'la', tournament_id: 'ta', player_id: 'p2' }),
    row('deck_lists', 'lb', 1, { id: 'lb', tournament_id: 'tb', player_id: 'p2' }),
  ]);
  let rows = (await call('GET', '/v1/sync/pull?since=0', null, player.token)).data;
  assert.ok(!rows.rows.some((x) => x.t === 'deck_lists'), 'ninguna lista todavía');
  // Termina el torneo "al terminar": llegan sus listas.
  await push([row('tournaments', 'tb', 2, { id: 'tb', status: 'finished', list_visibility: 'after' })]);
  rows = (await call('GET', `/v1/sync/pull?since=${rows.seq}`, null, player.token)).data;
  assert.ok(rows.rows.some((x) => x.id === 'lb'));
  assert.ok(!rows.rows.some((x) => x.id === 'la'));
});
