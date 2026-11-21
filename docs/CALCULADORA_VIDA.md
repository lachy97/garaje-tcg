# Calculadora de vida (LP) · estudio y diseño

Estudio de noviembre de 2026. Se revisaron las apps de LP de Yu-Gi-Oh! más usadas y dos contadores de Magic que marcan el estándar de usabilidad. De cada una se toma lo mejor para la calculadora de Garage TCG.

## 1. Qué hace cada app (lo destacable)

| App | Lo mejor | Lo que falla |
|---|---|---|
| **Yu-Gi-Oh! Neuron** (Konami, oficial) | Calculadora, registro del duelo (log), temporizador, moneda y dado en una sola app | Básica: el log no se puede editar y no conecta con torneos |
| **Duel Calculator PegaSystem** | Pantalla espejada (cada jugador desde su lado, sin mover el teléfono); calculadora que suma varias cantidades y aplica el total con un botón; botones rápidos; deshacer (mantener para limpiar); nombres y contador de victorias; aviso flotante con el cambio (−1000) | En móviles grandes, los botones de la mitad de arriba quedan lejos |
| **DuelTool** | Botón **½** (Solemn Judgment, Shrink…); botón **VS** para el daño de batalla (ATK − ATK); botones rápidos configurables | Sin historial; un fallo conocido al reiniciar |
| **Duel Adviser** | Anillo de progreso alrededor de los LP; operaciones + − × ÷ ½ ×2; **nota opcional en cada cambio** ("ataque directo"); log con hora que incluye monedas y dados; **recupera el duelo si la app se cierra**; LP iniciales con hándicap; hasta 6 dados y 3 monedas animados | Interfaz cargada |
| **Quantum** | Deslizar arriba o abajo sobre los LP con paso de 1/10/100/500; pulsación larga para ×2 y ½; historial exportable; modo oscuro | Sin deshacer explícito |
| **Life Points Classic** | Animación de los LP bajando y sonidos del anime; varias monedas y dados a la vez; modo horizontal | Animaciones que terminan antes que el número; dados que se salen de la pantalla |
| **DeckTin** (YGOPRODECK) | Pantalla partida; deshacer y **rehacer**; historial por jugador | Muy simple |
| **Duel Connect** | Escanear el QR del rival para empezar; resultados guardados con gráficas; teclado, botones o gestos para introducir LP | Necesita conexión y cuenta |
| **Lifetap** (Magic, referencia de usabilidad) | **El estado se guarda: un cierre o reinicio no pierde la partida**; registro turno a turno; cronómetro con pausa y deshacer; opción de quitar animaciones; modo negro OLED | Pensada para 4–6 jugadores |

## 2. Lo que nos quedamos (requisitos)

**Entrada de LP (lo más usado: rápida y sin errores)**
1. Un **teclado numérico por jugador** con − y + (el gesto principal): escribir 1800 y pulsar −. Se pueden sumar varias cantidades antes de aplicarlas, como en PegaSystem: 1800 + 500 → −2300.
2. **Botones rápidos**: −100, −500, −1000 y ±50 con pulsación larga, configurables (DuelTool).
3. **½** (Solemn, Shrink), **×2** y **VS** de batalla: se escribe el ATK propio y el rival, y la diferencia va al LP que toca (DuelTool + Duel Adviser).
4. Opcional, en Ajustes: deslizar sobre los LP para ±100 (Quantum). Desactivado por defecto, porque con nervios provoca cambios sin querer (queja en Lifetap).

**Pantalla**
5. **Espejada para una mesa**: cada jugador ve su mitad derecha frente a él, con la del rival girada 180° (PegaSystem). Cada uno toca solo su mitad. También hay vista "un solo lado" para quien la use solo en su teléfono.
6. **LP grandes con barra o anillo** de 8000 a 0 (Duel Adviser) y un **aviso flotante del cambio** (−1800 en rojo, +500 en verde) que se desvanece (PegaSystem).
7. **Animación del contador** que baja número a número y termina a la vez que el número (sin el fallo de Classic), con la opción de quitarla (Lifetap).
8. **Pantalla siempre encendida** mientras la calculadora está abierta. Sonido corto opcional (apagado por defecto en torneo).
9. A **0 LP**: el duelo se marca terminado y propone pasar al siguiente.

**Historial y correcciones**
10. **Registro del duelo**: cada cambio con hora, jugador, de cuánto a cuánto y nota opcional ("ataque directo", "Solemn"). Las monedas y dados también salen en el registro (Duel Adviser).
11. **Deshacer y rehacer** ilimitados (DeckTin). Deshacer está siempre a la vista; tocar una línea del registro permite volver a ese punto.
12. ~~Nada se pierde (guardar el estado en el teléfono)~~: descartado por Lachy el 17/11. La partida solo vive mientras la app está abierta.

