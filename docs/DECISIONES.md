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
- **Catálogo de mazos**: 163 mazos: los 55 de https://edisonformat.net/decks (competitivos, rogue y casual) y 96 más de https://formatlibrary.com/deck-gallery/edison (categoría "Más mazos"), más **Jinzo OTK** y los mazos de los Torneos #1 y #2 · T4 2026 añadidos a mano. Alias que se fusionan solos al abrir: "Hybrid" → Hybrid Blackwing, "Dark Jinzo OTK" → Jinzo OTK. En "Gestionar mazos" hay buscador. Imágenes **circulares**: el arte de la carta más representativa de cada mazo; los mazos que combinan dos arquetipos llevan media imagen de cada uno. Los de Edison que no están en Format Library usan el frente de su caja. Todos vienen dentro de la app con su imagen (`assets/decks/*.webp`, `deck_catalog.dart`) y se cargan en la BD al abrir (BD v5: `decks.image_path`). Al asignar mazo se abre una cuadrícula con imágenes, búsqueda y filtro por categoría; un mazo que no esté se añade con nombre y foto opcional de la galería. En la tier list aparece la imagen cuadrada de cada mazo con su nombre encima, ordenada por puesto. Las fotos propias no viajan en la copia de seguridad.
- Crear, renombrar y fusionar mazos pasa a "Gestionar mazos" (botón en la barra de Mazos).

## Licencias (offline)
- Ver `docs/LICENCIAS.md`. Firma Ed25519: la app lleva la clave pública (`lib/core/license/license_config.dart`); el administrador firma con la privada desde el **Modo administrador** del móvil (7 toques en la versión, en Ajustes) o con `tools/generador_licencias.html` en el PC.
- Licencia ligada al código del teléfono (hash de ANDROID_ID) con vencimiento por meses (1 mes en adelante). Aviso diario 7 días antes. Al vencer, pantalla de bloqueo con el código, introducir licencia y exportar datos.
- Protección contra atrasar la fecha (última fecha vista, tolerancia 36 h).
- Sin clave pública configurada la app no pide licencia (modo desarrollo).
- Sin servidor no hay desactivación remota: el control es la duración de la licencia.

## Copias de seguridad
- Exportar/importar toda la BD en un archivo `.gtcg` (importar = **integrar**, ver abajo): cabecera + SQLite (VACUUM INTO) comprimido + sello HMAC-SHA256 con clave interna. Solo se aceptan archivos exportados por la app (de cualquier teléfono); se detectan archivos dañados.
- Importar INTEGRA los datos (ver "Importar = integrar"). Antes se guarda una copia automática (las 5 últimas) para poder deshacer. Una copia de una versión anterior de la BD se actualiza sola; una de una versión más nueva se rechaza.
- La licencia NO va en la copia (está fuera de la BD).

## Pendiente de confirmar
- Torneos de menos de 6 jugadores: no tienen Top Cut, así que no dan puntos de ranking.

## Bloqueo de capturas de pantalla
- Android `FLAG_SECURE` en toda la app: no se pueden hacer capturas ni grabar la pantalla (sale en negro, también en "apps recientes"). Exportar ranking/tier list sigue funcionando (la imagen la genera la app).
- Activo por defecto. Solo se desactiva desde **Modo administrador → Seguridad**, con la clave desbloqueada con el PIN; vale para ese teléfono (preferencia `screen_protection_off`, la lee MainActivity al arrancar). No evita fotos con otra cámara.

## Modo administrador solo en el teléfono del organizador
- Solo aparece (Ajustes → Administrador) y solo se puede abrir en los teléfonos de `lib/core/license/admin_devices.dart` (código de teléfono de Ajustes → Licencia; hoy solo el de Lachy, QT4Q-G5NW-BHMW-BJY4). Se quitó el desbloqueo tocando 7 veces la versión.
- Si el administrador cambia de teléfono o lo restablece de fábrica, hay que añadir el código nuevo y compilar. Con ello, el interruptor de capturas también queda solo en su teléfono.

