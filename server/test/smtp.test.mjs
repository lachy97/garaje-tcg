import test from 'node:test';
import assert from 'node:assert/strict';
import { buildMessage, sendSmtp } from '../src/smtp.js';
import { mailConfigured, sendCode } from '../src/mail.js';

/** Servidor SMTP falso: responde según lo que recibe. */
function fakeSmtp({ authOk = true } = {}) {
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  const log = [];
  let ctrl;
  const readable = new ReadableStream({ start: (c) => (ctrl = c) });
  const say = (s) => ctrl.enqueue(enc.encode(s));
  let buf = '';
  let inData = false;
  let data = '';
  const writable = new WritableStream({
    write(chunk) {
      buf += dec.decode(chunk);
      let i;
      while ((i = buf.indexOf('\r\n')) >= 0) {
        const line = buf.slice(0, i);
        buf = buf.slice(i + 2);
        if (inData) {
          if (line === '.') {
            inData = false;
            log.push({ data });
            say('250 2.0.0 OK queued\r\n');
          } else data += `${line}\r\n`;
          continue;
        }
        log.push(line);
        if (line.startsWith('EHLO')) say('250-smtp.gmail.com\r\n250-AUTH LOGIN PLAIN\r\n250 SMTPUTF8\r\n');
        else if (line.startsWith('AUTH')) say(authOk ? '235 2.7.0 Accepted\r\n' : '535-5.7.8 Username and Password not accepted\r\n535 5.7.8 BadCredentials\r\n');
        else if (line.startsWith('MAIL FROM') || line.startsWith('RCPT TO')) say('250 2.1.0 OK\r\n');
        else if (line === 'DATA') {
          inData = true;
          say('354 Go ahead\r\n');
        } else if (line === 'QUIT') say('221 bye\r\n');
      }
    },
  });
  say('220 smtp.gmail.com ESMTP ready\r\n');
  const connect = async (host, port) => {
    log.push({ host, port });
    return { readable, writable, close() {} };
  };
  return { connect, log };
}

test('Gmail SMTP: conversación completa y mensaje con acentos', async () => {
  const env = { GMAIL_USER: 'club@gmail.com', GMAIL_APP_PASSWORD: 'abcd efgh ijkl mnop' };
  assert.equal(mailConfigured(env), true);
  const s = fakeSmtp();
  await sendCode(env, 'leo@gmail.com', '123456', 'verify', fetch, Date.UTC(2026, 10, 10), s.connect);
  assert.deepEqual(s.log[0], { host: 'smtp.gmail.com', port: 465 });
  const auth = s.log.find((l) => typeof l === 'string' && l.startsWith('AUTH PLAIN'));
  assert.equal(Buffer.from(auth.slice(11), 'base64').toString(), '\u0000club@gmail.com\u0000abcdefghijklmnop');
  assert.ok(s.log.includes('MAIL FROM:<club@gmail.com>'));
  assert.ok(s.log.includes('RCPT TO:<leo@gmail.com>'));
  const { data } = s.log.find((l) => l.data);
  assert.match(data, /Subject: =\?UTF-8\?B\?/);
  assert.match(data, /From: Garage TCG <club@gmail.com>/);
  const parts = [...data.matchAll(/base64\r\n\r\n([A-Za-z0-9+/=\r\n]+?)\r\n--/g)].map((m) =>
    Buffer.from(m[1].replace(/\r\n/g, ''), 'base64').toString(),
  );
  assert.match(parts[0], /código.*123456/);
  assert.match(parts[1], /<b>Garage TCG<\/b>/);
});

test('Gmail SMTP: contraseña rechazada → error claro', async () => {
  const s = fakeSmtp({ authOk: false });
  await assert.rejects(
    sendSmtp(s.connect, { host: 'h', port: 465, user: 'u', pass: 'p', from: 'u', to: 't', message: 'x' }),
    /SMTP AUTH: 535-5.7.8/,
  );
});

test('buildMessage', () => {
  const m = buildMessage({ fromName: 'Garage TCG', from: 'a@gmail.com', to: 'b@gmail.com', subject: 'Hola', text: 't', html: 'h', date: 'd', messageId: 'id@x' });
  assert.match(m, /Subject: Hola\r\n/);
  assert.match(m, /multipart\/alternative/);
});
