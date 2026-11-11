// Envío de los códigos por correo. Se usa el primero configurado:
// 1. Gmail del club por SMTP (GMAIL_USER + GMAIL_APP_PASSWORD), ~500/día.
// 2. SendPulse (SENDPULSE_ID + SENDPULSE_SECRET + MAIL_FROM).
// 3. Brevo (BREVO_API_KEY + MAIL_FROM).
import { buildMessage, cloudflareConnect, sendSmtp } from './smtp.js';

const SUBJECTS = {
  verify: 'Tu código para confirmar la cuenta de Garage TCG',
  reset: 'Tu código para cambiar la contraseña de Garage TCG',
  test: 'Correo de prueba de Garage TCG',
};

function body(code, purpose) {
  const what =
    purpose === 'verify'
      ? 'confirmar tu cuenta'
      : purpose === 'reset'
        ? 'poner una contraseña nueva'
        : 'probar el envío de correos (no hace falta usarlo)';
  return {
    subject: SUBJECTS[purpose],
    text:
      `Tu código para ${what} en Garage TCG es: ${code}\n\n` +
      'Vale 15 minutos. Si no lo pediste, ignora este correo.',
    html:
      '<div style="font-family:Arial,sans-serif;font-size:15px;color:#111">' +
      `<p>Tu código para ${what} en <b>Garage TCG</b> es:</p>` +
      `<p style="font-size:32px;font-weight:bold;letter-spacing:6px">${code}</p>` +
      '<p>Vale 15 minutos. Si no lo pediste, ignora este correo.</p></div>',
  };
}

const usesGmail = (env) => Boolean(env.GMAIL_USER && env.GMAIL_APP_PASSWORD);
const usesSendPulse = (env) => Boolean(env.SENDPULSE_ID && env.SENDPULSE_SECRET);

/** Qué proveedor se usaría (para el diagnóstico del administrador). */
export const mailProvider = (env) =>
  usesGmail(env) ? 'gmail' : !env.MAIL_FROM ? null : usesSendPulse(env) ? 'sendpulse' : env.BREVO_API_KEY ? 'brevo' : null;

/** true si el envío de correos está configurado. */
export const mailConfigured = (env) =>
  usesGmail(env) || Boolean(env.MAIL_FROM && (usesSendPulse(env) || env.BREVO_API_KEY));

/** Base64 de un texto UTF-8 (SendPulse pide el HTML así). */
export function base64Utf8(text) {
  const bytes = new TextEncoder().encode(text);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

// Token de SendPulse (dura 1 h); se guarda mientras viva el Worker.
let spToken = null;

async function sendPulseToken(env, fetchFn, now) {
  if (spToken && spToken.key === env.SENDPULSE_ID && spToken.expires > now + 60_000) {
    return spToken.value;
  }
  const res = await fetchFn('https://api.sendpulse.com/oauth/access_token', {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({
      grant_type: 'client_credentials',
      client_id: env.SENDPULSE_ID,
      client_secret: env.SENDPULSE_SECRET,
    }),
  });
  if (!res.ok) throw new Error(`SendPulse token ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const data = await res.json();
  if (!data.access_token) throw new Error('SendPulse: sin access_token');
  spToken = {
    key: env.SENDPULSE_ID,
    value: data.access_token,
    expires: now + (Number(data.expires_in) || 3600) * 1000,
  };
  return spToken.value;
}

/** Olvida el token guardado (tests). */
export function resetMailCache() {
  spToken = null;
}

async function sendWithSendPulse(env, to, mail, fetchFn, now) {
  const post = async (token) =>
    fetchFn('https://api.sendpulse.com/smtp/emails', {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
        accept: 'application/json',
      },
      body: JSON.stringify({
        email: {
          subject: mail.subject,
          html: base64Utf8(mail.html),
          text: mail.text,
          from: { name: env.MAIL_FROM_NAME || 'Garage TCG', email: env.MAIL_FROM },
          to: [{ email: to }],
        },
      }),
    });
  let res = await post(await sendPulseToken(env, fetchFn, now));
  if (res.status === 401) {
    // Token vencido antes de tiempo: se pide otro y se reintenta una vez.
    spToken = null;
    res = await post(await sendPulseToken(env, fetchFn, now));
  }
  const text = await res.text();
  if (!res.ok) throw new Error(`SendPulse ${res.status}: ${text.slice(0, 200)}`);
  let data = {};
  try {
    data = JSON.parse(text);
  } catch {
    // respuesta sin JSON: se da por buena si el código HTTP lo es
  }
  if (data.result === false) throw new Error(`SendPulse: ${text.slice(0, 200)}`);
}

async function sendWithBrevo(env, to, mail, fetchFn) {
  const res = await fetchFn('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': env.BREVO_API_KEY,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      sender: { email: env.MAIL_FROM, name: env.MAIL_FROM_NAME || 'Garage TCG' },
      to: [{ email: to }],
      subject: mail.subject,
      textContent: mail.text,
      htmlContent: mail.html,
    }),
  });
  if (!res.ok) throw new Error(`Brevo ${res.status}: ${(await res.text()).slice(0, 200)}`);
}

async function sendWithGmail(env, to, mail, connectFn, now) {
  const user = String(env.GMAIL_USER).trim();
  // Las contraseñas de aplicación de Google se muestran con espacios.
  const pass = String(env.GMAIL_APP_PASSWORD).replace(/\s+/g, '');
  const from = env.MAIL_FROM || user;
  const message = buildMessage({
    fromName: env.MAIL_FROM_NAME || 'Garage TCG',
    from,
    to,
    subject: mail.subject,
    text: mail.text,
    html: mail.html,
    date: new Date(now).toUTCString(),
    messageId: `${crypto.randomUUID()}@garage-tcg`,
  });
  await sendSmtp(connectFn, { host: 'smtp.gmail.com', port: 465, user, pass, from, to, message });
}

/** Envía el código. Lanza Error si el proveedor lo rechaza. */
export async function sendCode(
  env,
  to,
  code,
  purpose,
  fetchFn = fetch,
  now = Date.now(),
  connectFn = cloudflareConnect,
) {
  const mail = body(code, purpose);
  if (usesGmail(env)) return sendWithGmail(env, to, mail, connectFn, now);
  if (usesSendPulse(env)) return sendWithSendPulse(env, to, mail, fetchFn, now);
  return sendWithBrevo(env, to, mail, fetchFn);
}