## Importar = integrar (no reemplazar)
- Importar un `.gtcg` ya no borra los datos del teléfono (`backup_merge.dart`): la copia se migra al esquema actual, se adjunta (`ATTACH`) y se integra en una transacción.
- **Torneos**: el de la copia reemplaza al del teléfono con el mismo nombre (sin distinguir mayúsculas/espacios) o el mismo id, con rondas, partidas, inscripciones y puntos; los demás se añaden; los que solo están en el teléfono se quedan. Los torneos borrados en la copia se ignoran.
- **Jugadores** por id o apodo (se completan datos vacíos), **mazos** por id o nombre, **temporadas** por año y trimestre. La escala de puntos y los ajustes del teléfono no se tocan. Las fotos de otro teléfono no viajan.
- Antes se guarda una copia automática. "Deshacer una importación" sí REEMPLAZA todo por la copia automática elegida.

## Mejoras Fase 1 (análisis de octubre 2026)
- **Top Cut con drops**: si al terminar el Swiss quedan menos jugadores activos que el Top elegido, el cuadro se reduce al mayor que se pueda llenar (Top 8 con 7 activos → Top 4; con 3 → final directa; con 1 → sin Top) y se guarda ese tamaño en el torneo. El botón de avanzar avisa antes. La línea de corte de la clasificación cuenta solo jugadores activos.
- **Resultado de un toque**: botones 2-0 · 2-1 · Empate · 1-2 · 0-2 (leídos desde el jugador de la izquierda) y, en Swiss, ID y Doble derrota. Cada toque guarda al instante, sin aviso (se quitó el "Deshacer": el aviso tapaba la pantalla demasiado tiempo). Para corregir: tocar otro botón o "Borrar resultado".
- **ID (empate intencional)**: se guarda como empate 0-0-0: 1 punto cada uno y no cuenta juegos (no altera el GW%). Solo en Swiss.
- **Compartir**: "Compartir ronda" (pestaña Rondas) y "Compartir" (Clasificación), como texto para WhatsApp (ganador en negrita) o como imagen.
- **Licencia**: no se puede activar con la fecha anterior a la emisión. Volver a pegar la misma licencia (o una más vieja) ya no quita el bloqueo de fecha atrasada; solo una licencia nueva y recién emitida lo quita. La última fecha vista nunca retrocede. Limitación: borrar los datos de la app borra también esa fecha (sin servidor no se puede evitar del todo).
- **Firma**: en el servidor de compilación (CI=true) la compilación falla si faltan los secretos de firma, en vez de firmar con la clave de debug (cambiaría el código de todos los teléfonos y las licencias dejarían de valer). En la PC sigue el respaldo con la clave de debug.
- **Copia de Android desactivada** (`allowBackup=false` y reglas de extracción): los datos y la licencia no viajan solos a la nube de Google ni a otro teléfono; las copias se hacen con `.gtcg`.

## Mejoras Fase 2
- **Corregir rondas cerradas**: mientras el torneo esté en el Swiss se pueden cambiar los resultados de rondas Swiss anteriores (la clasificación se recalcula; los cruces ya hechos no cambian). En una ronda cerrada no se puede dejar un resultado pendiente. Al iniciar el Top Cut el Swiss queda fijo. Con el torneo terminado no se cambia nada.
- **Deshacer ronda** (botón al final de la ronda actual): borra cruces y resultados de la ronda actual y reabre la anterior. Desde la 1ª ronda del Top Cut vuelve al Swiss (se borran las posiciones Swiss guardadas); desde la ronda 1 vuelve a la inscripción. No se puede en un torneo terminado. Si el Top se había reducido por drops, queda el tamaño reducido.
- **Importar con vista previa**: antes de integrar se muestra cada torneo de la copia y qué se hará (Añadir / Reemplazar / No importar), editable:
  - Mismo torneo (mismo id) o mismo nombre y misma fecha → Reemplazar, salvo que el del teléfono tenga cambios más recientes (se mira la última modificación del torneo, sus rondas, partidas e inscripciones) → No importar, con aviso.
  - Mismo nombre y otra fecha → Añadir como otro torneo (se puede elegir reemplazar).
  - Borrado en este teléfono → No importar (se puede restaurar). Temporada cerrada en el teléfono → No se importa.
  - Jugadores y mazos borrados en la copia también se traen (si tienen partidas), sin reactivar nada borrado o fusionado en el teléfono. Una temporada nueva entra activa.
