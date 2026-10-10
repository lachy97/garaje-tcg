# Decisiones de diseño — Garage TCG

- Nombre de la app: **Garage TCG**; en el lanzador de Android/iOS aparece **GARAGE TCG**. El identificador interno del paquete sigue siendo `garaje_tcg` para que las actualizaciones se instalen encima de la versión anterior.

## Plataforma y datos
- Flutter + Riverpod + **Drift (SQLite)**. Isar/Hive descartados por estar casi abandonados; los datos son relacionales y las estadísticas son agregaciones SQL.
- 100 % local, sin servidor. Preparado para sincronización futura: IDs UUID v7, `createdAt/updatedAt`, borrado lógico `deletedAt`.
- **Los matches son la única fuente de verdad.** Las estadísticas de jugador, mazo y ranking se calculan por consulta. Al cerrar temporada se congelan en `ranking_snapshots` y `deck_snapshots`.
- Cada match guarda el mazo de cada lado, así las estadísticas de un mazo no dependen del jugador.
- Solo **Yu-Gi-Oh!** por ahora (campo `game = 'ygo'` listo para otros juegos).

## Diseño visual
- App siempre en modo oscuro: fondo negro `#000000`, acento verde neón `#8CF04C` (puerta del logo), verdes medios `#5FB86A` / `#3E7A4E` para bordes y marcos, texto verde claro `#C9F7B4` y secundario `#7FA886`.
- Brillos ("glow") verdes en títulos, logo y tarjetas destacadas. Derrota en rojo suave `#FF5C5C` y empate en ámbar `#E6C84F` para que los resultados se distingan.
- Icono y pantalla de carga: logo sobre negro.
- Fuente única **Inter** (OFL) empaquetada en `assets/fonts`, recortada a caracteres latinos (~70 KB por peso): se ve igual en cualquier teléfono.
- Toda eliminación pide confirmación (jugador, torneo, inscripción, fusión de mazos, resultado de un match, drop).

## Perfil de jugador
- Datos personales: nickname, nombre, Konami/COSSY ID, teléfono, notas (BD v3 añade `konami_id` y `phone`).
- Todo lo demás se calcula desde los matches: historial (torneo, fase, rival, mazos, marcador visto desde el jugador, V/D/E), mazos usados (torneos con ese mazo, PJ, V/D/E, WR%, última vez) y totales (títulos = 1º en torneos terminados). El BYE aparece en el historial pero no cuenta como partida.

## Torneo
- **Matches al mejor de 3** (gana quien llega a 2 juegos). Marcador `J1 - Empates - J2`, solo se aceptan: 2-0-0, 2-0-1, 0-0-2, 1-0-2 y 1-1-1 (empate del match). En Top Cut no se acepta 1-1-1. El BYE se registra 2-0-0. Se guardan los juegos (columnas `games1`, `gamesDraw`, `games2`) y el resultado del match se deriva del marcador.
- Rondas Swiss (1-15) y Top Cut (Sin Top / 4 / 8 / 16 / 32) se eligen al crear el torneo y se pueden ajustar solo durante la inscripción. **Al generar la ronda 1 quedan fijos.** La app solo muestra una sugerencia orientativa; nunca cambia la configuración por su cuenta. Al empezar se comprueba que haya jugadores suficientes para el Top elegido.
- Swiss: V=3, E=1, D=0. El BYE cuenta como victoria. Desempates: OMW% (piso 33 %) → OOMW% → GW% (% de juegos ganados propio, piso 33 %; el BYE cuenta 2-0).
- Rondas sugeridas (valor por defecto): ceil(log2 N), mínimo 3.
- Top Cut según asistencia: **menos de 15 jugadores → Top 4** (mínimo 6 jugadores); 15+ → Top 8; 24+ → Top 16; 48+ → Top 32. Se siembra 1 vs N según el Swiss (el 1 y el 2 solo se cruzan en la final). Los jugadores retirados no entran al Top.
- Pairings: ronda 1 aleatoria; después por puntos, con orden aleatorio dentro de cada grupo de puntos. Backtracking sin repetir rivales; solo se repite rival si es imposible evitarlo. El BYE va al jugador con menos puntos que aún no haya tenido BYE.
- En el Top Cut no hay empates: cada match necesita un ganador.
- **Doble derrota** (solo Swiss): si se acaba el tiempo y el match no terminó, el organizador marca la casilla "Doble derrota" y queda 0-0-0 con derrota para los dos (0 puntos, cuenta como partida jugada y como rival enfrentado). No es automática. Se guarda como `result = doubleLoss`.
- **Tiempo por ronda**: 45 min por defecto, configurable de 5 a 120 (de 5 en 5) al crear el torneo o durante la inscripción; al generar la ronda 1 queda fijo (BD v4: `tournaments.round_minutes`). En la ronda actual se inicia el reloj a mano ("Iniciar tiempo"), se puede reiniciar o detener; se guarda la hora de inicio (`rounds.timer_started_at`), así sigue bien aunque se cierre la app. Al llegar a 0 avisa (vibración, sonido y mensaje) y muestra el tiempo extra; nunca pone resultados.
- **3º/4º se decide con una partida por el 3er puesto.**
- Posiciones 5-8, 9-16, … se ordenan por standing Swiss dentro de su tramo.

