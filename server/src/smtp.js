// Cliente SMTP mínimo para Workers (sockets TCP de Cloudflare) con TLS
// directo (puerto 465). Se usa para enviar desde el Gmail del club con una
// "contraseña de aplicación".

const enc = new TextEncoder();
const dec = new TextDecoder();

function b64(text) {
  let s = '';
  for (const b of enc.encode(text)) s += String.fromCharCode(b);
  return btoa(s);
}

/** Cabecera con acentos (RFC 2047). */
const encodeHeader = (text) => (/^[\x20-\x7e]*$/.test(text) ? text : `=?UTF-8?B?${b64(text)}?=`);

/** Base64 en líneas de 76 caracteres. */
const wrap76 = (s) => s.replace(/.{1,76}/g, (m) => `${m}\r\n`);

/** Mensaje MIME (texto + HTML) listo para DATA. */
export function buildMessage({ fromName, from, to, subject, text, html, date, messageId }) {
  const boundary = `gtcg-${messageId.replace(/[^a-z0-9]/gi, '')}`;
  const headers = [
    `From: ${encodeHeader(fromName)} <${from}>`,
    `To: <${to}>`,
    `Subject: ${encodeHeader(subject)}`,
    `Date: ${date}`,
    `Message-ID: <${messageId}>`,
    'MIME-Version: 1.0',
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
  ];
  const part = (type, content) =>
    `--${boundary}\r\nContent-Type: ${type}; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${wrap76(b64(content))}`;
  return `${headers.join('\r\n')}\r\n\r\n${part('text/plain', text)}${part('text/html', html)}--${boundary}--\r\n`;
}

/** Lee respuestas SMTP ("250-…" multilínea hasta "250 …"). */
class Reader {
  constructor(readable) {
    this.reader = readable.getReader();
    this.buf = '';
  }

  async line() {
    for (;;) {
      const i = this.buf.indexOf('\r\n');
      if (i >= 0) {
        const l = this.buf.slice(0, i);
        this.buf = this.buf.slice(i + 2);
        return l;
      }
      const { value, done } = await this.reader.read();
      if (done) throw new Error('SMTP: conexión cerrada');
      this.buf += dec.decode(value, { stream: true });
    }
  }

  async reply() {
    const lines = [];
    for (;;) {
      const l = await this.line();
      lines.push(l);
      if (/^\d{3} /.test(l) || /^\d{3}$/.test(l)) break;
    }
    return { code: Number(lines[lines.length - 1].slice(0, 3)), text: lines.join(' | ') };
  }
}

/**
 * Envía un correo por SMTP con TLS directo.
 * @param connect  función (host, port) → socket { readable, writable, close() }
 */
export async function sendSmtp(connect, { host, port, user, pass, from, to, message, heloName = 'garage-tcg' }) {
  const socket = await connect(host, port);
  const r = new Reader(socket.readable);
  const w = socket.writable.getWriter();
  const send = (s) => w.write(enc.encode(s));
  const expect = async (codes, what) => {
    const res = await r.reply();
    if (!codes.includes(res.code)) throw new Error(`SMTP ${what}: ${res.text.slice(0, 200)}`);
    return res;
  };
  try {
    await expect([220], 'saludo');
    await send(`EHLO ${heloName}\r\n`);
    await expect([250], 'EHLO');
    await send(`AUTH PLAIN ${b64(`\u0000${user}\u0000${pass}`)}\r\n`);
    await expect([235], 'AUTH');
    await send(`MAIL FROM:<${from}>\r\n`);
    await expect([250], 'MAIL FROM');
    await send(`RCPT TO:<${to}>\r\n`);
    await expect([250, 251], 'RCPT TO');
    await send('DATA\r\n');
    await expect([354], 'DATA');
    // Las líneas que empiezan por "." se duplican (no pasa con base64, por si acaso).
    await send(`${message.replace(/\r\n\./g, '\r\n..')}\r\n.\r\n`);
    await expect([250], 'envío');
    await send('QUIT\r\n');
  } finally {
    try {
      await w.close();
    } catch {
      // ya cerrado
    }
    try {
      socket.close();
    } catch {
      // ya cerrado
    }
  }
}

/** Conexión TLS con los sockets de Cloudflare Workers. */
export async function cloudflareConnect(host, port) {
  const { connect } = await import('cloudflare:sockets');
  const socket = connect({ hostname: host, port }, { secureTransport: 'on' });
  await socket.opened;
  return socket;
}
