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

## 7. Propuestas para la siguiente iteración (no aplicadas)

1. **Deshacer** tras eliminar un jugador o torneo (aviso con "Deshacer" en vez de solo confirmar) · B.
2. **Pantalla de bienvenida** para jugadores nuevos (qué ver, cómo vincular su ficha, por qué hace falta la VPN) · B.
3. **Ficha del jugador**: mismo diseño de cuadrícula y "destacados" que la nueva ficha del mazo (mejor mazo, rival más difícil) · B.
4. **Tablas**: fijar la primera columna al desplazar horizontalmente (como la matriz) en ranking y tablas largas · B.
5. **Tamaño de letra del sistema**: probar con letra grande del teléfono y ajustar anchos fijos de las tablas · C.
6. **Modo torneo**: mantener la pantalla encendida mientras corre el tiempo de ronda · C.
7. **Accesibilidad**: etiquetas de lectura (Semantics) en botones de resultado y tablas · C.