**Partida (Bo3) y torneo: lo que no tiene ninguna app**
13. **Contador de duelos de la partida** (1, 2, 3) con quién ganó cada uno, y botón "Siguiente duelo" que vuelve a 8000.
14. **Unida a Mi mesa**: en un torneo en juego, la calculadora se abre ya con el nombre del rival, la mesa y el **tiempo de la ronda** (el mismo reloj del organizador, con la pausa y el tiempo extra del juez).
15. Al terminar la partida, **"Reportar 2-1"** con el marcador ya rellenado desde los duelos ganados. Va al flujo de reporte que ya existe, y el rival confirma.
16. **Fin del tiempo**: aviso y contador de turnos extra, configurable porque el procedimiento lo decide el organizador. No pone resultados por su cuenta.
17. **Moneda y dado** animados (1–3 monedas, 1–6 dados, que no se salen de la pantalla), quedan en el registro. "¿Quién empieza?" con moneda al iniciar la partida.
18. También funciona **fuera de un torneo** (duelo libre, desde Torneos o Ajustes), sin cuenta, sin internet y en la versión web.

**Lo que descartamos (y por qué)**
- **Sincronizar dos teléfonos en tiempo real** (Duel Connect, Duel Adviser): necesita internet estable y gastaría lecturas del servidor (el límite de D1). En Cuba no es fiable. Basta un teléfono en el centro de la mesa.
- **Más de 2 jugadores**: Yu-Gi-Oh! es 1 contra 1.
- **Skins del anime y sonidos con derechos**: problemas de licencia. Se usa el estilo neón de la app.
- **Subir cada cambio de LP al servidor**: no aporta nada al torneo y gastaría escrituras. Solo viaja el resultado final, con el reporte de siempre.

## 3. Diseño propuesto

```
┌──────────────────────────────┐
│ (girado 180°)  RIVAL · 4200  │  ← mitad del rival
│  [−100][−500][−1000] [½][⌨]  │
│ ▓▓▓▓▓▓▓▓░░░░░░░░             │
├─ Mesa 3 · R2 · 32:15 · G1 1-0 ┤  ← barra central: ronda, tiempo, duelo
│  ↶ Deshacer  🪙  🎲  📜  ⋯    │
├──────────────────────────────┤
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓░░░             │
│        TÚ · 6500   (−1800)   │  ← mi mitad
│  [−100][−500][−1000] [½][⌨]  │
└──────────────────────────────┘
```
- **⌨** abre el teclado de ese jugador: dígitos, 00, 000, +, −, = y VS. El teclado sale en su mitad y con su orientación.
- **📜** abre el registro (con deshacer a un punto) y **⋯** el resto: reiniciar, LP iniciales, sonido, animación y vista espejada o un lado.

**Técnica**
- Sin cambios en el servidor ni en la base sincronizada. El estado vive en el teléfono (SharedPreferences, JSON por partida). El registro solo se queda en el teléfono.
- El reloj de la ronda y la mesa salen de `myTablesProvider` (Mi mesa); el reporte usa `PlayApi.report` como ahora.
- `wakelock_plus` para mantener la pantalla encendida (con su equivalente en la web) y `HapticFeedback` al aplicar un cambio.
- Lógica pura y con tests: aplicar operaciones, ½ (redondea hacia arriba, como pide la regla), deshacer y rehacer, siguiente duelo y marcador de la partida.

## 4. Decisiones de Lachy (16/11) e implementación de la fase 1
- **Teclado**: lo escrito se autocompleta con "00" mientras no pase de 4 cifras: "5" → 500, "18" → 1800. Con 3 cifras o más va tal cual: "150" → 150, "1800" → 1800, "050" → 50. El "00" se ve en gris mientras se escribe (`typedAmount`, `typedPreview`).
- **Vista** (Más → "Ver en horizontal / en espejo"; se recuerda en el teléfono):
  - **Espejo**: vertical, con el teléfono en el centro de la mesa y la mitad de arriba girada para el rival.
  - **Horizontal**: los dos lados de pie, uno junto al otro.
- **No se guardan las partidas** (17/11): la partida solo vive en memoria mientras la app está abierta. Más → **Reiniciar la calculadora** vuelve todo a 0.
- **±50**: botones rápidos −50 / −100 / −500 / −1000 y ½. El botón **−/+** de la izquierda los cambia a sumar (vuelven a restar después de cada suma). Mantener pulsado hace lo contrario.
- **Tiempo de partida (reloj de ajedrez)**: cada jugador tiene su reloj y solo corre el del que está jugando su turno.
  - El botón **Turno** (o tocar el propio reloj) para uno y arranca el otro. Pausa en la barra central.
  - Al empezar cada duelo se toca el reloj del que empieza.
  - Se guarda el tiempo de cada uno **por duelo y en total**; se ve en "Resumen de la partida".
- Archivos: `lib/features/duel/domain/duel.dart` (lógica pura, con tests en `test/duel_test.dart`), `application/duel_controller.dart` (estado en memoria; solo la vista elegida se guarda: `duel.layout`) y `presentation/duel_page.dart`.
- Se abre desde **Mi mesa → Calculadora** (con el rival, la mesa, el tiempo de la ronda y "Reportar" al terminar) y desde el icono de **calculadora en Torneos** (duelo libre, con nombres editables).
- Al llegar a 0 se confirma el ganador del duelo (o se deshace).