## Ranking trimestral
- Temporada = trimestre natural.
- Escala escalonada +100 por nivel (editable en la BD, tabla `points_scale_entries`):
  - Top 4: 400 / 300 / 200 / 100
  - Top 8: 500 / 400 / 300 / 200 / 5-8: 100
  - Top 16: 600 / 500 / 400 / 300 / 5-8: 200 / 9-16: 100
  - Top 32: 700 / 600 / 500 / 400 / 5-8: 300 / 9-16: 200 / 17-32: 100
- **Fuera del Top Cut: 0 puntos.**
- Desempates: puntos, mejor posición, winrate, menos torneos.
- Tabla con: #, jugador, puntos, último mazo, PJ, V, D, E, WR%, torneos y mejor posición. Solo cuentan torneos terminados; PJ excluye BYE.
- Se puede consultar cualquier temporada (selector en el título), no solo la actual.
- **Exportación** (ranking y tier list): una sola imagen PNG compartida como foto, ajustada al máximo de WhatsApp HD (≈3900 px por el lado largo; hay que tocar "HD" en WhatsApp). El **ranking** sale con la tabla completa en una sola columna, de arriba abajo (sin repartir en columnas); si es muy larga la imagen pasa de 3900 px (mínimo 1,5× de densidad, tope 8000 px por límite de la GPU). La **tier list** se exporta como un póster parecido a las tier lists de referencia: fondo oscuro con textura, título grande "»»» TIER LIST" con la marca y la temporada, y un tablero redondeado con una fila por tier (etiqueta de color a la izquierda, imágenes cuadradas de los mazos con su nombre a la derecha, 10 por línea, por puesto), sin la tabla. (Se probó enviarla como documento, pero no se veía bien en el teléfono del que la recibe.)
## Puntuación de mazos (tier list)
Konami no publica fórmula de tier list (sus "Deck Breakdown" de YCS solo cuentan mazos por fase); se usa el criterio de la comunidad (Master Duel Meta / Duel Links Meta: Power = tops recientes) adaptado a nuestros torneos:
- **Power** = Σ puntos de cada piloto en el Top: Campeón 8 · Finalista 6 · 3º-4º 4 · Top 8 2 · Top 16 (o Top 32) 1 · fuera del Top 0. En torneos sin Top Cut cuentan como Top los 4 primeros.
- **Presencia** = inscripciones con el mazo ÷ inscripciones (con mazo) de la temporada.
- **Conversión** = entradas al Top ÷ inscripciones con el mazo.
- **Tier** relativo al mejor Power de la temporada: S ≥ 70 %, A ≥ 40 %, B ≥ 15 %, C el resto (> 0); **Rogue/Local** = Power 0 (sin Top).
- Orden y desempates: Power → Conversión → Presencia → nombre.
- Pestaña **Mazos** = tabla de la temporada: #, tier, mazo, Power, Presencia, Conversión, uso, jugadores distintos, entradas al Top, títulos, mejor posición, PJ, V, D, E, WR% y V en Top (informativas). Solo torneos terminados; la doble derrota cuenta como derrota para ambos mazos.
- (Hasta oct-2026 se usaba Score = PP × (0.5 + WRp); se cambió a petición de Lachy por el criterio de tops.)
- Se muestra la tier list (filas S/A/B/C/Rogue) y la tabla; al exportar solo sale la tier list en imagen (ver Exportación). El **texto y el color** de la etiqueta de cada tier se editan tocándola en la pantalla de Mazos (paleta o código de color); se guardan en el teléfono (SharedPreferences) y se usan en pantalla, en la tabla y en la imagen. Por defecto: S rojo, A naranja, B amarillo, C verde, Rogue/Local morado (tonos apagados).
- **Catálogo de mazos**: 160 mazos: los 55 de https://edisonformat.net/decks (competitivos, rogue y casual) y 96 más de https://formatlibrary.com/deck-gallery/edison (categoría "Más mazos"), más **Jinzo OTK** y los mazos del Torneo #1 · T4 2026 añadidos a mano. Alias que se fusionan solos al abrir: "Hybrid" → Hybrid Blackwing, "Dark Jinzo OTK" → Jinzo OTK. En "Gestionar mazos" hay buscador. Imágenes **circulares**: el arte de la carta más representativa de cada mazo; los mazos que combinan dos arquetipos llevan media imagen de cada uno. Los de Edison que no están en Format Library usan el frente de su caja. Todos vienen dentro de la app con su imagen (`assets/decks/*.webp`, `deck_catalog.dart`) y se cargan en la BD al abrir (BD v5: `decks.image_path`). Al asignar mazo se abre una cuadrícula con imágenes, búsqueda y filtro por categoría; un mazo que no esté se añade con nombre y foto opcional de la galería. En la tier list aparece la imagen cuadrada de cada mazo con su nombre encima, ordenada por puesto. Las fotos propias no viajan en la copia de seguridad.
- Crear, renombrar y fusionar mazos pasa a "Gestionar mazos" (botón en la barra de Mazos).

