# Garage TCG · Auditoría de diseño y experiencia de uso (11/11/2026)

Análisis de toda la app (tema, componentes y pantallas) con las mejoras ya aplicadas
y las propuestas para las siguientes iteraciones. Prioridad: **A** = estorba en el uso
real (torneo en marcha, jugadores nuevos), **B** = fricción notable, **C** = pulido.

## 1. Sistema visual

| Hallazgo | Prioridad | Estado |
|---|---|---|
| Avisos (SnackBar) de error con texto rojo sobre fondo verde oscuro: poco contraste y se confunden con los avisos normales; duraban lo mismo que un aviso corto. | A | **Hecho**: icono, fondo rojizo con borde, texto claro y 6 s para errores; aviso neutro con icono de información. |
| Errores de carga mostraban `Error: <excepción>` en rojo pegado al borde. | B | **Hecho**: estado vacío "No se pudo cargar" con icono y el detalle debajo. |
| Al recargar datos (sincronización, cambiar de temporada) las listas parpadeaban con un spinner a pantalla completa. | B | **Hecho**: se mantienen los datos anteriores mientras se recarga. |
| Títulos de la barra superior con mucho espaciado y brillo: los nombres largos de torneos y mazos se cortaban antes de tiempo. | C | **Hecho**: 20 px, espaciado 1.0 y brillo más suave. |
| Iconos de los estados vacíos en verde musgo casi invisible sobre negro. | C | **Hecho**: verde hoja. |
| Escala tipográfica (11 · 12 · 14 · 16 · 20 · 24) | — | Ya unificada el 09/11. |

## 2. Navegación y estado de conexión

| Hallazgo | Prioridad | Estado |
|---|---|---|
| No se veía si el teléfono estaba sincronizado ni si había cambios sin subir (solo dentro de Ajustes). | A | **Hecho**: icono de nube junto a Ajustes en Torneos (al día · subiendo · cambios pendientes · sin conexión); tocarlo abre Ajustes. |
| Para actualizar había que ir a Ajustes → Sincronización. | A | **Hecho**: **arrastrar hacia abajo** en Torneos, Ranking y Tier list sincroniza (sube o baja según el teléfono). |
| Ajustes mezclaba opciones técnicas (servidor, diagnóstico) con las de uso diario y las mostraba a los jugadores. | B | **Hecho**: orden Cuenta → Sincronización → Licencia → Copia → Cartas → Servidor (solo administración) → Administrador → Acerca de. |

## 3. Torneos (pantalla principal)

| Hallazgo | Prioridad | Estado |
|---|---|---|
| Cabecera con logo de 96 px + título: la lista empezaba a media pantalla en móviles pequeños. | B | **Hecho**: logo 72 px y título más compacto. |
| Torneos en una sola lista mezclando en juego, inscripción y terminados. | B | **Hecho**: secciones **En juego**, **Inscripción abierta** y **Terminados** con su número. |
| Mismo icono (rayo) para torneos en inscripción y en juego. | C | **Hecho**: inscripción con icono propio; nombres largos en 2 líneas. |

## 4. Crear torneo

| Hallazgo | Prioridad | Estado |
|---|---|---|
| El botón "Crear torneo" quedaba al final; había que bajar para encontrarlo. | A | **Hecho**: botón fijo abajo, con indicador mientras guarda. |
| Si fallaba al guardar no se avisaba (error sin capturar). | A | **Hecho**: aviso de error. |
| La tabla de sugerencias era solo informativa: había que copiar los valores a mano. | B | **Hecho**: tocar una fila aplica rondas y Top Cut; la fila elegida se resalta. |

## 5. Inscripción y rondas

| Hallazgo | Prioridad | Estado |
|---|---|---|
| Con 30–40 inscritos costaba encontrar a alguien para cambiar mazo, pago o drop. | A | **Hecho**: buscador en la lista (aparece con más de 8 inscritos). |
| Al marcar un resultado no había respuesta táctil. | C | **Hecho**: vibración breve al tocar un resultado. |
| Tiempo de ronda fijo arriba, botones de 48 dp, borrado con confirmación | — | Ya estaba bien. |

## 6. Jugadores