## 4b. Rediseño del 20/11 (marcas de Lachy sobre la captura)
- **Sin barra central ni nombres**: se quitan el nombre, las estrellas y la barra de botones del centro. Los dos lados quedan separados por una línea.
- **LP más grandes** (se ajustan al ancho). Con el teclado abierto, los LP se encogen para dejar sitio.
- **Teclado** en 3 columnas: 1–9 en 3 filas, una cuarta fila con **moneda · 0 · dado**, y debajo Restar / Sumar.
- **Esquina de cada lado**: deshacer, **girar ese lado 180°** (cada lado por separado, en espejo y en horizontal) y opciones (⋮).
- **Opciones**:
  - **Reiniciar** (LP a 8000 y relojes a 0).
  - Pausar los relojes.
  - Gana el duelo / empate.
  - Registro y Resumen de tiempos.
  - Vista espejo u horizontal, nombres (duelo libre) y salir.
  - Arriba, el marcador y la ronda del torneo.
- **Dos relojes por jugador**:
  - El del **turno** vuelve a 0 en cada turno; fuera de su turno se ve 0:00; tras una pausa en su turno, sigue.
  - El **total** de la partida.
  - Tocar el reloj pasa el turno; mantenerlo pulsado lo pausa. Antes de cada duelo sale "Empiezo yo".
- **Borrar con los "00"**: con 1 o 2 cifras se añaden dos ceros ("30" → 3000). El primer borrar quita esos ceros ("30" → 30), no la cifra escrita. Al vaciarlo, la siguiente cantidad vuelve a llevar los ceros (`typedBackspace`).

## 4c. Correcciones del 20/11 (segunda tanda)
- **Moneda y dado animados (2 s)**:
  - La **moneda** sube, gira sobre sí misma cada vez más despacio, cae con un pequeño rebote y su sombra crece al bajar. Es una moneda dorada con CARA (estrella) y CRUZ (aspa).
  - El **dado** es un cubo 3D (perspectiva, caras con luz según hacia dónde miran, el 1 en rojo) que rueda y rebota frenando hasta dejar el resultado de frente.
  - El resultado se decide al azar al empezar y la animación termina exactamente en él (`diceRestAngles`, probado en `test/duel_visuals_test.dart`). Al parar, queda en el registro.
  - El diálogo sale orientado hacia el jugador que lo pidió.
- **Girar**: cada toque gira ese lado **90°** (vuelta completa en 4 toques). La pantalla queda en vertical; se quita la vista horizontal aparte.
- **Opciones (⋮)**: solo **Reiniciar**, **Registro de la partida** y **Salir**, más el selector de tema arriba. Se quitan "gana el duelo", empate, resumen y reporte (no se guarda nada); al llegar a 0 se paran los relojes.
- **Barra de vida** (igual en todos los temas, `lifeBarColor`):
  - Verde a 8000; al bajar pasa a naranja y a rojo, y cerca de 0 a un rojo intenso.
  - Por encima de 8000 se vuelve azul, más intenso cuanto más se aleja (máximo a 16000).
- **5 temas** (se recuerdan en el teléfono: `duel.theme`):
  - **Neón**: el verde de la app.
  - **Hielo**: azul.
  - **Faraón**: oro.
  - **Abismo**: morado.
  - **Papel**: claro.

## 5. Fases
1. **MVP (lo del torneo)**: pantalla espejada, teclado + botones rápidos + ½, aviso del cambio, deshacer y rehacer, registro, estado que no se pierde, moneda y dado, pantalla encendida, partida Bo3 y "Reportar" desde Mi mesa con el tiempo de la ronda.
2. **Mejoras**: VS de batalla, notas en el registro, deslizar para ±100, sonidos, animación configurable, turnos extra al acabar el tiempo y compartir el registro (texto).
3. **Más adelante**: estadísticas propias (duelos ganados yendo primero o segundo, LP medio al ganar) con el registro guardado.

## Fuentes
- [Yu-Gi-Oh! NEURON (Konami)](https://www.yugioh-card.com/en/products/neuron/) · [Yu-Gi-Oh! Neuron (YGOrganization)](https://svelte.ygorganization.com/yugiohneuronapp)
- [Duel Calculator PegaSystem](https://apps.apple.com/us/app/id864394943) · [DuelTool](https://apps.apple.com/ru/app/dueltool/id836442259?l=en-GB) · [Duel Adviser](https://apps.apple.com/app/duel-adviser/id1523375153)
- [Quantum – LP Counter](https://apps.apple.com/us/app/id1507624563) · [Life Points Classic](https://apps.apple.com/us/app/id1302349210) · [YGO Life Points Counter](https://apps.apple.com/us/app/id6751197781)
- [DeckTin duel calculator (YGOPRODECK)](https://ygoprodeck.com/duel-calculator-added-to-decktin/) · [Duel Connect](https://apps.apple.com/md/app/duel-connect/id1668095322) · [Lifetap](https://apps.apple.com/us/app/id1508241754)
