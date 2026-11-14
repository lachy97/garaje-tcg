import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/sync/sync_service.dart';

/// Para el organizador durante la ronda: cuándo sincronizó por última vez.
/// Si pasa de 2 minutos (o hay error), los reportes, check-ins y avisos de los
/// jugadores no le están llegando: se ve en rojo con "Reintentar".
class SyncFreshness extends ConsumerStatefulWidget {
  const SyncFreshness({super.key});

  @override
  ConsumerState<SyncFreshness> createState() => _SyncFreshnessState();
}

class _SyncFreshnessState extends ConsumerState<SyncFreshness> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncControllerProvider);
    if (!s.enabled || s.download) return const SizedBox.shrink();
    final last = s.lastSync;
    final ago = last == null ? null : DateTime.now().difference(last);
    final stale = ago == null || ago > const Duration(minutes: 2);
    final slow = !stale && ago > const Duration(minutes: 1);
    final bad = stale || s.lastError != null;
    final color = bad
        ? AppColors.loss
        : slow
            ? AppColors.draw
            : AppColors.leaf;
    final when = ago == null
        ? 'todavía no'
        : ago.inSeconds < 60
            ? 'hace ${ago.inSeconds} s'
            : 'hace ${ago.inMinutes} min';
    final text = s.lastError != null
        ? 'Sin conexión con el servidor ($when): los reportes de los jugadores no te llegan.'
        : bad
            ? 'Última sincronización $when: los reportes de los jugadores pueden no llegarte.'
            : 'Sincronizado $when${s.pending > 0 ? ' · ${s.pending} cambio(s) por subir' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Icon(bad ? Icons.cloud_off : Icons.cloud_done_outlined, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ),
          if (bad)
            s.running
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: () => ref.read(syncControllerProvider.notifier).sync(),
                    child: const Text('Reintentar'),
                  ),
        ],
      ),
    );
  }
}
