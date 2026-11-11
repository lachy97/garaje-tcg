import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../core/sync/sync_service.dart';

/// Ajustes → Sincronización: cambios pendientes de subir, última subida y
/// botón para subir ahora.
class SyncSection extends ConsumerStatefulWidget {
  const SyncSection({super.key});

  @override
  ConsumerState<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<SyncSection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final s = ref.read(syncControllerProvider);
      if (s.enabled) ref.read(syncControllerProvider.notifier).refreshPending();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncControllerProvider);
    final ctrl = ref.read(syncControllerProvider.notifier);
    final last = s.lastSync == null ? null : DateFormat('dd/MM HH:mm', 'es').format(s.lastSync!);
    return NeonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                !s.enabled
                    ? Icons.cloud_off
                    : s.lastError != null
                        ? Icons.cloud_queue
                        : Icons.cloud_done,
                color: !s.enabled
                    ? AppColors.textSecondary
                    : s.lastError != null
                        ? AppColors.draw
                        : AppColors.neon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  !s.enabled
                      ? 'Sin sincronizar'
                      : s.download
                          ? (s.lastSync == null ? 'Bajando datos…' : 'Datos al día')
                          : s.pending == 0
                              ? 'Todo subido al servidor'
                              : '${s.pending} cambio(s) por subir',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            !s.enabled
                ? s.reason ?? ''
                : s.download
                    ? [
                        'Ranking, tier list, tus torneos y tu ficha llegan del servidor '
                            'cada 30 s cuando hay internet (con VPN si hace falta). Sin '
                            'conexión ves lo último que bajó.',
                        if (last != null) 'Última actualización: $last (${s.lastSent} fila(s)).',
                      ].join('\n')
                    : [
                        'Los torneos se siguen jugando sin conexión; los cambios suben solos '
                            'cada 30 s cuando hay internet.',
                        if (last != null) 'Última subida: $last (${s.lastSent} fila(s)).',
                        if (s.rejected > 0)
                          '${s.rejected} fila(s) no aceptadas (son de otro organizador).',
                      ].join('\n'),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          if (s.enabled && s.lastError != null) ...[
            const SizedBox(height: 6),
            Text(s.lastError!, style: TextStyle(color: AppColors.draw, fontSize: 12)),
          ],
          if (s.enabled) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: s.running ? null : ctrl.sync,
              icon: s.running
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(s.download ? Icons.cloud_download : Icons.cloud_upload),
              label: Text(s.running
                  ? (s.download ? 'Actualizando…' : 'Subiendo…')
                  : (s.download ? 'Actualizar ahora' : 'Sincronizar ahora')),
            ),
            TextButton(
              onPressed: s.running ? null : (s.download ? ctrl.redownloadAll : ctrl.resendAll),
              child: Text(s.download ? 'Volver a bajar todo' : 'Volver a subir todo'),
            ),
          ],
        ],
      ),
    );
  }
}