| Hallazgo | Prioridad | Estado |
|---|---|---|
| Papelera visible en cada fila: fácil borrar a alguien por accidente al hacer scroll. | A | **Hecho**: menú ⋮ con Editar / Eliminar (con confirmación). |
| Nombres largos desbordaban. | C | **Hecho**: se cortan con "…". |

## 7. Segunda tanda (11/11)

| Mejora | Estado |
|---|---|
| **Logo nuevo** (casa con puerta de garaje, "GARAGE", "— TCG —"), redibujado en vectores con trazos limpios a partir de las imágenes del club. | **Hecho**: `assets/logo/logo.png` (blanco sobre transparente, la app lo tiñe según el modo), icono de la app (casa blanca sobre negro, también icono adaptable) y pantalla de inicio (normal y Android 12, claro y oscuro) regenerados en `android/app/src/main/res`. El logo sustituye al título de texto en Torneos, bloqueo de licencia e imágenes compartidas. |
| **Modo claro y modo oscuro**. | **Hecho**: Ajustes → Apariencia (Sistema / Claro / Oscuro; por defecto el del teléfono). Paleta clara propia (fondo `#F4F7F2`, verde `#2E7D1F`, texto `#13261A`), sombras suaves en vez de brillo neón. Las **imágenes que se comparten salen siempre en oscuro**. |
| Deshacer tras eliminar jugador o torneo. | **Hecho**: aviso con "Deshacer" (6 s). Jugador: sin confirmación previa. Torneo: confirmación + Deshacer (restaura también sus resultados de temporada). |
| Pantalla de bienvenida para jugadores y jueces. | **Hecho**: hoja de bienvenida la primera vez que entra cada cuenta (qué ver, vincular la ficha, VPN). |
| Ficha del jugador con destacados. | **Hecho**: tarjeta con mazo más jugado, mejor mazo (≥3 partidas), rival más difícil y "le gana más a" (≥2 partidas). |

## 8. Tercera tanda (11/11)

