# Servidor de Garage TCG (Cloudflare Workers + D1)

Servidor de **cuentas y roles** de la app: registro con Gmail, código de
verificación, inicio de sesión, contraseña olvidada y panel del
administrador (roles, vincular ficha, confirmar a mano). Plan gratuito de
Cloudflare: 100.000 peticiones al día y una base de datos SQLite (D1) de 5 GB.

- `src/index.js` · rutas de la API (`/v1/...`)
- `src/auth.js` · lógica de cuentas (mismas reglas que la app)
- `src/mail.js` · envío de códigos con Brevo
- `migrations/0001_init.sql` · tablas
- `test/` · pruebas (`npm test`, sin internet ni Cloudflare)

> **Si algo no abre desde Cuba** (la web de Cloudflare, nodejs.org, Brevo o
> la dirección del servidor), usa la **VPN**. La cuenta y la publicación se
> hacen una sola vez.

---

## 1 · Crear la cuenta de Cloudflare (una vez)

1. Entra a **https://dash.cloudflare.com/sign-up** y regístrate con tu correo y
   una contraseña. Es gratis y no pide tarjeta.
2. Confirma el correo que te envían.

## 2 · Instalar Node.js en el PC (una vez)

1. Descarga la versión **LTS** de **https://nodejs.org** e instálala
   (Siguiente → Siguiente…).
2. Abre una terminal **nueva** (PowerShell) y comprueba:
   ```powershell
   node -v
   ```
   Debe salir `v22…` o más.

## 3 · Preparar la carpeta del servidor

```powershell
cd D:\Work\Movil\Yu-Gi-OH\server
npm install
npx wrangler login
```

`wrangler login` abre el navegador: entra con tu cuenta de Cloudflare y pulsa
**Allow**.

## 4 · Crear la base de datos

```powershell
npx wrangler d1 create garage-tcg
```

Copia el valor de `database_id` que aparece y pégalo en `wrangler.toml`, en
lugar de `PEGA-AQUI-EL-DATABASE-ID`. Luego crea las tablas:

```powershell
npm run db:init
```

## 5 · Publicar

```powershell
npm run deploy
```

La primera vez te pide elegir un subdominio de `workers.dev` (por ejemplo
tu nombre). Al terminar muestra la dirección del servidor:

```
https://garage-tcg-api.<tu-subdominio>.workers.dev
```

Cada vez que cambie algo en `server/`, basta con repetir `npm run deploy`.

## 6 · Tu Gmail de administrador

(Después de publicar: el secreto se guarda en el Worker ya creado.)

```powershell
npx wrangler secret put ADMIN_EMAIL
```

Escribe **tu Gmail** y pulsa Enter. La cuenta que se registre con ese
correo será **Administrador**; todas las demás empiezan como **Jugador**.
Si alguna vez wrangler pregunta si quieres crear un Worker nuevo con ese
nombre, es que aún no publicaste: haz primero el paso 5.

## 7 · Fase 0: probar desde Cuba

1. En el teléfono, **con datos de Etecsa y sin VPN**, abre en el navegador:
   `https://garage-tcg-api.<tu-subdominio>.workers.dev/v1/health`
   Debe salir algo como `{"ok":true,"service":"garage-tcg",...}`.
2. En la app: **Ajustes → Servidor → Probar conexión con un servidor** y pega
   la dirección. Dice cuántos milisegundos tarda.
3. Si **no** responde sin VPN, prueba con la VPN. Si con VPN sí funciona, se
   sigue adelante: los teléfonos usarán la VPN para conectarse (los torneos
   siguen funcionando sin conexión como siempre).

## 8 · Conectar la app con el servidor

1. Abre `lib/core/auth/server_config.dart` y pon la dirección (sin barra final):
   ```dart
   const kServerUrl = 'https://garage-tcg-api.<tu-subdominio>.workers.dev';
   ```
2. `git add -A` · `git commit` · `git push` → GitHub compila la APK.
3. En la APK nueva: **Ajustes → Cuenta → Crear cuenta** con tu Gmail de
   administrador.

Mientras no configures los correos (paso 9), el servidor está en **modo de
pruebas** (`DEV_CODES = "1"` en `wrangler.toml`): el código no llega al
correo, sino que la app lo muestra en un recuadro amarillo. **No lo dejes así
cuando los jugadores empiecen a registrarse.**

## 9 · Correos de verificación con Brevo

1. Crea el Gmail del club (por ejemplo `garagetcg.cuba@gmail.com`).
2. Regístrate en **https://www.brevo.com** con ese Gmail (plan Free: 300
   correos al día).
3. En Brevo: **Senders, Domains & Dedicated IPs → Senders → Add a sender**:
   nombre `Garage TCG` y el Gmail del club. Confírmalo con el correo que te
   llega.
4. **SMTP & API → API Keys → Generate a new API key**. Copia la clave
   (empieza por `xkeysib-`).
5. En el PC:
   ```powershell
   npx wrangler secret put BREVO_API_KEY
   npx wrangler secret put MAIL_FROM
   ```
   (en el primero pega la clave; en el segundo, el Gmail del club).
6. En `wrangler.toml` cambia `DEV_CODES = "1"` por `DEV_CODES = "0"` y publica:
   ```powershell
   npm run deploy
   ```

Los correos que se envían desde un Gmail a través de Brevo pueden caer en
**Spam** más a menudo; la app ya avisa de mirar ahí. Con un dominio propio
(más adelante) llegan mejor.

## Útil

| Para | Comando |
|---|---|
| Ver lo que pasa en el servidor en vivo | `npm run logs` |
| Pruebas (Node 22, sin internet) | `npm test` |
| Ver las cuentas en la base | `npx wrangler d1 execute garage-tcg --remote --command "SELECT username, email, role, verified FROM accounts"` |
| Hacer administrador a mano | `npx wrangler d1 execute garage-tcg --remote --command "UPDATE accounts SET role='admin' WHERE email='tu@gmail.com'"` |

## API (v1)

| Método | Ruta | Cuerpo / cabecera |
|---|---|---|
| GET | `/v1/health` | — |
| POST | `/v1/auth/register` | `username, email, password, nickname, phone?` |
| POST | `/v1/auth/resend` | `email` |
| POST | `/v1/auth/verify` | `email, code` → `session` |
| POST | `/v1/auth/login` | `identifier, password` → `session` |
| POST | `/v1/auth/password/request` | `identifier` |
| POST | `/v1/auth/password/reset` | `identifier, code, newPassword` |
| POST | `/v1/auth/logout` | `Authorization: Bearer <token>` |
| GET | `/v1/me` | `Authorization` |
| GET | `/v1/admin/accounts` | `Authorization` (admin) |
| POST | `/v1/admin/accounts/:id/role` | `role` (admin) |
| POST | `/v1/admin/accounts/:id/player` | `playerId` o `null` (admin) |
| POST | `/v1/admin/accounts/:id/verify` | (admin) |

Errores: código HTTP 4xx con `{ "error": "mensaje para el usuario" }`; si la
cuenta no está confirmada, además `"code": "unverified"` y `"email"`.

Seguridad: contraseñas con PBKDF2-SHA256 (100.000 iteraciones, sal propia),
sesiones de 30 días guardadas como hash, códigos guardados como hash, 5
intentos por código, 3 códigos por hora, 10 inicios fallidos cada 15 minutos.
