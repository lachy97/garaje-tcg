import test from 'node:test';
import assert from 'node:assert/strict';
import { base64Utf8, mailConfigured, resetMailCache, sendCode } from '../src/mail.js';

const env = { SENDPULSE_ID: 'id', SENDPULSE_SECRET: 'sec', MAIL_FROM: 'club@gmail.com' };

function fakeFetch(responses) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, body: JSON.parse(init.body), headers: init.headers });
    const r = responses.shift();
    return new Response(JSON.stringify(r.body), { status: r.status ?? 200 });
  };
  return { fn, calls };
}

test('configuración', () => {
  assert.equal(mailConfigured(env), true);
  assert.equal(mailConfigured({ ...env, MAIL_FROM: '' }), false);
  assert.equal(mailConfigured({ BREVO_API_KEY: 'k', MAIL_FROM: 'a@gmail.com' }), true);
  assert.equal(mailConfigured({ MAIL_FROM: 'a@gmail.com' }), false);
});

test('SendPulse: token, envío con HTML en base64 y token reutilizado', async () => {
  resetMailCache();
  const { fn, calls } = fakeFetch([
    { body: { access_token: 'T1', expires_in: 3600 } },
    { body: { result: true, id: 'x' } },
    { body: { result: true, id: 'y' } },
  ]);
  await sendCode(env, 'leo@gmail.com', '123456', 'verify', fn, 0);
  await sendCode(env, 'leo@gmail.com', '654321', 'reset', fn, 1000);
  assert.equal(calls.length, 3); // el token solo se pide una vez
  assert.equal(calls[0].url, 'https://api.sendpulse.com/oauth/access_token');
  assert.equal(calls[0].body.client_id, 'id');
  assert.equal(calls[1].headers.authorization, 'Bearer T1');
  const email = calls[1].body.email;
  assert.deepEqual(email.to, [{ email: 'leo@gmail.com' }]);
  assert.equal(email.from.email, 'club@gmail.com');
  assert.match(email.text, /123456/);
  const html = new TextDecoder().decode(Uint8Array.from(atob(email.html), (c) => c.charCodeAt(0)));
  assert.match(html, /código/);
  assert.match(html, /123456/);
});

test('SendPulse: 401 → pide otro token y reintenta; error → lanza', async () => {
  resetMailCache();
  const { fn, calls } = fakeFetch([
    { body: { access_token: 'T1' } },
    { status: 401, body: { error: 'expired' } },
    { body: { access_token: 'T2' } },
    { body: { result: true } },
  ]);
  await sendCode(env, 'leo@gmail.com', '1', 'verify', fn, 0);
  assert.equal(calls[3].headers.authorization, 'Bearer T2');

  resetMailCache();
  const bad = fakeFetch([{ body: { access_token: 'T' } }, { status: 422, body: { message: 'Sender not valid' } }]);
  await assert.rejects(sendCode(env, 'leo@gmail.com', '1', 'verify', bad.fn, 0), /SendPulse 422/);
});

test('base64 UTF-8', () => {
  assert.equal(base64Utf8('ñ'), 'w7E=');
});
