import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Las imágenes de mazo son cuadradas y se muestran en círculo.
const kDeckImageAspect = 1.0;

/// ImageProvider de un mazo, o null si no tiene imagen (o el archivo ya no existe).
ImageProvider? deckImageProvider(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('assets/')) return AssetImage(path);
  final f = File(path);
  return f.existsSync() ? FileImage(f) : null;
}

/// Imagen circular de un mazo. Sin imagen muestra un círculo con el nombre
/// (o las iniciales si es muy pequeña). [width] es el diámetro.
class DeckImage extends StatelessWidget {
  const DeckImage({
    super.key,
    required this.path,
    required this.name,
    this.width = 60,
    this.radius = 0, // ya no se usa: la imagen siempre es circular
    this.borderColor,
  });

  final String? path;
  final String name;
  final double width;
  final double radius;

  /// Aro alrededor (p. ej. el color del tier). Por defecto, el borde del tema.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final provider = deckImageProvider(path);
    final ring = width >= 40 ? 2.0 : 1.2;
    return Container(
      width: width,
      height: width,
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: borderColor ?? AppColors.outline,
      ),
      child: ClipOval(
        child: provider == null
            ? _placeholder()
            : Image(
                image: provider,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => _placeholder(),
              ),
      ),
    );
  }

  Widget _placeholder() {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.forest, AppColors.surfaceHigh],
        ),
      ),
      padding: EdgeInsets.all(width * 0.14),
      // Mazos sin foto: el nombre (o las iniciales si la imagen es muy pequeña).
      child: width >= 56
          ? Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: width * 0.14,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: AppColors.neon),
            )
          : FittedBox(
              child: Text(
                initials.isEmpty ? '?' : initials,
                style: const TextStyle(
                    fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.neon),
              ),
            ),
    );
  }
}
