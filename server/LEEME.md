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

## 9 · Correos de verificación desde el Gmail del club

El servidor envía los códigos directamente por el SMTP de Gmail con una
**contraseña de aplicación** (no la contraseña normal). Gratis, sin dominio
ni proveedores, hasta ~500 correos al día. Si un correo no sale, la cuenta
se crea igual y el administrador la confirma a mano en **Cuentas y roles**
(y puede darle un código de contraseña para mandarlo por WhatsApp).

1. Crea el Gmail del club (por ejemplo `garagetcg.cuba@gmail.com`).
2. Activa la **Verificación en 2 pasos** en ese Gmail:
   **myaccount.google.com → Seguridad → Verificación en 2 pasos**.
3. Crea la contraseña de aplicación en
   **https://myaccount.google.com/apppasswords**: nombre `Garage TCG` →
   **Crear**. Copia las 16 letras (los espacios dan igual).
4. En el PC:
   ```powershell
   npx wrangler secret put GMAIL_USER
   npx wrangler secret put GMAIL_APP_PASSWORD
   ```
   (el Gmail del club y la contraseña de aplicación).
5. Si antes configuraste SendPulse o Brevo, borra el remitente viejo (si no,
   se usaría como "De:"):
   ```powershell
   npx wrangler secret delete MAIL_FROM
   ```
   (`SENDPULSE_ID`/`SENDPULSE_SECRET` pueden quedarse: si hay Gmail, se usa
   Gmail.)
6. `DEV_CODES = "0"` en `wrangler.toml` y `npm run deploy`.
7. Prueba creando una cuenta con otro Gmail (mira también en **Spam**). Si
   falla, `npm run logs`: la línea `mail Error: SMTP …` dice el motivo (p. ej.
   `SMTP AUTH: 535` = usuario o contraseña de aplicación incorrectos).

Alternativas ya programadas (se usan si no hay Gmail configurado):
SendPulse (`SENDPULSE_ID`, `SENDPULSE_SECRET`, `MAIL_FROM` de un dominio
verificado) o Brevo (`BREVO_API_KEY`, `MAIL_FROM`).

## 10 · Sincronización (fase 2)

Los teléfonos de los organizadores suben sus datos (jugadores, mazos,
temporadas, torneos, resultados, listas…) al servidor. Para activarla en
un servidor ya publicado (una vez):

```powershell
npm run db:sync
npm run deploy
```

Luego, en la app (con sesión de organizador o administrador): **Ajustes →
Sincronización**. La primera vez sube todo; después, cada 30 s y al
volver a la app, solo lo que cambió. Sin conexión los cambios esperan en
la cola.

## 11 · Fase 3: datos en los teléfonos de los jugadores

Una vez, en el PC:

```powershell
npm run db:fase3
npm run deploy
```

Los jugadores y jueces que inician sesión bajan del servidor lo que pueden
ver: catálogo de mazos, temporadas, ranking y tier list, los torneos
terminados y aquellos en los que están inscritos (en vivo), y su propia
ficha. De los demás jugadores solo llega el apodo.

## 12 · Inscripción desde la app

Una vez, en el PC (con VPN):

```powershell
npm run db:inscripcion
npm run deploy
```

El organizador abre la inscripción desde la app en la pestaña **Jugadores**
del torneo (mientras está en inscripción) y elige si las solicitudes se
aceptan **a mano** o **solas**. Los jugadores la piden desde **Torneos →
Inscripción abierta** con su mazo. El teléfono del organizador inscribe a los
aceptados al sincronizar.

## 13 · Resultados, juez y drop desde el móvil

Una vez, en el PC (con VPN):

```powershell
npm run db:mesa
npm run deploy
```

## 14 · Check-in y jueces por torneo

Una vez, en el PC (con VPN):

```powershell
npm run db:jueces
npm run deploy
```

## 15 · Versión mínima de la app

Cuando todos hayan instalado una versión nueva y quieras que las viejas
dejen de usar el servidor (p. ej. porque cambió algo importante), pon el
número de compilación de GitHub Actions (el `#` de la ejecución que generó la
APK) como mínimo:

```powershell
npx wrangler secret put MIN_APP_BUILD
```

