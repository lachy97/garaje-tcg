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
- **Base de cartas** `assets/cards/edison_cards.json`: cartas legales en Edison según YGOPRODeck (`format=edison`), nombre en inglés, tipo, copias permitidas por la banlist (`ban_edison`; correcciones en `tools/cards/banlist_edison.txt`) y códigos de ilustraciones alternativas. La genera `tools/cards/build_card_db.py` en un **repositorio público aparte, `garaje-tcg-cartas`** (así el código de la app sigue privado), con el workflow `tools/cards/cartas.yml`; se descarga de `https://lachy97.github.io/garaje-tcg-cartas/edison_cards.json` y se copia a `assets/cards/`. Pasos en `tools/cards/LEEME.md`. Hasta entonces la app trae una base vacía.
- **Imágenes**: el mismo workflow las baja una vez de YGOPRODeck (≈10 por segundo, sin enlazarlas directo) y las publica en GitHub Pages `lachy97.github.io/garaje-tcg-cartas` (se descartó Cloudflare: más pasos y posible bloqueo de cuentas desde Cuba). `s/{código}.jpg` carta pequeña, `a/{código}.jpg` ilustración recortada. La app prueba los servidores en orden, comprueba que la respuesta sea un JPEG y guarda cada imagen en el teléfono la primera vez.
- **Permiso INTERNET** en Android: solo para estas imágenes; el resto de la app sigue sin conexión.
- **Ajustes → Cartas**: cuántas cartas hay, "Probar descarga de imágenes" (tiempo de cada servidor, para probar desde Cuba) y borrar las imágenes guardadas.

## Inscripción: último mazo y cover
- Al inscribir (normal o tardía), cada jugador aparece con su **último mazo**: el de su inscripción en el torneo empezado más reciente por fecha (sin contar el actual, los torneos en inscripción ni los borrados; si en el último no tenía mazo, vale el anterior). Se cambia con el icono de mazo antes de inscribir, o tocando al jugador ya inscrito mientras el torneo esté en inscripción.
- **Cover pagado** (esquema v7, `tournament_players.paid`): casilla "Cover" en cada inscrito, se puede marcar en cualquier momento (no con la temporada cerrada). Arriba se cuenta cuántos faltan por pagar. Al generar la ronda 1 se avisa de los que no tienen mazo o no han pagado, pero no impide empezar. Reinscribir a alguien no borra su pago. Viaja en las copias .gtcg.

## Resumen del torneo (pestaña Resumen)
- Con el torneo **terminado** aparece la pestaña **Resumen**:
  - **Metagame**: dona con un sector por mazo (jugadores que lo usaron, % del total; los inscritos sin mazo cuentan como "Sin mazo") y la leyenda completa. Colores fijos por orden de uso (16 colores; desde el 17º, gris). Arriba, la línea "Metagame" con los 3 más jugados y "+N".
  - **Participantes**: puesto final, jugador, récord de todo el torneo (Swiss y Top Cut; BYE = victoria; doble derrota = derrota; cada ronda perdida por inscripción tardía = derrota), % de victorias y mazo. Franja verde para el Top Cut. Tocar un jugador abre su ficha.
- **Exportar** (imagen para WhatsApp HD): "Participantes" con el diseño de tabla de la app y la línea de metagame; "Metagame" como póster (fondo con textura, título METAGAME, dona y leyenda en dos columnas).

## Dona con imágenes, cruces de la ronda 1 y mazo editable
- **Dona del metagame con imágenes**: cada sector se rellena con la imagen del mazo (si un mazo no tiene imagen, con un color). Los mazos que jugó **un solo jugador** se juntan en un sector **OTROS** con su propia imagen (`assets/export/otros.webp`). La leyenda lista los mazos con imagen, jugadores y %, y debajo de OTROS los nombres de los mazos que lo forman. Las etiquetas de los participantes y la línea "Metagame" muestran la imagen del mazo en vez de un color.
- **Ronda 1 con cruces definidos**: al generar la ronda 1 se elige "Al azar" o "Definir cruces". En esa pantalla se toca un jugador y luego su rival (con número impar se puede dar el BYE a mano). Las mesas definidas van primero (mesa 1, 2…); el resto se empareja al azar y, si queda uno suelto, recibe el BYE. Solo en la ronda 1; las siguientes siguen siendo Swiss.
- **Mazo editable siempre**: el mazo de un inscrito se cambia tocándolo en Jugadores en cualquier fase, también con el torneo terminado (no con la temporada cerrada). Se actualiza también en todos sus matches de ese torneo, así la tier list, la matriz de enfrentamientos y el resumen quedan coherentes.

## Ficha del jugador: enfrentamientos por rival
- Nueva tabla **Enfrentamientos por rival** (debajo de "Mazos usados"): por cada jugador contra el que ha jugado, partidas, victorias, derrotas, empates y % de victorias, sumando todos los torneos (Swiss y Top Cut). No cuentan los BYE ni las partidas sin resultado; la doble derrota cuenta como derrota.
- Orden: más partidas primero; a igualdad, el enfrentamiento más reciente. Se ven 10 y "Ver todos" despliega el resto. Franja verde si le gana más veces, roja si pierde más. Tocar un rival abre su ficha.

