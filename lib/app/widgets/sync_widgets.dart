import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sync/sync_service.dart';
import '../theme.dart';

/// Arrastrar hacia abajo para sincronizar con el servidor (subir o bajar,
/// según el teléfono). Si este teléfono no sincroniza, no hace nada.
class SyncRefresh extends ConsumerWidget {
  const SyncRefresh({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    if (!s.enabled) return child;
    return RefreshIndicator(
      color: AppColors.neon,
      backgroundColor: AppColors.surfaceHigh,
      onRefresh: () => ref.read(syncControllerProvider.notifier).sync(),
      child: child,
    );
  }
}

/// Icono de estado de la sincronización (nube). Al tocarlo abre Ajustes.
/// Solo aparece si el teléfono sincroniza con el servidor.
class SyncStatusIcon extends ConsumerWidget {
  const SyncStatusIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    if (!s.enabled) return const SizedBox.shrink();
    final (IconData icon, Color color, String tip) = s.running
        ? (Icons.cloud_sync_outlined, AppColors.neon, 'Sincronizando…')
        : s.lastError != null
            ? (Icons.cloud_off_outlined, AppColors.draw, 'Sin conexión con el servidor: ${s.lastError}')
            : !s.download && s.pending > 0
                ? (Icons.cloud_upload_outlined, AppColors.draw, '${s.pending} cambio(s) por subir')
                : (Icons.cloud_done_outlined, AppColors.textSecondary, 'Todo sincronizado');
    return IconButton(
      tooltip: tip,
      onPressed: () => context.push('/ajustes'),
      icon: Icon(icon, color: color),
    );
  }
}
