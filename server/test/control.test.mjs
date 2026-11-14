import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/index.js';
import { makeD1 } from './d1_shim.mjs';

async function setup() {
  const state = { now: Date.UTC(2026, 10, 14, 12) };
  const env = { DB: makeD1(), ADMIN_EMAIL: 'lachy@gmail.com', DEV_CODES: '1' };
  const opts = { now: () => state.now, iterations: 1000 };
  const call = async (method, path, body, token, device) => {
    const res = await handle(
      new Request(`https://api.test${path}`, {
        method,
        headers: {
          'content-type': 'application/json',
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...(device ? { 'x-device-id': device, 'x-device-name': encodeURIComponent(`Teléfono ${device}`) } : {}),
        },
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
  const otro = await account('otro', 'otro@gmail.com');
  await call('POST', `/v1/admin/accounts/${org.account.id}/role`, { role: 'organizer' }, admin.token);
  await call('POST', `/v1/admin/accounts/${otro.account.id}/role`, { role: 'organizer' }, admin.token);
  return { call, state, admin, org, otro };
}

const t1 = (changedAt, name = 'T1') => ({ rows: [{ t: 'tournaments', id: 't1', changedAt, data: { id: 't1', name, status: 'swiss' } }] });

test('el teléfono que sube un torneo lo lleva; otro teléfono toma el control', async () => {
  const { call, org, otro } = await setup();
  let r = await call('POST', '/v1/sync/push', t1(1), org.token, 'A');
  assert.equal(r.data.accepted, 1);

  // Otro teléfono de la misma cuenta: sus cambios se rechazan.
  r = await call('POST', '/v1/sync/push', t1(2, 'desde B'), org.token, 'B');
  assert.deepEqual(r.data.rejected.map((x) => x.reason), ['not_controller']);
  r = await call('POST', '/v1/control/beat', { tournamentIds: ['t1'] }, org.token, 'B');
  assert.equal(r.data.controls[0].mine, false);
  assert.equal(r.data.controls[0].deviceName, 'Teléfono A');
  assert.equal(r.data.controls[0].canTake, true);

  // Otro organizador (p. ej. juez del torneo): solo consulta.
  r = await call('POST', '/v1/control/beat', { tournamentIds: ['t1'] }, otro.token, 'C');
  assert.equal(r.data.controls[0].mine, false);
  assert.equal(r.data.controls[0].canTake, false);

  // Otra cuenta no puede tomarlo.
  assert.equal((await call('POST', '/v1/control/take', { tournamentId: 't1' }, otro.token, 'C')).status, 403);

  // B toma el control: ahora sube B y A queda bloqueado.
  r = await call('POST', '/v1/control/take', { tournamentId: 't1' }, org.token, 'B');
  assert.equal(r.data.control.mine, true);
  assert.equal((await call('POST', '/v1/sync/push', t1(3, 'B'), org.token, 'B')).data.accepted, 1);
  r = await call('POST', '/v1/sync/push', t1(4, 'A'), org.token, 'A');
  assert.equal(r.data.rejected[0].reason, 'not_controller');

  // Versiones viejas (sin identificador): no se comprueba.
  assert.equal((await call('POST', '/v1/sync/push', t1(5, 'viejo'), org.token)).data.accepted, 1);

  // El organizador baja sus torneos (para seguir desde otro teléfono).
  const pull = await call('GET', '/v1/sync/pull?since=0', null, org.token, 'B');
  assert.equal(pull.data.rows.find((x) => x.id === 't1').data.name, 'viejo');
});

test('el administrador puede tomar el control de cualquier torneo', async () => {
  const { call, admin, org } = await setup();
  await call('POST', '/v1/sync/push', t1(1), org.token, 'A');
  const r = await call('POST', '/v1/control/take', { tournamentId: 't1' }, admin.token, 'ADM');
  assert.equal(r.data.control.mine, true);
});

test('borrados de otro teléfono rechazados; filas nuevas del admin quedan del dueño', async () => {
  const { call, admin, org } = await setup();
  const round = (changedAt, extra = {}) => ({ rows: [{ t: 'rounds', id: 'r1', changedAt, ...extra }] });
  await call('POST', '/v1/sync/push', t1(1), org.token, 'A');
  await call('POST', '/v1/control/take', { tournamentId: 't1' }, admin.token, 'ADM');
  // El admin sigue el torneo: crea la ronda.
  let r = await call('POST', '/v1/sync/push', round(2, { data: { id: 'r1', tournament_id: 't1', number: 1 } }), admin.token, 'ADM');
  assert.equal(r.data.accepted, 1);
  // El teléfono A (ya sin control) intenta borrarla: rechazado.
  r = await call('POST', '/v1/sync/push', round(3, { deleted: true }), org.token, 'A');
  assert.equal(r.data.rejected[0].reason, 'not_controller');
  // El organizador lo retoma y puede cambiar la ronda que creó el admin.
  await call('POST', '/v1/control/take', { tournamentId: 't1' }, org.token, 'A');
  r = await call('POST', '/v1/sync/push', round(4, { data: { id: 'r1', tournament_id: 't1', number: 1, x: 1 } }), org.token, 'A');
  assert.equal(r.data.accepted, 1);
});

test('base restaurada desde una copia: el teléfono que va por delante baja todo', async () => {
  const { call, org } = await setup();
  await call('POST', '/v1/sync/push', t1(1), org.token, 'A');
  const now = await call('GET', '/v1/sync/pull?since=0', null, org.token, 'A');
  assert.ok(now.data.seq > 0);
  let r = await call('GET', `/v1/sync/pull?since=${now.data.seq}`, null, org.token, 'A');
  assert.equal(r.data.reset, undefined); // al día: nada nuevo
  r = await call('GET', `/v1/sync/pull?since=${now.data.seq + 500}`, null, org.token, 'A');
  assert.equal(r.data.reset, true);
  assert.equal(r.data.seq, 0);
  assert.equal(r.data.more, true);
});