| Mejora | Estado |
|---|---|
| Primera columna fija en las tablas. | **Hecho**: en todas las tablas (ranking, clasificación, mazos, fichas), al desplazar en horizontal las columnas hasta el nombre (# y Jugador/Mazo) se quedan fijas, con una sombra suave; barra de desplazamiento visible. Si las columnas fijas ocuparían más del 60 % de la pantalla, no se fijan. |
| Letra grande del teléfono. | **Hecho**: la app respeta la letra del sistema hasta un 130 %; las columnas de las tablas se ensanchan en la misma proporción para que nada se corte. Las imágenes compartidas no cambian. |
| Pantalla encendida durante la ronda. | **Hecho**: mientras corre el tiempo de ronda, el teléfono del organizador no apaga la pantalla (plugin `wakelock_plus`). Se apaga normal al detener el tiempo, pasar de ronda o salir del torneo. |
| Accesibilidad (lector de pantalla). | **Hecho**: cada botón de resultado se lee como "Gana Ana 2-1", "Empate intencional"…, con estado seleccionado; cada mesa se anuncia ("mesa 3: Ana contra Luis. Pendiente"); cada fila de tabla se lee entera de una vez; el logo tiene nombre. |

Con esto quedan aplicadas todas las propuestas de la auditoría.

## 9. Cuarta tanda (11/11)

| Mejora | Estado |
|---|---|
| La sesión vencía a los 30 días aunque se usara la app a diario. | **Hecho**: se renueva sola al abrir la app con conexión. |
| Había que escribir el usuario cada vez. | **Hecho**: se recuerda el último y el cursor va a la contraseña; teclado y botones "siguiente/listo" adecuados. |
| "Atrás" en la pantalla principal cerraba la app de golpe. | **Hecho**: desde otra pestaña vuelve a Torneos; en Torneos pide pulsar dos veces. |
| Mensaje de "sin conexión" sin pista de la VPN. | **Hecho**: lo menciona. |

## 10. Segunda auditoría con capturas (14/11) — propuestas

| # | Hallazgo | Propuesta | Prioridad |
|---|---|---|---|
| 1 | Rondas: cada mesa ocupa media pantalla (7 botones) aunque ya tenga resultado; con 20 mesas hay mucho scroll. | Mesas con resultado se pliegan a una línea; las pendientes arriba; filtro "Solo pendientes". | A |
| 2 | "Generar ronda N" visible y encima de las mesas aunque falten resultados. | Mientras falten resultados, "Faltan 3" (lleva a la primera pendiente); el botón aparece al completar la ronda. | A |
| 3 | Inscritos: "Drop" en rojo, casilla Cover y martillo en cada fila. | Fila con Cover a la vista; Drop y penalización en el menú ⋮. | B |
| 4 | Rondas repite la configuración ("4 rondas Swiss · Top 4") que ya sale bajo el título. | Quitar la línea; editar desde el menú. | B |
| 5 | Títulos en mayúsculas se cortan ("GARAGE WEEKLY #14 N…"). | Nombre del torneo en tipografía normal, hasta 2 líneas. | B |
| 6 | Torneo terminado: pestañas solo con iconos. | Iconos con texto (Participantes · Mazos · Listas). | B |
| 7 | "Cerrar temporada" destacado arriba del ranking. | Al menú ⋮ (es irreversible y se usa 4 veces al año). | B |
| 8 | "Compartir" en 5 sitios y formas distintas. | Siempre el mismo icono en la barra superior. | C |
| 9 | Lista de jugadores repite el apodo con el nombre completo. | Subtítulo útil: puesto en el ranking y mazo habitual. | C |
| 10 | Ranking: filas resaltadas en dos verdes sin leyenda. | Leyenda corta o un solo resaltado. | C |
| 11 | Jugador sin inscripciones: "Aún no hay torneos", aunque tiene los terminados. | Mostrar los últimos terminados de la comunidad. | B |

Ideas nuevas: historial contra el rival en "Mi mesa ahora", tarjeta para compartir "Mi torneo" del jugador, y "te faltan X puntos para el Top 8" en la ficha.

**Estado (14/11): todo hecho.** Detalles:
- Rondas: las mesas siguen **en orden de mesa** (si las pendientes subieran, la lista saltaría al anotar cada resultado). Con resultado se pliegan a una línea ("1  Dante  2-1  Mara ✓"); al tocarla se abre para corregir y "Plegar" la cierra. Filtro **Todas / Pendientes**. Compartir es un icono junto al título de la ronda; Cambiar cruces, Importar cruces y Deshacer ronda pasan al menú ⋮. La línea "4 rondas Swiss · Top 4 · Fijado" ya no sale (la configuración solo aparece mientras se puede cambiar, en inscripción).
- Botón flotante: con resultados pendientes dice **"Faltan N"** y al tocarlo muestra solo las mesas pendientes; al completarse la ronda pasa a "Generar ronda N" / "Iniciar Top" / "Finalizar".
- Vista de jugador: todas las mesas en una línea y la suya resaltada en verde.
- Inscritos: a la vista solo la casilla Cover (y Check-in); Cambiar mazo, Penalización, Retirar (drop) y Quitar en el menú ⋮.
- Títulos de torneo, jugador, mazo y lista: en su forma normal y hasta en 2 líneas (`NameTitle`).
- Torneo terminado: pestañas Participantes · Mazos · Listas.
- "Cerrar temporada": en el menú ⋮ del ranking y solo para quien crea torneos (antes salía a cualquiera).
- Compartir: siempre el mismo icono (`ShareButton`).
- Lista de jugadores: "3º · 200 pts · Yubel" o "Sin puntos" en vez del nombre completo (la búsqueda sigue encontrando por nombre).
- Ranking: leyenda del verde ("los 8 primeros, más claro = mejor puesto") y, para quien tiene ficha, "Vas 6º con 120 pts: te faltan 40 para alcanzar a Leo" / "para el Top 8".
- Jugadores: en Torneos ven también los **últimos 10 terminados** de la comunidad.
- Nuevo: **historial contra el rival** en "Mi mesa ahora" ("Historial: 2-1 · la última vez ganaste" o "Primera vez que se enfrentan").
- Nuevo: **"Tu torneo"** en el resumen de un torneo terminado (puesto, mazo, récord, % y puntos) con **Compartir mi resultado** (imagen).
