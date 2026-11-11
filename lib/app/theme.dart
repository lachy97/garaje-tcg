import 'package:flutter/material.dart';

/// Colores de un modo (oscuro o claro).
class AppPalette {
  const AppPalette({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.neon,
    required this.neonBright,
    required this.leaf,
    required this.moss,
    required this.forest,
    required this.outline,
    required this.outlineVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.draw,
    required this.loss,
    required this.logo,
  });

  final bool isDark;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceHighest;
  final Color neon;
  final Color neonBright;
  final Color leaf;
  final Color moss;
  final Color forest;
  final Color outline;
  final Color outlineVariant;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color draw;
  final Color loss;

  /// Color del logo (blanco en oscuro, casi negro en claro).
  final Color logo;

  /// Modo oscuro: negro de fondo + verdes neón (el de siempre).
  static const dark = AppPalette(
    isDark: true,
    background: Color(0xFF000000),
    surface: Color(0xFF070D09),
    surfaceHigh: Color(0xFF0E1A12),
    surfaceHighest: Color(0xFF15261A),
    neon: Color(0xFF8CF04C),
    neonBright: Color(0xFFD1FFAD),
    leaf: Color(0xFF5FB86A),
    moss: Color(0xFF3E7A4E),
    forest: Color(0xFF16402A),
    outline: Color(0xFF2A4A33),
    outlineVariant: Color(0xFF1B2E21),
    textPrimary: Color(0xFFC9F7B4),
    textSecondary: Color(0xFF7FA886),
    textDisabled: Color(0xFF41594A),
    draw: Color(0xFFE6C84F),
    loss: Color(0xFFFF5C5C),
    logo: Color(0xFFFFFFFF),
  );

  /// Modo claro: fondo blanco verdoso, verdes más oscuros para que el texto
  /// y los botones tengan buen contraste.
  static const light = AppPalette(
    isDark: false,
    background: Color(0xFFF4F7F2),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEDF3EA),
    surfaceHighest: Color(0xFFE1EADD),
    neon: Color(0xFF2E7D1F),
    neonBright: Color(0xFF1B5410),
    leaf: Color(0xFF3B8A47),
    moss: Color(0xFF8DAE93),
    forest: Color(0xFFD7EDCC),
    outline: Color(0xFFC3D5BF),
    outlineVariant: Color(0xFFDDE8D9),
    textPrimary: Color(0xFF13261A),
    textSecondary: Color(0xFF4B6451),
    textDisabled: Color(0xFF9BAE9F),
    draw: Color(0xFFA87400),
    loss: Color(0xFFC62828),
    logo: Color(0xFF111111),
  );
}

/// Colores de la app. Dependen del modo activo (claro u oscuro): por eso son
/// getters y no constantes. Las imágenes que se comparten se dibujan siempre
/// en oscuro (ver [AppColors.runDark]).
class AppColors {
  const AppColors._();

  /// Paleta elegida (modo claro u oscuro).
  static AppPalette _user = AppPalette.dark;

  /// Mientras se dibuja una imagen para compartir: siempre oscura.
  static int _forceDark = 0;

  static AppPalette get _p => _forceDark > 0 ? AppPalette.dark : _user;

  /// Paleta elegida por el usuario (la de la interfaz).
  static AppPalette get palette => _user;
  static set palette(AppPalette p) => _user = p;
  static bool get isDark => _p.isDark;

  // Fondos
  static Color get background => _p.background;
  static Color get surface => _p.surface; // tarjetas
  static Color get surfaceHigh => _p.surfaceHigh; // tarjetas elevadas / inputs
  static Color get surfaceHighest => _p.surfaceHighest;

  // Verdes del logo
  static Color get neon => _p.neon; // acento principal
  static Color get neonBright => _p.neonBright;
  static Color get leaf => _p.leaf;
  static Color get moss => _p.moss;
  static Color get forest => _p.forest;
  static Color get outline => _p.outline;
  static Color get outlineVariant => _p.outlineVariant;

  // Texto
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textDisabled => _p.textDisabled;

  // Semánticos (resultados)
  static Color get win => _p.neon;
  static Color get draw => _p.draw;
  static Color get loss => _p.loss;

  /// Color del logo.
  static Color get logo => _p.logo;

  /// Sombra luminosa reutilizable ("glow"). En claro, una sombra suave.
  static List<BoxShadow> glow({Color? color, double strength = 1}) => [
        BoxShadow(
          color: (color ?? neon).withValues(alpha: (_p.isDark ? 0.35 : 0.18) * strength),
          blurRadius: (_p.isDark ? 18 : 10) * strength,
          spreadRadius: _p.isDark ? 1 : 0,
        ),
      ];

