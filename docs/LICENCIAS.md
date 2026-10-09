# Licencias de Garage TCG — cómo funcionan y cómo usarlas

## La idea en 30 segundos

- Tú tienes una **clave privada** (solo tú). La app lleva dentro la **clave pública**.
- Cada teléfono muestra un **código de dispositivo** (ej. `7K3M-Q2PX-…`).
- Con tu clave privada creas una **licencia** para ese código y una fecha de
  vencimiento (1 mes o más). Es un texto que empieza por `GTCG1.`.
- El cliente la pega en la app. La app comprueba, **sin internet**, que la
  firmaste tú, que es para ese teléfono y que no ha vencido.
- Al vencer, la app se bloquea hasta que pegue una renovación. Así controlas
  quién la usa: si no renuevas, deja de funcionar.

Nadie puede fabricar licencias sin tu clave privada, y una licencia no sirve en
otro teléfono (el código sale del identificador del teléfono; solo cambia con un
restablecimiento de fábrica).

## Paso 1 · Crear tus claves (una sola vez)

En TU teléfono, con la versión actual de la app (todavía sin licencias):

1. Ajustes (engranaje arriba a la derecha en Torneos) → toca **7 veces** la
   tarjeta "Garage TCG · Versión" → aparece **Modo administrador**.
2. Modo administrador → **Crear claves nuevas** → elige un **PIN** (4 a 8 números).
   La clave privada queda cifrada con ese PIN: sin él nadie puede generar
   licencias desde tu teléfono. Tras 5 PIN incorrectos se bloquea 15 minutos.
   Si olvidas el PIN: "Importar clave privada" con tu respaldo y eliges otro PIN.
3. **Copiar privada (respaldo)** y guárdala en 2 lugares seguros (una nota
   privada, un papel, una memoria USB). **Si la pierdes no podrás crear más
   licencias** para esta app. No se la envíes a nadie.
4. **Copiar pública** y envíatela al PC.

(Alternativa en el PC: abre `tools/generador_licencias.html` en el navegador →
"Crear claves nuevas". Luego importa la misma clave privada en el móvil con
"Importar clave privada" para poder generar licencias desde los dos.)

## Paso 2 · Poner la clave pública en la app

1. Abre `lib/core/license/license_config.dart` y pega la clave pública:
   ```dart
   const kLicensePublicKey = 'ebVWLo_mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ';
   ```
   (esa es de ejemplo; usa la tuya). La pública **no es secreta**, se puede subir a GitHub.
2. `git add` / `commit` / `push` → GitHub Actions compila la APK nueva.

**Antes de repartir esa APK**, genera tu propia licencia (paso 3, "Usar este
teléfono" → "Activar aquí") para que tu teléfono no se bloquee. Si se bloquea
igual: en la pantalla de bloqueo toca **7 veces el logo** → Modo administrador.

## Paso 3 · Dar una licencia a un cliente

1. El cliente instala la APK. Le aparece la pantalla de bloqueo con su
   **código** y un botón para enviártelo por WhatsApp.
2. Tú: Modo administrador → **Generar licencia**: pega el código, escribe el
   nombre del cliente y elige la duración (1, 2, 3, 6, 12, 24 meses u otra).
3. **Enviar** → le llega por WhatsApp un mensaje con la licencia.
4. El cliente copia el mensaje → **Introducir licencia** → **Pegar** →
   **Activar**. (Se puede pegar el mensaje completo; la app extrae la licencia.)

Desde el PC es igual con `tools/generador_licencias.html` (funciona sin
internet; ábrelo con Chrome, Edge o Firefox).

## Renovar

Igual que el paso 3: nueva licencia para el mismo código. El cliente la pega en
Ajustes → Licencia → "Introducir licencia nueva / renovación". 7 días antes
del vencimiento la app avisa una vez al día.

## Qué pasa si…

| Situación | Resultado |
|---|---|
| No renuevas | Al día siguiente del vencimiento la app se bloquea. Los datos no se borran y desde la pantalla de bloqueo se pueden exportar. |
| Copian la APK a otro teléfono | Ese teléfono tiene otro código: necesita su propia licencia. |
| Pasan la licencia a otro | No sirve: es para un solo código. |
| Atrasan la fecha del teléfono | La app guarda la última fecha vista; si la fecha va hacia atrás más de 36 h se bloquea hasta corregirla. |
| Restablecen el teléfono de fábrica | Cambia el código: necesita licencia nueva (y importar su copia de datos). |
| Se adelantó la fecha por error y luego se corrigió | Se bloquea por "fecha atrasada"; una licencia recién emitida (de hoy) lo desbloquea. |
| Pierdes la clave privada | No puedes crear licencias para esa app. Tendrías que crear claves nuevas, cambiar la pública en el código y dar licencias nuevas a todos. |

## Límites (sin servidor)

- No se puede **desactivar a distancia** una licencia ya entregada: el control es
  la duración. Por eso conviene dar licencias cortas (1–3 meses) a clientes nuevos.
- Una persona con conocimientos avanzados podría modificar la APK; esto pone
  la barrera alta para el uso normal. Con un servidor (más adelante) se podrá
  añadir verificación online y desactivación remota.
- Mientras `kLicensePublicKey` esté vacía, la app funciona sin licencia (modo desarrollo).

## Protección extra

- **PIN del Modo administrador**: la clave privada se guarda cifrada (AES-256-GCM
  con clave derivada del PIN por PBKDF2). Si la creaste en una versión anterior
  sin PIN, al entrar al Modo administrador te pedirá crear uno.
- **Ofuscación**: el build de GitHub compila con `--obfuscate`, así es mucho más
  difícil descompilar la app para saltarse las licencias.

## Detalles técnicos

- Firma **Ed25519** (paquete `cryptography`); formato en `lib/core/license/license_codec.dart`.
- Código de dispositivo = SHA-256 de `ANDROID_ID` (canal `garage_tcg/device` en
  `MainActivity.kt`), 10 bytes en Base32 Crockford.
- El generador de PC (`tools/license_core.js`) y la app firman exactamente igual
  (test `test/license_codec_test.dart` con un vector del generador).