Las versiones anteriores verán "Hay una versión nueva de Garage TCG". Para
quitarlo: `npx wrangler secret delete MIN_APP_BUILD`.

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
| POST | `/v1/sync/push` | `rows: [{t, id, changedAt, deleted?, data?}]` (organizador/admin) |
| GET | `/v1/sync/pull?since=&limit=` | (organizador/admin) |
| GET | `/v1/sync/status` | (organizador/admin) |
| POST | `/v1/admin/accounts/:id/role` | `role` (admin) |
| POST | `/v1/admin/accounts/:id/player` | `playerId` o `null` (admin) |
| POST | `/v1/admin/accounts/:id/verify` | (admin) |
| POST | `/v1/admin/accounts/:id/reset-code` | (admin) → `code` para mandar por WhatsApp |
| GET | `/v1/me` | también renueva la sesión → `expiresAt` |
| POST | `/v1/registrations` | `tournamentId, deckName` (jugador: pedir plaza o cambiar el mazo) |
| GET | `/v1/registrations/mine` | (jugador) → `registrations`, `open` (torneos abiertos), `playerId` |
| POST | `/v1/registrations/:id/cancel` | (jugador) |
| GET | `/v1/registrations?tournament=` | (organizador del torneo / admin) |
| GET | `/v1/registrations/todo` | (organizador) aceptadas por inscribir y bajas por quitar |
| POST | `/v1/registrations/:id/accept` | `playerId?` (vincula la cuenta si no tenía ficha) |
| POST | `/v1/registrations/:id/reject` | `reason?` |
| POST | `/v1/registrations/:id/done` | (organizador) ya inscrito / ya quitado |
| POST | `/v1/play/report` | `tournamentId, matchId, g1, gd, g2` (jugador de esa mesa) |
| POST | `/v1/play/:id/confirm` · `/dispute` | (el rival) |
| POST | `/v1/play/judge` · `/v1/play/drop` | `tournamentId, matchId?, note?` |
| POST | `/v1/play/:id/cancel` | (quien lo envió) |
| GET | `/v1/play/mine?tournament=` | (jugador) |
| GET | `/v1/play?tournament=` | (organizador del torneo) avisos abiertos |
| GET | `/v1/play/todo` | (organizador) confirmados y drops por aplicar |
| POST | `/v1/play/:id/done` | (organizador) aplicado / atendido |
| POST | `/v1/play/checkin` | `tournamentId, code` (jugador inscrito) |
| POST | `/v1/play/judge-result` | `tournamentId, matchId, g1, gd, g2` o `doubleLoss` (juez u organizador) |
| POST | `/v1/play/extension` | `tournamentId, matchId, minutes` (juez) |
| POST | `/v1/play/penalty` | `tournamentId, playerId, penalty, reason?` (juez) |
| GET | `/v1/staff/candidates` | (organizador) cuentas que pueden ser jueces |
| GET/POST | `/v1/tournaments/:id/judges` | listar / añadir `accountId` (organizador del torneo) |
| POST | `/v1/tournaments/:id/judges/:accountId/remove` | (organizador del torneo) |
| GET | `/v1/me/judging` | torneos donde soy juez |

Errores: código HTTP 4xx con `{ "error": "mensaje para el usuario" }`; si la
cuenta no está confirmada, además `"code": "unverified"` y `"email"`.

Seguridad: contraseñas con PBKDF2-SHA256 (100.000 iteraciones, sal propia),
sesiones de 30 días guardadas como hash, códigos guardados como hash, 5
intentos por código, 3 códigos por hora, 10 inicios fallidos cada 15 minutos.

## 16 · Seguir un torneo desde otro teléfono

Una vez, en el PC (con VPN):

```powershell
npm run db:control
npm run deploy
```

Cada torneo lo lleva un solo teléfono (el primero que lo sube). Si ese
teléfono se queda sin batería o sin datos, el organizador entra con su cuenta
en otro teléfono (o el administrador en el suyo), abre el torneo y toca
**Tomar el control**. Lo que el primer teléfono no llegó a subir se pierde.

## 17 · Copia de seguridad antes de cada torneo

**Antes de empezar cada torneo**, en el PC (con VPN), dentro de `server`:

```powershell
npm run backup
```

Deja en `server/backups/` dos archivos con la fecha y la hora:

- `garage-tcg_AAAA-MM-DD_HHMM.sql`: la base entera.
- `garage-tcg_AAAA-MM-DD_HHMM.marca.txt`: la **marca** (bookmark) de ese
  momento, para volver la base justo ahí.

La carpeta `backups` **no se sube a git** (tiene correos, teléfonos y datos de
las cuentas). No compartas esos archivos. Si quieres, copia de vez en cuando
la carpeta a un pendrive.

Además, Cloudflare guarda solo el historial de la base (*Time Travel*): se
puede volver a cualquier minuto de los últimos **7 días** (plan gratis; 30 en
el de pago). `npm run backup:info` muestra la marca actual.

### Si algo sale mal: volver la base atrás

**A. Dentro de los últimos 7 días** (lo normal): con la marca de la copia

```powershell
npx wrangler d1 time-travel restore garage-tcg --bookmark=MARCA_DEL_ARCHIVO
```

o a una hora concreta (hora de Cuba, ojo al `-05:00` / `-04:00` en verano):

```powershell
npx wrangler d1 time-travel restore garage-tcg --timestamp=2026-11-14T15:00:00-05:00
```

Se pierde **todo** lo que cambió después en el servidor (de todos los
torneos). El propio comando muestra una marca para deshacer la restauración.

**B. Más de 7 días o se perdió la base**: desde el `.sql`, en una base nueva

```powershell
npx wrangler d1 create garage-tcg-2
npx wrangler d1 execute garage-tcg-2 --remote --file=backups/garage-tcg_AAAA-MM-DD_HHMM.sql
```

Luego, en `wrangler.toml`, cambia `database_name` por `garage-tcg-2` y
`database_id` por el que mostró `create`, y `npm run deploy`. (Los scripts
`db:*` y `backup` usan el nombre `garage-tcg`: cámbialo también en
`package.json` y `scripts/backup.mjs`.)

### Después de restaurar

- Los teléfonos de jugadores y jueces **bajan todo de nuevo solos** (el
  servidor detecta que la base volvió atrás).
- Los teléfonos de los organizadores aún tienen lo que se perdió en el
  servidor: en cada uno, **Ajustes → (sincronización) → Volver a subir todo**.
  Así el servidor recupera lo que esos teléfonos tenían.