- **Cerrar temporada** (pantalla Ranking): exige que todos sus torneos estén terminados; guarda la foto del ranking de jugadores y de la tabla de mazos. El ranking de una temporada cerrada sale de la foto (no cambia aunque se renombre un jugador). Sus torneos quedan bloqueados (no se editan, borran ni se crean torneos en esas fechas). Se reabre desde **Modo administrador → Temporadas cerradas** (borra la foto). La **tier list** también: al cerrar se guarda su foto (Power, Presencia, Conversión, tier, pilotos, V/D/E) y en una temporada cerrada se muestra y exporta la foto, aunque después se renombre o fusione un mazo (la imagen sí es la actual del mazo). Al reabrir vuelve a calcularse en vivo.
- **Pruebas** con SQLite real (`backup_merge_test`, `tournament_flow_test`); si el equipo no tiene SQLite nativo se omiten sin fallar.

## Mejoras Fase 3
- **Código quitado** (no se usaba): exportación PDF (`pdf_export.dart`, paquete `pdf`, fuentes `assets/fonts/pdf/`, tablas PDF de ranking y tier list), el canal Android `garage_tcg/share` con `DocumentShareProvider` (y su `document_share_paths.xml`, el `provider` del manifiesto y `core-ktx`), `ExportFormat` y el recurso `logo_dark` del paquete de la app (el archivo se queda: lo usa la pantalla de carga).
- **PIN de administrador**: tras 5 fallos seguidos se bloquea 15 min, luego 30 min, 1 h, 2 h… hasta 24 h; se reinicia al acertar. **Importar clave privada** solo acepta la que corresponde a la clave pública de la app; si la app ya tiene clave pública no se pueden crear claves nuevas.
- **Botón de avanzar** con texto: "Generar ronda N", "Iniciar Top N", "Siguiente ronda del Top", "Finalizar torneo".
- **Versión** 0.2.0 (el número de compilación lo pone GitHub Actions). Fijar la versión de Flutter en el workflow queda a mano (la carpeta `.github` no se toca desde aquí).

## Mejoras Fase 4
- **Penalizaciones** (solo registro, esquema v6, tabla `penalties`): Aviso, Game loss, Match loss, Descalificación, con motivo opcional y la ronda. Se ponen desde el icono de mazo/martillo de cada jugador en la pestaña Jugadores del torneo (una vez empezado), se listan arriba de esa pestaña (se pueden quitar) y en la ficha del jugador. No cambian resultados: eso se hace a mano (resultado o Drop). Viajan en las copias.
- **Inscripción tardía** (columna `tournament_players.late_rounds`): durante el Swiss, mientras queden rondas por generar, "Inscribir tarde". Cada ronda ya generada cuenta como derrota 0-2 sin rival (0 puntos; no cuenta como rival para el OMW% de nadie). Entra a emparejarse en la siguiente ronda. Puede elegir mazo después. Al deshacer rondas se recortan sus rondas perdidas.
- **Cambiar cruces** (ronda Swiss actual): "Cambiar cruces" → tocar un jugador y otro de otra mesa para intercambiarlos (el mazo va con el jugador; también con el BYE). Solo mesas sin resultado. Avisa si se repite un cruce o alguien recibe un segundo BYE, pero lo permite.
- **Mazos → Enfrentamientos**: matriz mazo contra mazo de la temporada (los 12 primeros de la tier list con partidas; victorias-derrotas(-empates) del mazo de la fila, Swiss y Top, torneos terminados; espejos en la diagonal).
- **Ficha de mazo** (tocar un mazo en la tabla o en la matriz): Power, Presencia, Conversión, inscripciones, pilotos, tops, títulos, partidas; cada torneo con su piloto, puesto y Power aportado; y sus enfrentamientos. La ficha de jugador ya tenía mazos usados e historial; ahora también sus penalizaciones.
- **Borrado lógico**: al borrar un torneo, sus puntos de ranking se marcan como borrados (no se eliminan); al cerrar/reabrir temporada, la foto anterior también. Siguen eliminándose de verdad las rondas al "Deshacer ronda" (la ronda N se vuelve a crear con el mismo número) y lo que reemplaza una importación.
- **Rutas de imagen relativas**: las fotos propias de los mazos se guardan como `docs:deck_images/…` (relativas a la carpeta de la app); las rutas absolutas antiguas se convierten solas al abrir la app, y si una ruta antigua no existe se busca el archivo por su nombre.

