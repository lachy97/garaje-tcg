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