  /// Sombra para textos destacados (títulos con brillo). En claro, sin brillo.
  static List<Shadow> textGlow({Color? color, double blur = 12}) => _p.isDark
      ? [Shadow(color: (color ?? neon).withValues(alpha: 0.7), blurRadius: blur)]
      : const [];

  /// Ejecuta [action] con la paleta oscura (para dibujar imágenes que se
  /// comparten, que siempre son oscuras) y después restaura la activa.
  static Future<T> runDark<T>(Future<T> Function() action) async {
    _forceDark++;
    try {
      return await action();
    } finally {
      _forceDark--;
      if (_forceDark == 0 && !_user.isDark) rebuildAllWidgets();
    }
  }
}

/// Vuelve a construir toda la interfaz (tras cambiar de paleta) sin perder
/// el estado de las pantallas.
void rebuildAllWidgets() {
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(mark);
}

class AppTheme {
  const AppTheme._();

  /// Fuente única de la app (empaquetada en assets/fonts, no depende del teléfono).
  static const fontFamily = 'Inter';

  static ThemeData get dark => build(AppPalette.dark);
  static ThemeData get light => build(AppPalette.light);

  static ThemeData build(AppPalette p) {
    final onAccent = p.isDark ? Colors.black : Colors.white;
    List<Shadow> glow({double blur = 12}) =>
        p.isDark ? [Shadow(color: p.neon.withValues(alpha: 0.7), blurRadius: blur)] : const [];
    final scheme = ColorScheme(
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      primary: p.neon,
      onPrimary: onAccent,
      primaryContainer: p.forest,
      onPrimaryContainer: p.neonBright,
      secondary: p.leaf,
      onSecondary: onAccent,
      secondaryContainer: p.isDark ? const Color(0xFF1C3524) : const Color(0xFFDDEDD5),
      onSecondaryContainer: p.textPrimary,
      tertiary: p.draw,
      onTertiary: onAccent,
      error: p.loss,
      onError: onAccent,
      surface: p.background,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceHigh,
      surfaceContainerHighest: p.surfaceHighest,
      outline: p.outline,
      outlineVariant: p.outlineVariant,
      shadow: p.forest,
      scrim: Colors.black,
      inverseSurface: p.neonBright,
      onInverseSurface: onAccent,
      inversePrimary: p.forest,
      surfaceTint: Colors.transparent, // sin tinte gris al elevar
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: fontFamily);
    final text = base.textTheme.apply(
      bodyColor: p.textPrimary,
      displayColor: p.neon,
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          shadows: glow(),
        ),
        titleLarge: text.titleLarge?.copyWith(
          color: p.neon,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.neon,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        // Un poco menos de espaciado y brillo: los nombres largos de torneos
        // y mazos caben mejor y se leen más fácil.
        titleTextStyle: text.titleLarge?.copyWith(
          color: p.neon,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          shadows: glow(blur: 6),
        ),
        shape: Border(bottom: BorderSide(color: p.outline, width: 0.6)),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.outline, width: 0.8),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.leaf,
        textColor: p.textPrimary,
        subtitleTextStyle: TextStyle(color: p.textSecondary),
      ),
      dividerTheme: DividerThemeData(color: p.outline, thickness: 0.6),
      iconTheme: IconThemeData(color: p.neon),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.neon,
          foregroundColor: onAccent,
          disabledBackgroundColor: p.surfaceHighest,
          disabledForegroundColor: p.textDisabled,
          minimumSize: const Size(64, 48),
          shape: rounded,
          shadowColor: p.neon,
          elevation: 4,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.surfaceHigh,
          foregroundColor: p.neon,
          minimumSize: const Size(64, 48),
          shape: rounded,
          shadowColor: p.neon,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.neon,
          side: BorderSide(color: p.neon, width: 1.2),
          minimumSize: const Size(64, 48),
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.neon),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.neon,
        foregroundColor: onAccent,
        elevation: 6,
        shape: StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceHigh,
        labelStyle: TextStyle(color: p.textSecondary),
        floatingLabelStyle: TextStyle(color: p.neon),
        hintStyle: TextStyle(color: p.textDisabled),
        prefixIconColor: p.leaf,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.neon, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.loss),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.forest,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected)
                  ? p.neon
                  : p.textSecondary,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: s.contains(WidgetState.selected)
                  ? p.neon
                  : p.textSecondary,
            )),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.surfaceHigh,
        selectedColor: p.forest,
        side: BorderSide(color: p.outline),
        labelStyle: TextStyle(color: p.textPrimary),
        checkmarkColor: p.neon,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.moss),
        ),
        titleTextStyle: text.titleLarge?.copyWith(color: p.neon),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: p.moss,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceHighest,
        contentTextStyle: TextStyle(color: p.textPrimary),
        actionTextColor: p.neon,
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.neon,
        linearTrackColor: p.forest,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? onAccent : p.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.neon : p.surfaceHighest),
      ),
    );
  }
}
