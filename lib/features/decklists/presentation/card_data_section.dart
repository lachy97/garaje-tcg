import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../data/card_images.dart';
import 'card_image.dart';

final _usageProvider = FutureProvider.autoDispose<(int, int)>(
    (ref) => ref.watch(cardImageStoreProvider).usage());

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Ajustes → Cartas: estado de la base de cartas de Edison, prueba de
/// descarga de imágenes y espacio usado.
class CardDataSection extends ConsumerStatefulWidget {
  const CardDataSection({super.key});

  @override
  ConsumerState<CardDataSection> createState() => _CardDataSectionState();
}

class _CardDataSectionState extends ConsumerState<CardDataSection> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(cardDbProvider);
    final usage = ref.watch(_usageProvider).value;
    return NeonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          db.when(
            loading: () => const Text('Cargando base de cartas…'),
            error: (e, _) =>
                Text('Error al leer la base de cartas: $e', style: const TextStyle(color: AppColors.loss)),
            data: (d) => d.isEmpty
                ? const Text(
                    'La base de cartas aún no está en esta versión de la app.',
                    style: TextStyle(color: AppColors.draw, fontWeight: FontWeight.w600),
                  )
                : Text('${d.length} cartas de Edison Format (base del ${d.version})',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Se usan para las listas de mazos del Top 4. Las imágenes se descargan '
            'solo la primera vez que se ven y quedan guardadas en el teléfono.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          if (usage != null && usage.$2 > 0) ...[
            const SizedBox(height: 6),
            Text('Imágenes guardadas: ${usage.$2} (${_mb(usage.$1)})',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            label: const Text('Probar descarga de imágenes'),
          ),
          if (usage != null && usage.$2 > 0)
            TextButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Borrar imágenes guardadas'),
            ),
        ],
      ),
    );
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final store = ref.read(cardImageStoreProvider);
    final results = await store.testHosts();
    if (!mounted) return;
    setState(() => _testing = false);
    final anyOk = results.any((r) => r.ok);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(anyOk ? 'Descarga OK' : 'No se pudo descargar'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(r.ok ? Icons.check_circle : Icons.error,
                          color: r.ok ? AppColors.neon : AppColors.loss, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Uri.parse(r.host).host,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              r.ok
                                  ? '${r.millis} ms · ${(r.bytes! / 1024).toStringAsFixed(0)} KB'
                                  : r.error!,
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (anyOk)
                const Center(
                  child: CardImage(
                    id: cardImageTestId,
                    name: 'Dark Magician',
                    size: CardImageSize.art,
                    width: 160,
                  ),
                )
              else
                const Text(
                  'Comprueba que tienes datos o wifi. Si el servidor de imágenes no '
                  'responde, avisa al administrador.',
                  style: TextStyle(fontSize: 13),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
    if (mounted) ref.invalidate(_usageProvider);
  }

  Future<void> _clear() async {
    final ok = await confirmDialog(
      context,
      title: '¿Borrar imágenes guardadas?',
      message: 'Se volverán a descargar cuando hagan falta.',
      confirm: 'Borrar',
    );
    if (!ok || !mounted) return;
    await ref.read(cardImageStoreProvider).clear();
    if (mounted) ref.invalidate(_usageProvider);
  }
}
