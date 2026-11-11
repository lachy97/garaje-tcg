import 'package:flutter/material.dart';

import '../theme.dart';

/// Rutas de los recursos de marca.
class BrandAssets {
  const BrandAssets._();
  /// Logo con el nombre (blanco sobre transparente; en la app se tiñe con
  /// el color del modo: blanco en oscuro, casi negro en claro).
  static const logo = 'assets/logo/logo.png';
}

/// Logo de Garage TCG con el color del modo activo (y un halo verde suave
/// en modo oscuro).
class GlowLogo extends StatelessWidget {
  const GlowLogo({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppColors.isDark
            ? [
                BoxShadow(
                  color: AppColors.neon.withValues(alpha: 0.14),
                  blurRadius: size * 0.45,
                  spreadRadius: size * 0.02,
                ),
              ]
            : null,
      ),
      child: Image.asset(
        BrandAssets.logo,
        width: size,
        height: size,
        color: AppColors.logo,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        semanticLabel: 'Garage TCG',
      ),
    );
  }
}

/// Tarjeta con borde verde y brillo opcional (para destacar ganadores, mesa 1, etc.).
class NeonCard extends StatelessWidget {
  const NeonCard({
    super.key,
    required this.child,
    this.glow = false,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final bool glow;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: radius,
        border: Border.all(
          color: glow ? AppColors.neon : AppColors.outline,
          width: glow ? 1.2 : 0.8,
        ),
        boxShadow: glow ? AppColors.glow(strength: 0.8) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Título "GARAGE TCG" con brillo.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.fontSize = 28});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'GARAGE TCG',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: fontSize * 0.18,
        color: AppColors.neon,
        shadows: AppColors.textGlow(blur: fontSize * 0.6),
      ),
    );
  }
}
