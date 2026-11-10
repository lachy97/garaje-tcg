// Envío de los códigos por correo con Brevo (300 correos gratis al día).
// https://developers.brevo.com/reference/sendtransacemail

const SUBJECTS = {
  verify: 'Tu código para confirmar la cuenta de Garage TCG',
  reset: 'Tu código para cambiar la contraseña de Garage TCG',
};

function body(code, purpose) {
  const what = purpose === 'verify' ? 'confirmar tu cuenta' : 'poner una contraseña nueva';
  return {
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

/** true si el envío de correos está configurado. */
export const mailConfigured = (env) => Boolean(env.BREVO_API_KEY && env.MAIL_FROM);

/** Envía el código. Lanza Error si Brevo lo rechaza. */
export async function sendCode(env, to, code, purpose) {
  const { text, html } = body(code, purpose);
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': env.BREVO_API_KEY,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      sender: { email: env.MAIL_FROM, name: env.MAIL_FROM_NAME || 'Garage TCG' },
      to: [{ email: to }],
      subject: SUBJECTS[purpose],
      textContent: text,
      htmlContent: html,
    }),
  });
  if (!res.ok) {
    throw new Error(`Brevo ${res.status}: ${(await res.text()).slice(0, 200)}`);
  }
}
