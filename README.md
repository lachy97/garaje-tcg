# Garage TCG

App Flutter **100 % offline** para organizar torneos de Yu-Gi-Oh! (Swiss + Top Cut), ranking trimestral y meta de mazos.

## Primera puesta en marcha

En esta carpeta (requiere Flutter estable ≥ 3.32):

```bash
# 1. Genera las carpetas android/ ios/ etc. sin tocar los archivos existentes
flutter create --org cu.garajetcg --project-name garaje_tcg --platforms android,ios .

# 2. Borra el test de ejemplo que crea flutter (referencia una clase que no existe)
#    Windows:  del test\widget_test.dart
rm test/widget_test.dart

# 3. Dependencias (si alguna versión no resuelve: flutter pub upgrade --major-versions)
flutter pub get

# 4. Genera el código de Drift (*.g.dart). Repetir cada vez que cambien tablas o DAOs
dart run build_runner build --delete-conflicting-outputs

# 5. Icono de la app y pantalla de carga (negro + logo). Solo la primera vez
#    o cuando cambie el logo
dart run flutter_launcher_icons
dart run flutter_native_splash:create

# 6. Tests de reglas y ejecución
flutter test
flutter run
```

## Estructura

```
lib/
  app/                 App, tema, router (go_router) y widgets comunes
  core/db/             Drift: tablas, AppDatabase, DAOs, providers
  core/utils/          ids (UUID v7), temporadas
  features/<feature>/  data · domain (Dart puro) · presentation
```

## Pantallas (Fase 1)

- **Torneos**: lista, crear (nombre, fecha, rondas Swiss y Top Cut; se fijan al empezar) y detalle con tres pestañas:
  - *Jugadores*: inscripción múltiple, mazo por jugador (autocompletado), drop durante el Swiss.
  - *Rondas*: configuración de rondas Swiss y Top Cut (con sugerencia según asistencia),
    tarjeta por mesa con `J1 | vs / Empate | J2` y tres columnas de opciones 0/1/2
    (juegos de J1, empates, juegos de J2); se guarda sola al formar un marcador válido
    (2-0-0, 2-0-1, 1-1-1, 1-0-2, 0-0-2). Botón flotante ">" para avanzar:
    generar ronda → iniciar Top → siguiente ronda → finalizar (siempre con confirmación).
    Casilla **Doble derrota** (Swiss) para cuando se acaba el tiempo: 0-0-0, pierden los dos.
    **Reloj de ronda** (45 min por defecto, editable antes de empezar): se inicia a mano y avisa al llegar a 0.
  - *Clasificación*: tabla Swiss en vivo (Pts, OMW%, OOMW%, GW%) con línea de corte y resultado final con puntos.
- **Ranking**: tabla del trimestre (selector de temporada; puntos, mazo, PJ/V/D/E, WR%, torneos, mejor puesto) y exportación a imágenes PNG nítidas (12 jugadores por imagen) para compartir.
- **Mazos**: tier list S/A/B/C y tabla de la temporada con la puntuación ponderada (Score), exportable como imágenes. *Gestionar mazos* (crear, renombrar, fusionar duplicados) en el botón de la barra.
- **Jugadores**: contador, lista con búsqueda, alta y borrado. Al tocar un jugador se abre su **perfil**: datos personales (nombre, Konami ID, teléfono, notas), resumen (torneos, partidas, V-D-E, winrate, títulos, mejor puesto), mazos usados (veces, PJ, V/D/E, WR%, última vez) e historial de todas sus partidas agrupado por torneo (fase, rival y su mazo, marcador y resultado).

## Diseño visual

Siempre oscuro: fondo **negro** y verdes del logo para textos, bordes y brillos.
Paleta y tema en `lib/app/theme.dart` (`AppColors`, `AppTheme.dark`); componentes de marca
(`GlowLogo`, `NeonCard`, `BrandTitle`) en `lib/app/widgets/brand.dart`.
Logo en `assets/logo/` (`logo.png` transparente, `logo_dark.png` fondo negro, iconos).

Decisiones de diseño: ver `docs/DECISIONES.md`.
