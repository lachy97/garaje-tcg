import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Proporción de las imágenes de mazo (cajas de Edison Format: 250×355).
const kDeckImageAspect = 250 / 355;

/// ImageProvider de un mazo, o null si no tiene imagen (o el archivo ya no existe).
ImageProvider? deckImageProvider(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('assets/')) return AssetImage(path);
  final f = File(path);
  return f.existsSync() ? FileImage(f) : null;
}

/// Imagen de un mazo. Sin imagen muestra un recuadro con las iniciales.
class DeckImage extends StatelessWidget {
  const DeckImage({
    super.key,
    required this.path,
    required this.name,
    this.width = 60,
    this.radius = 6,
  });

  final String? path;
  final String name;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final provider = deckImageProvider(path);
    final height = width / kDeckImageAspect;
    final Widget child = provider == null
        ? _placeholder(height)
        : Image(
            image: provider,
            width: width,
            height: height,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => _placeholder(height),
          );
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }

  Widget _placeholder(double height) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.forest, AppColors.surfaceHigh],
        ),
        border: Border.all(color: AppColors.outline),
      ),
      child: Padding(
        padding: EdgeInsets.all(width * 0.07),
        // Mazos sin foto: el nombre (o las iniciales si la imagen es muy pequeña).
        child: width >= 48
            ? Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: width * 0.15,
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
      ),
    );
  }
}