## Licencias (offline)
- Ver `docs/LICENCIAS.md`. Firma Ed25519: la app lleva la clave pública (`lib/core/license/license_config.dart`); el administrador firma con la privada desde el **Modo administrador** del móvil (7 toques en la versión, en Ajustes) o con `tools/generador_licencias.html` en el PC.
- Licencia ligada al código del teléfono (hash de ANDROID_ID) con vencimiento por meses (1 mes en adelante). Aviso diario 7 días antes. Al vencer, pantalla de bloqueo con el código, introducir licencia y exportar datos.
- Protección contra atrasar la fecha (última fecha vista, tolerancia 36 h).
- Sin clave pública configurada la app no pide licencia (modo desarrollo).
- Sin servidor no hay desactivación remota: el control es la duración de la licencia.

## Copias de seguridad
- Exportar/importar toda la BD en un archivo `.gtcg`: cabecera + SQLite (VACUUM INTO) comprimido + sello HMAC-SHA256 con clave interna. Solo se aceptan archivos exportados por la app (de cualquier teléfono); se detectan archivos dañados.
- Importar reemplaza todos los datos, previa confirmación. Antes se guarda una copia automática (las 5 últimas) para poder deshacer. Una copia de una versión anterior de la BD se actualiza sola; una de una versión más nueva se rechaza.
- La licencia NO va en la copia (está fuera de la BD).

## Pendiente de confirmar
- Torneos de menos de 6 jugadores: no tienen Top Cut, así que no dan puntos de ranking.

## Bloqueo de capturas de pantalla
- Android `FLAG_SECURE` en toda la app: no se pueden hacer capturas ni grabar la pantalla (sale en negro, también en "apps recientes"). Exportar ranking/tier list sigue funcionando (la imagen la genera la app).
- Activo por defecto. Solo se desactiva desde **Modo administrador → Seguridad**, con la clave desbloqueada con el PIN; vale para ese teléfono (preferencia `screen_protection_off`, la lee MainActivity al arrancar). No evita fotos con otra cámara.

## Modo administrador solo en el teléfono del organizador
- Solo aparece (Ajustes → Administrador) y solo se puede abrir en los teléfonos de `lib/core/license/admin_devices.dart` (código de teléfono de Ajustes → Licencia; hoy solo el de Lachy, QT4Q-G5NW-BHMW-BJY4). Se quitó el desbloqueo tocando 7 veces la versión.
- Si el administrador cambia de teléfono o lo restablece de fábrica, hay que añadir el código nuevo y compilar. Con ello, el interruptor de capturas también queda solo en su teléfono.