## Listas de mazos del Top 4 (pasos 2–4)
- **Dónde**: torneo terminado → pestaña **Resumen** → "Listas del Top 4". Cada jugador del 1º al 4º muestra "Ver lista" o "Subir lista". Sin roles todavía: lo hace quien usa la app (organizador o administrador).
- **Cargar**: importar un **.ydk** (icono de subir; las ilustraciones alternativas se convierten al código principal y las cartas que no son de Edison se avisan y se quitan) o **a mano** con el buscador (nombre en inglés; cada toque añade una copia al Main o al Side; las del Extra Deck van solas al Extra). En cada carta: + / −, mantener pulsado para moverla de sección, y la **estrella** para elegir la carta principal.
- **Avisos** (no impiden guardar): Main 40–60, Extra y Side ≤15, más de 3 copias, prohibidas/limitadas/semilimitadas de Edison, cartas del Extra en el Main y al revés, falta elegir la carta principal.
- **Datos** (esquema **v8**, tabla `deck_lists`): una lista por jugador y torneo; Main/Extra/Side como códigos separados por comas (una entrada por copia) y la carta principal. Viajan en las copias .gtcg (se integran con su torneo).
- **Ver**: cuadrícula por sección con ×N, carta principal y avisos. Menú: editar, **compartir .ydk**, borrar.
- **Imagen exportada** (una por jugador, 1600 px de ancho): logo, puesto, torneo, jugador, mazo y fecha; Main/Extra/Side con una imagen por copia (10 por fila); a la derecha la ilustración de la carta principal sobre un fondo del **tono opuesto** a su color medio (oscuro si la ilustración es clara, claro si es oscura) con borde verde neón. Las cartas sin imagen (sin conexión) salen con su nombre.
- Pendiente (paso 5): mostrar las listas en la ficha del mazo y del jugador.

## Imagen de la lista: dos modelos (v9)
- Al exportar se elige el modelo:
  - **Clásico** (vertical, 1080 px, como los carteles de torneos de Edison): ilustración de **fondo** desenfocada; la **principal** arriba a la izquierda y la **secundaria** abajo a la izquierda, fundiéndose con el fondo; título GARAGE TCG, torneo y fecha; puesto en dorado ("CAMPEÓN" / "Nº LUGAR"), jugador y mazo; MAIN en panel morado (una imagen por carta con el número de copias), SIDE en panel turquesa y EXTRA en panel naranja (una imagen por copia); al pie "LUGAR · Garage TCG" y el logo.
  - **Contraste** (horizontal, 1600 px): fondo en degradado del color que contrasta con la principal (ya no negro) y la ilustración principal grande a la derecha, sin marco, fundiéndose con el fondo; la lista a la izquierda.
- Las 3 imágenes (principal, secundaria, fondo) las elige quien sube la lista entre las cartas de la lista ("Imágenes para exportar" en el editor). Sin elegir: secundaria = primer monstruo del Extra/Main distinto de la principal; fondo = la principal.
- Esquema **v9**: `deck_lists.background_card` y `secondary_card`.
- **Ajustes (31/10)**: Clásico → Main con una imagen por copia y sin número de copias; columna izquierda dividida en dos mitades (imagen 1 arriba, imagen 2 abajo) que la llenan entera y se funden hacia la derecha; el fondo (imagen 3) solo detrás de la lista, más difuminado. Contraste → la ilustración 1 ocupa todo el alto del lado derecho; el lado de la lista lleva un fondo del **mismo tono** que la ilustración (oscuro, texto blanco). En el editor, las imágenes se llaman 1 · Arriba izq., 2 · Abajo izq. y 3 · Fondo, con un esquema de los dos modelos.
- **Formato (31/10)**: al exportar una lista se elige **Actual** (Clásico vertical 1080 px / Contraste horizontal 1600 px, alto según la lista) o **16:9** (1920 × 1080 fijo, ambos modelos). En 16:9 el tamaño de las cartas se calcula para que quepan Main, Side y Extra completos.

