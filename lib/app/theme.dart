import 'package:flutter/material.dart';

/// Paleta sacada del logo de Garaje TCG: negro de fondo + verdes neón.
class AppColors {
  const AppColors._();

  // Fondos
  static const background = Color(0xFF000000); // negro puro (fondo del logo)
  static const surface = Color(0xFF070D09); // tarjetas, casi negro con tinte verde
  static const surfaceHigh = Color(0xFF0E1A12); // tarjetas elevadas / inputs
  static const surfaceHighest = Color(0xFF15261A);

  // Verdes del logo
  static const neon = Color(0xFF8CF04C); // puerta iluminada (acento principal)
  static const neonBright = Color(0xFFD1FFAD); // brillo máximo del logo
  static const leaf = Color(0xFF5FB86A); // verde medio (marcos interiores)
  static const moss = Color(0xFF3E7A4E); // verde apagado (marcos exteriores)
  static const forest = Color(0xFF16402A); // verde muy oscuro (sombras)
  static const outline = Color(0xFF2A4A33);
  static const outlineVariant = Color(0xFF1B2E21);

  // Texto (todo en verde, con distinta intensidad para mantener la legibilidad)
  static const textPrimary = Color(0xFFC9F7B4); // cuerpo de texto
  static const textSecondary = Color(0xFF7FA886); // textos secundarios
  static const textDisabled = Color(0xFF41594A);

  // Semánticos (resultados). La derrota necesita contraste: rojo suave.
  static const win = neon;
  static const draw = Color(0xFFE6C84F);
  static const loss = Color(0xFFFF5C5C);

  /// Sombra luminosa reutilizable ("glow" del logo).
  static List<BoxShadow> glow({Color color = neon, double strength = 1}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.35 * strength),
          blurRadius: 18 * strength,
          spreadRadius: 1,
        ),
      ];

  /// Sombra para textos destacados (títulos con brillo).
  static List<Shadow> textGlow({Color color = neon, double blur = 12}) => [
        Shadow(color: color.withValues(alpha: 0.7), blurRadius: blur),
      ];
}

class AppTheme {
  const AppTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.neon,
      onPrimary: Colors.black,
      primaryContainer: AppColors.forest,
      onPrimaryContainer: AppColors.neonBright,
      secondary: AppColors.leaf,
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFF1C3524),
      onSecondaryContainer: AppColors.textPrimary,
      tertiary: AppColors.draw,
      onTertiary: Colors.black,
      error: AppColors.loss,
      onError: Colors.black,
      surface: AppColors.background,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceHighest,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      shadow: AppColors.forest,
      scrim: Colors.black,
      inverseSurface: AppColors.neonBright,
      onInverseSurface: Colors.black,
      inversePrimary: AppColors.forest,
      surfaceTint: Colors.transparent, // sin tinte gris al elevar
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.neon,
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          shadows: AppColors.textGlow(),
        ),
        titleLarge: text.titleLarge?.copyWith(
          color: AppColors.neon,
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
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.neon,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: text.titleLarge?.copyWith(
          color: AppColors.neon,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          shadows: AppColors.textGlow(blur: 10),
        ),
        shape: const Border(bottom: BorderSide(color: AppColors.outline, width: 0.6)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.outline, width: 0.8),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.leaf,
        textColor: AppColors.textPrimary,
        subtitleTextStyle: TextStyle(color: AppColors.textSecondary),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.outline, thickness: 0.6),
      iconTheme: const IconThemeData(color: AppColors.neon),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.neon,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.surfaceHighest,
          disabledForegroundColor: AppColors.textDisabled,
          minimumSize: const Size(64, 48),
          shape: rounded,
          shadowColor: AppColors.neon,
          elevation: 4,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceHigh,
          foregroundColor: AppColors.neon,
          minimumSize: const Size(64, 48),
          shape: rounded,
          shadowColor: AppColors.neon,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.neon,
          side: const BorderSide(color: AppColors.neon, width: 1.2),
          minimumSize: const Size(64, 48),
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.neon),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.neon,
        foregroundColor: Colors.black,
        elevation: 6,
        shape: StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        floatingLabelStyle: const TextStyle(color: AppColors.neon),
        hintStyle: const TextStyle(color: AppColors.textDisabled),
        prefixIconColor: AppColors.leaf,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.neon, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.loss),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.forest,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected)
                  ? AppColors.neon
                  : AppColors.textSecondary,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: s.contains(WidgetState.selected)
                  ? AppColors.neon
                  : AppColors.textSecondary,
            )),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: AppColors.forest,
        side: const BorderSide(color: AppColors.outline),
        labelStyle: const TextStyle(color: AppColors.textPrimary),
        checkmarkColor: AppColors.neon,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.moss),
        ),
        titleTextStyle: text.titleLarge?.copyWith(color: AppColors.neon),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.moss,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceHighest,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
        actionTextColor: AppColors.neon,
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.neon,
        linearTrackColor: AppColors.forest,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.black : AppColors.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.neon : AppColors.surfaceHighest),
      ),
    );
  }
}
