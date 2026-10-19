import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../data/card_images.dart';

/// Imagen de una carta. Si no está en el teléfono la descarga (una vez);
/// mientras tanto, o sin conexión, muestra un rectángulo con el nombre.
class CardImage extends ConsumerStatefulWidget {
  const CardImage({
    super.key,
    required this.id,
    required this.name,
    this.size = CardImageSize.small,
    this.width = 60,
    this.fit = BoxFit.cover,
  });

  final int id;
  final String name;
  final CardImageSize size;
  final double width;
  final BoxFit fit;

  /// Proporción de una carta (ancho ÷ alto) y de la ilustración recortada.
  static const cardAspect = 168 / 246;
  static const artAspect = 1.0;

  @override
  ConsumerState<CardImage> createState() => _CardImageState();
}

class _CardImageState extends ConsumerState<CardImage> {
  late Future<File?> _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CardImage old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.size != widget.size) _load();
  }

  void _load() => _file = ref.read(cardImageStoreProvider).get(widget.id, widget.size);

  @override
  Widget build(BuildContext context) {
    final aspect =
        widget.size == CardImageSize.small ? CardImage.cardAspect : CardImage.artAspect;
    final height = widget.width / aspect;
    return SizedBox(
      width: widget.width,
      height: height,
      child: FutureBuilder<File?>(
        future: _file,
        builder: (context, snap) {
          final f = snap.data;
          if (f != null) {
            return Image.file(
              f,
              fit: widget.fit,
              cacheWidth: (widget.width * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, _, _) => _placeholder(loading: false),
            );
          }
          return _placeholder(loading: snap.connectionState != ConnectionState.done);
        },
      ),
    );
  }

  Widget _placeholder({required bool loading}) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          border: Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(3),
        alignment: Alignment.center,
        child: loading && widget.width >= 40
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(
                widget.name,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: (widget.width / 7).clamp(6, 12).toDouble(),
                    color: AppColors.textSecondary),
              ),
      );
}
