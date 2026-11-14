import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/index.js';
import { makeD1 } from './d1_shim.mjs';

test('/v1/poll: varias consultas y el latido en una sola petición', async () => {
  const env = { DB: makeD1(), ADMIN_EMAIL: 'lachy@gmail.com', DEV_CODES: '1' };
  const opts = { now: () => Date.UTC(2026, 10, 14, 12), iterations: 1000 };
  const call = async (method, path, body, token, device) => {
    const res = await handle(
      new Request(`https://api.test${path}`, {
        method,
        headers: {
          'content-type': 'application/json',
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...(device ? { 'x-device-id': device } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
      }),
      env,
      opts,
    );
    return { status: res.status, data: await res.json() };
  };
  const reg = await call('POST', '/v1/auth/register', { username: 'org', email: 'org@gmail.com', password: 'clave1234', nickname: 'Org' });
  const org = (await call('POST', '/v1/auth/verify', { email: 'org@gmail.com', code: reg.data.devCode })).data.session;
  const reg2 = await call('POST', '/v1/auth/register', { username: 'lachy', email: 'lachy@gmail.com', password: 'clave1234', nickname: 'L' });
  const admin = (await call('POST', '/v1/auth/verify', { email: 'lachy@gmail.com', code: reg2.data.devCode })).data.session;
  await call('POST', `/v1/admin/accounts/${org.account.id}/role`, { role: 'organizer' }, admin.token);
  await call('POST', '/v1/sync/push', { rows: [{ t: 'tournaments', id: 't1', changedAt: 1, data: { id: 't1', name: 'T', status: 'swiss' } }] }, org.token, 'A');

  const r = await call('POST', '/v1/poll', {
    gets: ['v1/sync/pull?since=0', 'v1/me/judging', 'v1/play/todo', 'v1/registrations/todo', 'v1/play?tournament=otro', 'v1/nada'],
    beat: ['t1'],
  }, org.token, 'A');
  assert.equal(r.status, 200);
  assert.equal(r.data.results['v1/sync/pull?since=0'].status, 200);
  assert.ok(r.data.results['v1/sync/pull?since=0'].data.rows.some((x) => x.id === 't1'));
  assert.deepEqual(r.data.results['v1/me/judging'].data.tournaments, []);
  assert.equal(r.data.results['v1/play/todo'].status, 200);
  assert.equal(r.data.results['v1/nada'].status, 404);
  assert.equal(r.data.beat.controls[0].mine, true);

  // Sin sesión: 401 para todo.
  assert.equal((await call('POST', '/v1/poll', { gets: ['v1/me/judging'] })).status, 401);
});
