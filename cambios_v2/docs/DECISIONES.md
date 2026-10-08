# Decisiones de diseño — Garaje TCG

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

## Torneo
- **Matches al mejor de 3** (gana quien llega a 2 juegos). Marcador `J1 - Empates - J2`, solo se aceptan: 2-0-0, 2-0-1, 0-0-2, 1-0-2 y 1-1-1 (empate del match). En Top Cut no se acepta 1-1-1. El BYE se registra 2-0-0. Se guardan los juegos (columnas `games1`, `gamesDraw`, `games2`) y el resultado del match se deriva del marcador.
- Rondas Swiss (1-15) y Top Cut (Sin Top / 4 / 8 / 16 / 32) se eligen al crear el torneo y se pueden ajustar solo durante la inscripción. **Al generar la ronda 1 quedan fijos.** La app solo muestra una sugerencia orientativa; nunca cambia la configuración por su cuenta. Al empezar se comprueba que haya jugadores suficientes para el Top elegido.
- Swiss: V=3, E=1, D=0. El BYE cuenta como victoria. Desempates: OMW% (piso 33 %) → OOMW% → GW% (% de juegos ganados propio, piso 33 %; el BYE cuenta 2-0).
- Rondas sugeridas (valor por defecto): ceil(log2 N), mínimo 3.
- Top Cut según asistencia: **menos de 15 jugadores → Top 4** (mínimo 6 jugadores); 15+ → Top 8; 24+ → Top 16; 48+ → Top 32. Se siembra 1 vs N según el Swiss (el 1 y el 2 solo se cruzan en la final). Los jugadores retirados no entran al Top.
- Pairings: ronda 1 aleatoria; después por puntos, con orden aleatorio dentro de cada grupo de puntos. Backtracking sin repetir rivales; solo se repite rival si es imposible evitarlo. El BYE va al jugador con menos puntos que aún no haya tenido BYE.
- En el Top Cut no hay empates: cada match necesita un ganador.
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
- Exportación a PNG de la tabla completa (cualquier número de filas), 1600 px de ancho, y menú de compartir de Android.

## Puntuación de mazos
- PP = 3·V_swiss + 1·E_swiss + 6·V_top + 3·Entradas_top + 5·Títulos
- WRp = (V_swiss + 2·V_top + 0.5·E + 5) / (Partidas_swiss + 2·Partidas_top + 10)
- Score = PP × (0.5 + WRp)
- Desempates: títulos, victorias en Top, WRp, mejor resultado.
- "Mejor rendimiento" exige un mínimo de 8 partidas.

## Pendiente de confirmar
- Torneos de menos de 6 jugadores: no tienen Top Cut, así que no dan puntos de ranking.