## Listas de mazos · Paso 1 (base de cartas e imágenes)
- **Base de cartas** `assets/cards/edison_cards.json`: cartas legales en Edison según YGOPRODeck (`format=edison`), nombre en inglés, tipo, copias permitidas por la banlist (`ban_edison`; correcciones en `tools/cards/banlist_edison.txt`) y códigos de ilustraciones alternativas. La genera `tools/cards/build_card_db.py` con el workflow `tools/cards/cartas.yml` (hay que copiarlo a `.github/workflows/`), que la sube sola al repositorio. Hasta entonces la app trae una base vacía.
- **Imágenes**: el mismo workflow las baja una vez de YGOPRODeck (≈10 por segundo, sin enlazarlas directo) y las publica: Cloudflare Pages `garaje-tcg-cartas.pages.dev` (principal) o GitHub Pages `lachy97.github.io/garaje-tcg` (plan B, repo público). `s/{código}.jpg` carta pequeña, `a/{código}.jpg` ilustración recortada. La app prueba los servidores en orden, comprueba que la respuesta sea un JPEG y guarda cada imagen en el teléfono la primera vez.
- **Permiso INTERNET** en Android: solo para estas imágenes; el resto de la app sigue sin conexión.
- **Ajustes → Cartas**: cuántas cartas hay, "Probar descarga de imágenes" (tiempo de cada servidor, para probar desde Cuba) y borrar las imágenes guardadas.

## Inscripción: último mazo y cover
- Al inscribir (normal o tardía), cada jugador aparece con su **último mazo**: el de su inscripción en el torneo empezado más reciente por fecha (sin contar el actual, los torneos en inscripción ni los borrados; si en el último no tenía mazo, vale el anterior). Se cambia con el icono de mazo antes de inscribir, o tocando al jugador ya inscrito mientras el torneo esté en inscripción.
- **Cover pagado** (esquema v7, `tournament_players.paid`): casilla "Cover" en cada inscrito, se puede marcar en cualquier momento (no con la temporada cerrada). Arriba se cuenta cuántos faltan por pagar. Al generar la ronda 1 se avisa de los que no tienen mazo o no han pagado, pero no impide empezar. Reinscribir a alguien no borra su pago. Viaja en las copias .gtcg.
- Las listas de mazos usarán el esquema v8.

## Resumen del torneo (pestaña Resumen)
- Con el torneo **terminado** aparece la pestaña **Resumen**:
  - **Metagame**: dona con un sector por mazo (jugadores que lo usaron, % del total; los inscritos sin mazo cuentan como "Sin mazo") y la leyenda completa. Colores fijos por orden de uso (16 colores; desde el 17º, gris). Arriba, la línea "Metagame" con los 3 más jugados y "+N".
  - **Participantes**: puesto final, jugador, récord de todo el torneo (Swiss y Top Cut; BYE = victoria; doble derrota = derrota; cada ronda perdida por inscripción tardía = derrota), % de victorias y mazo. Franja verde para el Top Cut. Tocar un jugador abre su ficha.
- **Exportar** (imagen para WhatsApp HD): "Participantes" con el diseño de tabla de la app y la línea de metagame; "Metagame" como póster (fondo con textura, título METAGAME, dona y leyenda en dos columnas).

## Dona con imágenes, cruces de la ronda 1 y mazo editable
- **Dona del metagame con imágenes**: cada sector se rellena con la imagen del mazo (si un mazo no tiene imagen, con un color). Los mazos que jugó **un solo jugador** se juntan en un sector **OTROS** con su propia imagen (`assets/export/otros.webp`). La leyenda lista los mazos con imagen, jugadores y %, y debajo de OTROS los nombres de los mazos que lo forman. Las etiquetas de los participantes y la línea "Metagame" muestran la imagen del mazo en vez de un color.
- **Ronda 1 con cruces definidos**: al generar la ronda 1 se elige "Al azar" o "Definir cruces". En esa pantalla se toca un jugador y luego su rival (con número impar se puede dar el BYE a mano). Las mesas definidas van primero (mesa 1, 2…); el resto se empareja al azar y, si queda uno suelto, recibe el BYE. Solo en la ronda 1; las siguientes siguen siendo Swiss.
- **Mazo editable siempre**: el mazo de un inscrito se cambia tocándolo en Jugadores en cualquier fase, también con el torneo terminado (no con la temporada cerrada). Se actualiza también en todos sus matches de ese torneo, así la tier list, la matriz de enfrentamientos y el resumen quedan coherentes.