## Cambios 02/11
- **Ronda 1: mesa de cada cruce definido**: en "Definir cruces" se toca "Mesa N" de una pareja y se elige el número (o "Automática"). Las parejas sin mesa elegida y las que se emparejan al azar ocupan las mesas libres más bajas. No se puede repetir mesa.
- **Resumen en 3 apartados**: **Puntos** (solo los que suman puntos de ranking), **Top y metagame** (listas del Top 4 y la dona; selector **Todos / Top N** para ver solo el metagame del Top Cut; al exportar se elige **con o sin leyenda**; sin leyenda la dona sale más grande) y **Participantes** (tabla #, jugador, mazo, récord, win %).
- **Ficha del jugador en 3 pestañas**: **Resumen** (datos, estadísticas, mazos usados, penalizaciones), **Rivales** (enfrentamientos por rival) e **Historial** (partidas por torneo).
- **Matriz de enfrentamientos**: la columna de nombres y la fila de imágenes quedan fijas al desplazarse; ahora muestra hasta 20 mazos.
- **Datos**: Torneo 01/11, ronda 5 mesa 6: Cacharro 2-0 a Lachy Lawton (antes al revés). Solo el resultado de la partida; puestos finales y puntos de ranking del torneo sin cambios.

## Imagen de la lista: diseño único (02/11)
- Se deja **un solo diseño** (se quitan los modelos Clásico y Contraste): base del Contraste (fondo en degradado del tono de la ilustración principal; la ilustración ocupa todo el alto del lado derecho) y, en la zona de la lista, las letras y paneles del Clásico: GARAGE TCG + torneo · fecha, puesto en dorado, jugador, "MAZO" y el mazo; MAIN (morado, 10 por fila), SIDE (turquesa) y EXTRA (naranja), una imagen por copia.
- Abajo a la derecha: **GARAGE TCG · EDISON FORMAT · CUBA** con la bandera de Cuba (dibujada, sin archivo). Ya no sale el nombre de la carta principal.
- Formatos: **Actual** (1600 px de ancho, alto según la lista) o **16:9** (1920 × 1080; el Main se ajusta para que quepa).
- En el editor solo se elige la **imagen principal** (las columnas de imagen secundaria y fondo de la v9 se conservan pero no se usan).

## Clasificación vs. resultado real (v10) · 02/11
- **Clasificación** del torneo: solo la tabla Swiss (el resultado final con puntos está en Resumen → Puntos).
- Nuevas columnas `matches.standings_result` y `standings_games1/draw/2` (esquema **v10**): un resultado que cuenta **solo para el torneo** (puntos y desempates Swiss, cruces siguientes, siembra del Top y récord del Resumen) cuando el organizador decide mantener uno distinto del real. Las estadísticas de jugadores (ficha, rivales) y de mazos (matriz, fichas) usan siempre el resultado real. En la tarjeta de la partida sale "En la clasificación del torneo cuenta: …".
- Caso aplicado al actualizar a v10 (automático): Torneo 01/11, ronda 5, mesa 6 — real: Cacharro 2-0; clasificación: Lachy Lawton 2-0.
- **Dona del Top Cut**: cada mazo con su propio sector, sin agrupar en OTROS.

## Correcciones 09/11
- **Tablas**: todas las filas llevan la franja de color de la izquierda (transparente si no hay color), así el Top 8 del ranking queda alineado con el resto.
- **Ranking**: un solo botón de compartir (arriba). El selector de temporada está siempre disponible para ver temporadas anteriores.
- **Mazos**: compartir la tier list desde la barra superior (ya no al final). Tier list y enfrentamientos por temporada, con la opción **Histórico · todas las temporadas**.
- **Torneo terminado**: solo se ve el Resumen; para corregir jugadores, rondas o clasificación, botón **Editar torneo** (⚙) en la barra y **Listo** para volver.
- **Resumen**: tres pestañas con icono — **Participantes** (con la columna **Pts** de ranking; desaparece la pestaña Puntos y la tarjeta de metagame), **Deck Breakdown** (Todos / Top N) y **Listas** (de todo el Top Cut; sin Top Cut, los 4 primeros).
- **Imagen del Deck Breakdown**: título "TOURNAMENT DECK BREAKDOWN" o "TOP CUT DECK BREAKDOWN", siempre en una línea.
- **Ficha del jugador**: filtro de temporada (todas o cada temporada en la que jugó) para estadísticas, mazos, rivales e historial.
- **Un solo término: "Compartir"** para las imágenes (la copia de seguridad sigue siendo "Exportar base de datos", porque es un archivo).
- **Tamaños de letra** de la app reducidos a una escala fija: 11 · 12 · 14 · 16 · 20 · 24 (las imágenes compartidas mantienen los suyos).

## Correcciones 09/11 (2)
- **Compartir una lista**: un solo botón de compartir con tres opciones: **Imagen · Actual**, **Imagen · 16:9** y **Archivo .ydk** (ya no está aparte en el menú ⋮).
- **Listas del Top Cut**: botón **Compartir todas** (o "Compartir N de M" si faltan listas por subir) que comparte de una vez todas las listas subidas, como imágenes (en el formato elegido) o como archivos .ydk.
- **Rondas**: el tiempo de la ronda en juego queda **fijo arriba**; los cruces se desplazan por debajo.

## Cuentas y roles · preparación (09/11)
Primer paso del plan online: la app ya tiene cuentas, roles y permisos, con un **servidor simulado dentro del teléfono**. Cuando exista el servidor (Cloudflare Workers + D1, tras probar la fase 0 desde Etecsa) solo se cambia la implementación de `AuthApi` en `lib/core/auth/auth_providers.dart`.
- **Decidido**: los jueces **no necesitan licencia** (usan la del organizador del torneo). **Lo propio es gratis**: sin licencia el jugador ve su ficha y sus torneos (abiertos y terminados), el ranking y la tier list. La licencia da las estadísticas de todos los mazos (tabla de mazos, matriz, ficha de cada mazo) y, al organizador, llevar torneos.
- **Sin cuenta = modo local**: el teléfono funciona exactamente como hasta ahora (todo permitido). La pantalla de licencia sigue igual para todos.
- **Cuenta** (Ajustes → Cuenta): usuario único (3–20, letras sin tilde, números, `.` `_`, sin distinguir mayúsculas), Gmail obligatorio y único, apodo, teléfono opcional, contraseña (≥ 8 con letras y números). Código de 6 dígitos al Gmail, válido 15 min, 5 intentos por código, 3 códigos por hora y 60 s entre códigos. Inicio de sesión con usuario o Gmail; sesión de 30 días que funciona sin conexión. Olvidé / cambiar contraseña con código al Gmail (cierra las demás sesiones).
- **Simulación**: los correos no se envían; el código aparece en un recuadro amarillo "Servidor de prueba". Las cuentas viven en `auth_sim.json` (carpeta de soporte de la app, fuera de las copias .gtcg). La primera cuenta creada en el teléfono del administrador es **Administrador**; las demás empiezan como **Jugador**.
- **Administrador** (Ajustes → Cuenta → Cuentas y roles): cambiar rol, vincular la cuenta con su ficha de jugador (una ficha por cuenta), confirmar el Gmail a mano. **Ver la app como** Organizador / Juez / Jugador para probar qué ve cada rol (aviso amarillo arriba con "Volver").
- **Permisos aplicados** (`lib/core/auth/permissions.dart`, con tests): pestaña Jugadores solo para el administrador (los demás ven **Mi ficha**); fichas ajenas bloqueadas; tabla de mazos, matriz y ficha de mazo con licencia; crear/eliminar/editar torneos, gestionar mazos, editar tiers y subir/editar listas solo organizador con licencia o administrador; copias .gtcg para administrador y organizadores; quien no lleva torneos ve solo aquellos en los que está inscrito (terminados: solo el Resumen; en juego: aviso de que llegarán en vivo con el servidor).
- Por ahora todos los torneos del teléfono cuentan como del organizador que lo usa (no hay torneos de otros hasta la sincronización). Jueces por torneo, preinscripción y sincronización: fases siguientes.

## Servidor de cuentas (09/11)
- Carpeta **`server/`**: Cloudflare Workers + D1 en JavaScript sin dependencias (solo `wrangler` para publicar). Guía paso a paso en `server/LEEME.md` (cuenta de Cloudflare, Node.js, base D1, publicar, fase 0, Brevo). Pruebas con `npm test` (Node 22, simulan D1 con SQLite).
- Si desde Cuba no responde sin VPN, **se usa VPN** para acceder (decidido); los torneos siguen funcionando sin conexión.
- Publicación **desde el PC** con `npm run deploy`. Remitente de los códigos: un **Gmail nuevo del club** verificado en Brevo.
- Administrador: la cuenta registrada con el Gmail guardado en el secreto `ADMIN_EMAIL`. Sin Brevo configurado el servidor queda en **modo de pruebas** (`DEV_CODES = "1"`): devuelve el código y la app lo muestra; pasar a `"0"` antes de abrir el registro a los jugadores.
- Seguridad: PBKDF2-SHA256 100.000 iteraciones, tokens y códigos guardados como hash, 10 inicios fallidos cada 15 min.
- App: `lib/core/auth/server_config.dart` (`kServerUrl`; vacía = servidor simulado) y `HttpAuthApi`. **Ajustes → Servidor**: a qué servidor está conectada y **Probar conexión** (también con una dirección escrita a mano, para la fase 0 sin recompilar). Sin conexión la sesión guardada sigue valiendo; al abrir la app se actualizan rol y ficha.

## Sincronización · fase 2 (10/11)
- El teléfono del organizador **sube** sus datos al servidor; el servidor es la copia principal. Los torneos se siguen jugando con la base local, sin conexión.
- **Cola automática**: disparadores de SQLite (`lib/core/sync/sync_schema.dart`, se instalan al abrir la base; sin cambiar la versión del esquema) apuntan en `sync_outbox` cada fila insertada, cambiada o borrada de las 13 tablas. Así cualquier cambio (pantallas, importar .gtcg, deshacer ronda…) se sube sin tocar cada consulta.
- **Subida** (`SyncController`): cada 30 s, al volver a la app y al salir, en lotes de 200 filas (fila completa en JSON tal como está en SQLite; borrado = marca de borrado). La primera vez que una cuenta sube desde un teléfono se pone en cola todo.
- **Servidor** (`server/src/sync.js`, tabla `sync_rows`, migración `0002_sync.sql`): solo organizadores y administrador suben; gana el cambio más reciente; una fila solo la cambia quien la subió primero (o el administrador). `/v1/sync/pull` (por número de llegada) y `/v1/sync/status` quedan listos para la fase 3 (bajar datos a los jugadores según permisos) y para restaurar.
- **Ajustes → Sincronización**: pendientes, última subida, "Sincronizar ahora" y "Volver a subir todo".
- Límites conocidos: las fotos propias de jugadores y mazos no se suben (solo su ruta). "Volver a subir todo" marca las filas con la hora actual (si se usa desde un teléfono con datos viejos, pisaría datos más nuevos del servidor). Por ahora solo un teléfono organizador (el de Lachy).

## Fase 0: resultado (10/11)
- `https://garage-tcg-api.garagetcg.workers.dev/v1/health` desde Cuba con datos de Etecsa: **sin VPN no responde; con VPN sí**. Se sigue con Cloudflare y los teléfonos usan **VPN** para conectarse (decidido). Los torneos siguen funcionando sin conexión y los cambios esperan en la cola hasta que haya VPN.
- La app ya avisa "El servidor no responde. Revisa la conexión (o prueba con VPN)" cuando no llega.
- Si más adelante se quiere evitar la VPN, opciones a estudiar: dominio propio delante del Worker o un reenvío desde un proveedor accesible desde Cuba (no implementado).

## Fase 3: app del jugador (10/11)
- **Sin licencia con cuenta**: los jugadores y jueces que inician sesión entran a la app sin licencia (lo suyo es gratis). La pantalla de licencia tiene ahora "¿Eres jugador? Iniciar sesión / Crear cuenta". Sin cuenta, o con cuenta de organizador, sigue haciendo falta la licencia.
- **Bajar datos** (teléfonos de jugadores y jueces): cada 30 s, al volver a la app y en Ajustes → Sincronización ("Actualizar ahora", "Volver a bajar todo"). Se guardan en la base local, así se ven sin conexión y las pantallas de siempre funcionan igual (ranking, tier list, Mi ficha, torneos).
- **Qué baja** (`/v1/sync/pull` filtra en el servidor, migración `0003_pull_filters.sql`): catálogo de mazos, temporadas, escalas de puntos, fotos de ranking y tier list; torneos **terminados** completos (hacen falta para calcular ranking y tier list) y los **en juego donde está inscrito**; de los demás jugadores **solo el apodo** (sin nombre, teléfono, Konami ID ni notas); solo **sus** penalizaciones. Cuando un torneo pasa a ser visible (termina o lo inscriben) llega entero.
- Decisión práctica: los resultados de los torneos terminados llegan a todos los teléfonos porque el ranking y la tier list (gratis) se calculan con ellos; la app solo deja ver la ficha propia. Los datos personales nunca salen del servidor.
- **Torneo en juego en el teléfono del jugador**: pestañas Rondas (con el tiempo de la ronda) y Clasificación, solo consulta (sin reportar, avanzar ni cambiar cruces).
- Lo que llega del servidor no se vuelve a poner en la cola de subida (los disparadores se saltan mientras hay la marca `applying`).
- Si el administrador vincula la ficha más tarde, el teléfono vuelve a bajar todo.

## Correos: SendPulse (10/11)
- Brevo no acepta direcciones de Cuba. Se usa **SendPulse** (ya probado desde Cuba en otra app): SMTP API con OAuth (ID + Secret), HTML en base64, token de 1 h guardado en el Worker y reintento si vence. Secretos `SENDPULSE_ID`, `SENDPULSE_SECRET`, `MAIL_FROM`. Brevo sigue como alternativa (`BREVO_API_KEY`). Guía: `server/LEEME.md`, paso 9.

## Correos: Gmail del club + aprobación del administrador (10/11)
- SendPulse sin dominio propio solo deja enviar en modo prueba (50 correos, remitente de ellos) y no se quiere usar el dominio de la otra cuenta. Se envía **desde el Gmail del club por SMTP** (`server/src/smtp.js`, sockets TCP de Workers, TLS en el puerto 465, AUTH con **contraseña de aplicación**). Secretos `GMAIL_USER` y `GMAIL_APP_PASSWORD`. Orden: Gmail → SendPulse → Brevo.
- **Aprobación del administrador como respaldo**: si el correo no sale, la cuenta se crea igual (`mailFailed`) y la app lo dice; el administrador la confirma en Cuentas y roles ("Confirmar Gmail a mano") y el jugador entra con "Ya me la confirmaron: entrar". Para contraseña olvidada, "Código para cambiar la contraseña" en Cuentas y roles da un código de 15 min para mandarlo por WhatsApp; el jugador usa "Olvidé mi contraseña → Ya tengo un código".

## Ficha del mazo como la del jugador (11/11)
- La ficha de cada mazo tiene 4 pestañas y selector de temporada (o histórico): **Resumen** (Power, tier, presencia, conversión; partidas, V-D-E, winrate total, Swiss y Top Cut, torneos; **mejor y peor piloto** y **mejor y peor enfrentamiento**), **Pilotos** (cada jugador con el mazo: torneos, PJ, V-D-E, WR, Tops, mejor puesto), **Rivales** (récord contra cada mazo y contra cada jugador) e **Historial** (torneos con puesto y Power, y todas las partidas).
- Reglas: winrate = victorias ÷ partidas (empates no ganan); los totales del mazo y los enfrentamientos **no cuentan espejos** (se muestran aparte); las cifras de cada piloto **sí** los cuentan. Mejor/peor piloto y enfrentamiento: con **al menos 3 partidas** (si ningún piloto llega, entre todos). Sigue requiriendo licencia (estadísticas de mazos).
- Correo: **Ajustes → Servidor → Enviarme un correo de prueba** (solo administrador) muestra el error exacto del envío.

## Auditoría de diseño (11/11)
- Ver `docs/DISENO_UX.md`: avisos de error legibles, estados de error/carga sin parpadeo, icono de sincronización y "arrastrar para sincronizar", Torneos agrupados por estado y cabecera compacta, crear torneo con botón fijo y sugerencias aplicables, buscador de inscritos, vibración al marcar resultado, borrar jugador desde menú, Ajustes reordenado (Servidor solo administración).

## Logo nuevo y modo claro/oscuro (11/11)
- **Logo**: redibujado a partir de las imágenes del club manteniendo el diseño (casa con puerta de garaje, GARAGE, — TCG —). Un solo PNG blanco que la app tiñe (blanco en oscuro, casi negro en claro). Icono de la app y pantalla de inicio regenerados.
- **Modo de color**: Ajustes → Apariencia: Sistema (por defecto), Claro u Oscuro; se guarda en el teléfono. Los colores de la app (`AppColors`) dependen de la paleta activa; al cambiar se redibuja todo sin perder el estado.
- Las **imágenes compartidas** (ranking, tier list, torneos, informes, listas) se dibujan **siempre en oscuro**, para que se vean iguales en WhatsApp.
- **Deshacer** al borrar jugador o torneo; **bienvenida** una vez por cuenta de jugador/juez; **destacados** en la ficha del jugador. Pendiente: primera columna fija, letra grande, pantalla encendida y Semantics (ver `docs/DISENO_UX.md`).

## Tablas, letra grande, pantalla encendida y accesibilidad (11/11)
- Tablas con **columnas fijas** (hasta la del nombre) al desplazar en horizontal.
- **Letra del sistema** limitada a 130 % en toda la app; las tablas ensanchan sus columnas con ese factor.
- **Pantalla encendida** mientras corre el tiempo de ronda, solo en el teléfono que lleva el torneo (no en los de solo consulta). Nueva dependencia: `wakelock_plus`.
- **Semantics** en botones de resultado, tarjetas de mesa y filas de tablas.

## Importar la ronda 1 desde texto (11/11)
- Complementa "Compartir ronda → Texto": se pegan los cruces (el mismo texto de WhatsApp o una lista a mano: `Mesa 1: Ana vs Luis`, `3. Ana vs Luis`, `BYE: Pedro`; título, marcadores y asteriscos se ignoran) y se reconocen los apodos de los inscritos (sin importar mayúsculas ni tildes; también el nombre completo).
- **Solo ronda 1**. Dónde: al generar la ronda 1 (botón "Importar texto", además de "Definir cruces" y "Al azar"), en la pantalla de cruces de la ronda 1 (botón de pegar arriba) y, si la ronda 1 ya está generada y **sin resultados**, "Importar cruces desde texto" en la propia ronda (deshace y vuelve a generar en una sola operación; el tiempo de ronda se reinicia).
- Siempre se revisa antes de generar: los cruces importados aparecen como "definidos" y se pueden quitar o cambiar; los inscritos que no estén en el texto se emparejan al azar. Avisos: nombres no inscritos, jugadores repetidos, mesas repetidas o inexistentes (toman otra libre), más de un BYE o BYE con número par.
- Código: `lib/features/tournaments/domain/round_import.dart` (Dart puro, `test/round_import_test.dart`), `TournamentService.replaceFirstRound`.

## Acceso solo con cuenta y espaciado de botones (11/11)
- **La app solo se usa con sesión iniciada** (decisión del 11/11, reemplaza al "Continuar sin cuenta"): sin sesión solo se ve la pantalla de inicio (**Iniciar sesión** / **Crear cuenta**); no se puede navegar a nada más. Al cerrar sesión se vuelve ahí. Iniciar sesión o crear cuenta necesita conexión (con VPN); la sesión se guarda en el teléfono (30 días) y funciona sin conexión. Después de la sesión sigue la licencia: organizadores y administrador la necesitan, jugadores y jueces no. La pantalla de licencia tiene "Cerrar sesión" para entrar con otra cuenta. Código: `lib/features/account/start_screen.dart` (`StartGate` envuelve a `LicenseGate`).
- Botones apilados con separación de 10 dp (Ajustes → Servidor, administrador, y en todos los diálogos cuando los botones no caben en una fila). El aviso de "Generar ronda 1" muestra las tres opciones (Al azar, Definir cruces, Importar texto) en vertical, a todo el ancho y con una línea de explicación.

## Sesión que se renueva sola y mejoras de uso (11/11)
- **Sesión deslizante**: `GET /v1/me` renueva la sesión (30 días desde ese momento) y devuelve `expiresAt`. La app lo llama al abrirse y al volver a ella (como mucho una vez por hora) si hay conexión. Así nadie se queda fuera en medio de un torneo: solo hay que volver a iniciar sesión si se pasan 30 días seguidos sin abrir la app con conexión. Necesita volver a desplegar el servidor (`npm run deploy`); con el servidor anterior la app sigue funcionando (sin renovar).
- **Iniciar sesión**: recuerda el último usuario o Gmail del teléfono y pone el cursor en la contraseña; teclado de correo sin autocorrección, "siguiente" pasa a la contraseña y "listo" entra; botón de mostrar/ocultar contraseña con nombre para lector de pantalla. El aviso de "sin conexión" recuerda activar la VPN.
- **Botón atrás** en la pantalla principal: en Ranking, Mazos o Jugadores vuelve a Torneos; en Torneos hay que pulsarlo dos veces seguidas para salir ("Pulsa atrás otra vez para salir"), para no cerrar la app sin querer durante un torneo.

## Inscripción desde la app (11/11)
- El organizador la abre por torneo en **Jugadores → Inscripción desde la app** (solo en inscripción, con servidor). Elige **A mano** (acepta o rechaza cada solicitud, con motivo opcional) o **Se aceptan solas** (las cuentas con ficha vinculada quedan aceptadas al momento; las que no tienen ficha esperan a que el organizador elija o cree su ficha). Esquema local v11: `tournaments.online_registration` y `auto_accept`.
- El jugador ve en **Torneos → Inscripción abierta** los torneos abiertos (lista que da el servidor, así no se ven abiertos torneos que ya cerraron), pide plaza eligiendo su mazo (sale el último que usó), puede cambiar el mazo mientras está pendiente, cancelar o borrarse, y volver a pedir si lo rechazan.
- La inscripción de verdad la crea **el teléfono del organizador** (dueño del torneo): al aceptar a mano, al momento; las aceptadas solas, en la siguiente sincronización (cada 30 s con la app abierta). Las bajas de jugadores ya inscritos también se aplican ahí. El servidor solo guarda las solicitudes (tabla `registrations`, migración `0004_registrations.sql`, `npm run db:inscripcion`).
- Aceptar a una cuenta sin ficha la **vincula** a la ficha elegida (si esa ficha no es de otra cuenta).
- Los torneos en inscripción con la inscripción desde la app abierta bajan a los teléfonos de los jugadores (con los inscritos, solo apodos).
- Se cierra sola al generar la ronda 1. El cover se sigue marcando a mano.

## Decisiones de privacidad y roles (11/11)
- **Ficha pública**: los jugadores verán la ficha pública de otros (apodo, torneos, mazos, winrate), sin datos personales (pendiente: tanda 5).
- **Teléfono**: lo ven el administrador y el organizador.
- **Listas de mazo**: de todo el Top Cut; el organizador elige si se ven al momento, solo el arquetipo o al terminar (pendiente: tanda 4).
- **Juez por torneo**: todas las partidas y penalizaciones de ese torneo, sin teléfonos ni cover (pendiente: tanda 3).
- **Sesión obligatoria**; más adelante, una web pública con datos de la comunidad.
- **Servidor (hecho)**: a jugadores y jueces ya no les llegan el **cover pagado** ni las **notas del organizador**. Los **organizadores** ya no reciben todo: sus torneos completos (cover, notas, penalizaciones de todos), los datos de los jugadores (también el teléfono) y del resto lo mismo que un jugador. El administrador sigue recibiendo todo.
- Pendiente (tanda 5): que los jugadores sin licencia reciban el ranking y la tier list ya calculados en vez de todas las partidas.

## Tanda 1 de mejoras (11/11)
- **Mi mesa ahora** (Torneos, arriba): para quien tenga ficha vinculada y esté en un torneo en juego: ronda, mesa, rival, su mazo, resultado y tiempo que queda; toca para abrir el torneo.
- **Pantalla para proyectar** (icono de TV en la barra del torneo en juego, organizador): cruces y clasificación en letra grande, reloj, columnas según el ancho; cambia sola cada 20 s o con un toque; pantalla completa y sin apagarse.
- **Cupo y lista de espera** en la inscripción desde la app (esquema v12, `tournaments.capacity`, 0 = sin límite): con el cupo lleno (inscritos + aceptadas + pendientes) las solicitudes nuevas van a la lista de espera con su puesto; al liberarse plazas suben por orden de llegada (aceptadas solas o pendientes, según el modo). Aceptar a mano con el cupo lleno pide aumentarlo o rechazar a alguien.

## Compilación: Flutter fijo en 3.47 (11/11)
- Flutter 3.50 exige AGP 9.1.1+ y Gradle 9.3.1+; el proyecto usa AGP 8.11.1 + Gradle 8.14.3 (y Kotlin 2.2.20). Saltarse la comprobación no basta: el plugin de Flutter 3.50 usa la API de AGP 9 y falla con AGP 8. El workflow fija `flutter-version: 3.47.x`. Pasar a AGP 9 / Gradle 9 queda como migración aparte cuando Flutter resuelva los fallos abiertos (flutter#192167, #192111).

## Tanda 2: resultados, juez y drop desde el móvil (12/11)
- **Reportar resultado**: en "Mi mesa ahora", el jugador elige su resultado (Gané 2-0, Gané 2-1, Empate 1-1-1 —no en Top Cut—, Perdí 1-2, Perdí 0-2). El rival ve "X reportó: ganas/pierdes…" y **confirma** o dice **no es correcto**. Si los dos reportan lo mismo, queda confirmado; si no, queda **en disputa** para el juez/organizador.
- Los **confirmados** los pone solo el teléfono del organizador al sincronizar (si la mesa sigue sin resultado). Los demás se ven en **Avisos de los jugadores** (ronda actual): "Poner 2-1" para aplicarlo, o "Descartar". El resultado que ponga el organizador a mano siempre manda.
- **Llamar al juez** (con nota opcional) y **drop** desde el móvil. El drop se aplica solo al sincronizar (desde la ronda actual); la llamada al juez se marca "Atendido".
- Servidor: tabla `play_actions` (migración `0005_play.sql`, `npm run db:mesa`), rutas `/v1/play/*`.

## Tanda 3: check-in y jueces por torneo (12/11)
- **Check-in** (Jugadores del torneo, en inscripción): interruptor + código de 4 caracteres (sin 0/O ni 1/I; "Nuevo código" lo cambia). El jugador lo escribe en Torneos → Check-in; el organizador también puede marcarlo a mano en cada inscrito. Al generar la ronda 1, si hay inscritos sin check-in: **Quitarlos** / **Jugar con todos**. El código no llega a los teléfonos de los jugadores.
- **Jueces por torneo** (Jugadores → Jueces → Gestionar): cuentas con rol Juez u Organizador. El juez ve el torneo entero (partidas y penalizaciones de todos, sin cover, notas ni teléfonos) y tiene **Vista de sala** (icono de mazo en la barra): mesa por mesa, **poner resultado** (también doble derrota; lo que pone el juez manda), **tiempo extra** por mesa (total en minutos) y **penalización** (jugador, tipo, motivo). También ve y atiende los avisos de los jugadores.
- Todo lo que hacen el juez y el check-in lo aplica el teléfono del organizador al sincronizar. El tiempo extra se ve en la mesa del jugador y en la tarjeta de la mesa ("+5 MIN").
- Esquema local v13: `tournaments.check_in`, `checkin_code`; `tournament_players.checked_in`; `matches.extra_minutes`. Servidor: `tournament_staff` y columnas nuevas en `play_actions` (migración `0006_judges.sql`, `npm run db:jueces`).

## Tanda 4: listas de mazo del Top Cut y su visibilidad (12/11)
- Las listas ya eran de todo el Top Cut (el resumen usa el tamaño del Top; sin Top, el Top 4). Ahora también se pueden subir **mientras se juega el Top Cut**: icono de cartas en la barra del torneo (organizador) → "Listas del Top Cut".
- **Quién ve las listas** (icono de ojo en "Listas del Top", organizador; esquema v14 `tournaments.list_visibility`): **en cuanto se suben** (por defecto), **solo el mazo, sin las cartas**, o **al terminar el torneo**. Lo aplica el servidor: a jugadores y jueces de otros torneos no les llegan las listas ocultas; el organizador y los jueces de ese torneo las ven siempre. Si se pasa de "abiertas" a otra opción, quien ya las bajó las conserva.
- Para los jugadores, las listas no publicadas salen como "Sin publicar".

## Tanda 5: ficha pública (12/11)
- Todos (con sesión) ven la **ficha pública** de cualquier jugador: apodo, torneos, mazos, winrate, destacados y rivales. Los **datos personales** (nombre, Konami ID, teléfono, notas) y las **penalizaciones** solo los ven el propio jugador, el administrador y los organizadores (`Permissions.canSeePersonalData`). El servidor ya no envía esos datos a los jugadores.
- Se llega a una ficha tocando una fila del **ranking**, de la **clasificación** de un torneo, de los participantes del resumen, o desde rivales y mazos.
- **Ranking ya calculado (privacidad #4)**: con la ficha pública, los resultados de los torneos terminados tienen que llegar a los teléfonos igual (de ellos salen torneos, mazos y winrate de cada ficha), así que mandar el ranking calculado no ocultaría nada más y obligaría a duplicar en el servidor el cálculo del ranking y de la tier list. Se queda como está: los jugadores sin licencia reciben esas partidas pero la app no les muestra las estadísticas de mazos.

## Tanda 6: avisos en el teléfono (12/11)
- **Sin Google** (Firebase está bloqueado en Cuba): los avisos los genera la propia app con `flutter_local_notifications` cada vez que sincroniza (cada 30 s con la app abierta o recién cerrada, y al volver a ella). Si Android cierra la app del todo, los avisos llegan al abrirla de nuevo. No hay avisos con la app cerrada del todo; para eso haría falta un servicio en segundo plano (más batería) o Google.
- **Jugador**: ronda nueva con su mesa y rival (o BYE), quedan 5 minutos, se acabó el tiempo, su rival reportó el resultado (para confirmar), y cambios en su inscripción (aceptada, rechazada, lista de espera).
- **Organizador y jueces**: llamadas al juez, resultados en disputa y solicitudes de inscripción nuevas.
- Cada aviso sale una sola vez (se recuerdan los últimos 400). **Ajustes → Avisos** los apaga. El permiso de Android 13+ se pide la primera vez que se entra a la app.
- Android: permiso `POST_NOTIFICATIONS` y *core library desugaring* (`desugar_jdk_libs` 2.1.4) en `android/app/build.gradle.kts`, que pide el plugin.

## Correcciones (13/11)
- **Torneo borrado seguía saliendo a los jugadores** en "Inscripción abierta": el borrado es lógico (`deleted_at` en la fila), y el servidor solo miraba su marca `deleted`. Ahora inscripciones y acciones de mesa ignoran también las filas con `deleted_at` (torneos, inscritos quitados). Las bajas de inscritos tampoco cuentan ya para el cupo ni para "ya inscrito".
- **Icono de los avisos**: silueta blanca de la casa del logo (`res/drawable-*/ic_notification.png`, tintada de verde), con `res/raw/keep.xml` para que la compilación de release no la quite.
- **Jugadores del torneo**: la cabecera, las tarjetas (inscripción desde la app, check-in, jueces, penalizaciones) y el buscador ya no quedan fijos; todo se desplaza junto con la lista de inscritos.
- Probado desde Cuba con internet (sin VPN): funciona.

## Mejoras de estabilidad del torneo (14/11)
- **¿Me llegan los reportes?** En la ronda actual, el organizador ve "Sincronizado hace 12 s". En ámbar a partir de 1 min; en rojo a partir de 2 min o si hay error ("los reportes de los jugadores no te llegan"), con **Reintentar**.
- **Versión mínima de la app**: cada llamada envía `X-App-Build` (número de compilación de GitHub Actions; el prefijo de arquitectura de `--split-per-abi` se quita: 2045 y 1045 = 45). Si en el servidor se pone `MIN_APP_BUILD`, las versiones anteriores (o sin cabecera) reciben 426 `update_required` y la app muestra arriba, en rojo, "Hay una versión nueva…". La sesión no se cierra por eso. `/v1/health` no se bloquea.
- **Avisos con la app minimizada**: mientras el teléfono juega, lleva o arbitra un torneo en juego, un servicio en primer plano (`flutter_foreground_task`, tipo `dataSync`) con el aviso fijo "Torneo en curso" evita que Android congele la app; se quita solo cuando ya no hay torneos en juego. Ajustes → Avisos → "Avisar con la app minimizada durante el torneo" (activado por defecto). Si se cierra la app desde Recientes, se detiene como antes.

## Seguir un torneo desde otro teléfono (14/11)
- **Problema**: si el teléfono del organizador se queda sin batería o sin datos a mitad de torneo, todo se paraba (solo ese teléfono tenía el torneo y podía cambiarlo).
- **Un teléfono a cargo por torneo** (servidor 1.9.0, migración `0007_control.sql`, `npm run db:control`): cada teléfono tiene un identificador propio (`X-Device-Id`, nombre "Teléfono 3F2A" en `X-Device-Name`). El primero que sube un torneo lo lleva. El servidor **rechaza los cambios de cualquier otro teléfono** en ese torneo (`not_controller`), también los borrados. Las versiones viejas de la app (sin identificador) no se comprueban.
- **Los organizadores ahora también bajan** del servidor sus torneos y aquellos en los que son jueces (nada más). Así otro teléfono con la misma cuenta, o el del administrador, tiene el torneo al día. Al bajar, no se pisan los cambios propios que aún no se subieron.
- **Latido**: en cada sincronización, el teléfono avisa de que sigue llevando sus torneos en juego. Si un torneo lo lleva otro, aquí se abre **solo para consultar**, con un aviso: "Este torneo lo lleva Teléfono X, activo hace 3 min" y el botón **Tomar el control**. Tomarlo bloquea al otro teléfono; lo que este no llegó a subir se pierde (se avisa antes), y el otro teléfono baja todo de nuevo para quedarse con lo del servidor.
- Puede tomar el control el **organizador dueño** del torneo (desde otro teléfono) o el **administrador**. Las filas nuevas que crea el administrador en un torneo ajeno quedan a nombre del dueño, para que este pueda retomarlo después. Un torneo de otro organizador (por ser juez) sale siempre solo para consultar.
- Quién lleva cada torneo se guarda en el teléfono: sin conexión no se toma por propio un torneo que lleva otro.
