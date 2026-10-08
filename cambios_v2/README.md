# Garaje TCG

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
  - *Clasificación*: tabla Swiss en vivo (Pts, OMW%, OOMW%, GW%) con línea de corte y resultado final con puntos.
- **Ranking**: tabla del trimestre (puntos, mazo, PJ/V/D/E, WR%, torneos, mejor puesto) y exportación a imagen PNG para compartir.
- **Mazos**: lista, crear, renombrar y fusionar duplicados.
- **Jugadores**: contador, lista con búsqueda, alta, edición y borrado.

## Diseño visual

Siempre oscuro: fondo **negro** y verdes del logo para textos, bordes y brillos.
Paleta y tema en `lib/app/theme.dart` (`AppColors`, `AppTheme.dark`); componentes de marca
(`GlowLogo`, `NeonCard`, `BrandTitle`) en `lib/app/widgets/brand.dart`.
Logo en `assets/logo/` (`logo.png` transparente, `logo_dark.png` fondo negro, iconos).

Decisiones de diseño: ver `docs/DECISIONES.md`.
