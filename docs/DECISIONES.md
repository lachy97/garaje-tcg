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
- **Exportación** (ranking y tier list): al exportar se elige el formato:
  - *Imagen única (alta calidad)*: toda la tabla en un PNG de hasta 2400 px de ancho (la densidad baja en tablas muy largas para no pasar ~8000 px de alto, límite de muchos móviles). Se entrega **dentro de un PDF de una sola página** del tamaño exacto de la imagen: WhatsApp decide por la extensión y un .png siempre lo comprime como foto, mientras que un PDF va como documento intacto.
  - *Documento PDF*: A4 con los colores de la app, texto vectorial (Inter en TTF, `assets/fonts/pdf/`), varias páginas repitiendo la cabecera de la tabla.
  - *Imágenes para el chat*: PNG de 1920 px con 12 filas cada uno.

## Puntuación de mazos
- PP = 3·V_swiss + 1·E_swiss + 6·V_top + 3·Entradas_top + 5·Títulos
- WRp = (V_swiss + 2·V_top + 0.5·E + 5) / (Partidas_swiss + 2·Partidas_top + 10)
- Score = PP × (0.5 + WRp)
- Desempates: títulos, victorias en Top, WRp, mejor resultado.
- Pestaña **Mazos** = tabla de la temporada para la tier list de fin de trimestre: #, tier, mazo, Score, uso (inscripciones), jugadores distintos, PJ, V, D, E, WR%, entradas al Top, V en Top, títulos y mejor posición. Solo torneos terminados; la doble derrota cuenta como derrota para ambos mazos.
- **Tiers** relativos al mejor Score de la temporada: S ≥ 70 %, A ≥ 45 %, B ≥ 20 %, C el resto. Se muestra la tier list (filas S/A/B/C) y la tabla; se exporta como imágenes (la tier list primero, luego la tabla de 12 en 12).
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
