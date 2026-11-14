import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/auth/account.dart';
import '../../../../core/sync/control.dart';
import '../../../../core/sync/sync_service.dart';

/// Torneo que lleva otro teléfono: aquí solo se consulta. Si ese teléfono se
/// quedó sin batería o sin datos, este puede tomar el control y seguir.
class ControlBanner extends ConsumerStatefulWidget {
  const ControlBanner({super.key, required this.control});

  final TournamentControl control;

  @override
  ConsumerState<ControlBanner> createState() => _ControlBannerState();
}

class _ControlBannerState extends ConsumerState<ControlBanner> {
  bool _busy = false;

  TournamentControl get c => widget.control;

  String get _ago {
    final last = c.lastSeen;
    if (last == null) return '';
    final d = DateTime.now().difference(last);
    if (d.inMinutes < 1) return ', activo ahora';
    if (d.inMinutes < 60) return ', activo hace ${d.inMinutes} min';
    if (d.inHours < 24) return ', activo hace ${d.inHours} h';
    return ', activo hace ${d.inDays} d';
  }

  Future<void> _take() async {
    final who = c.deviceName ?? 'el otro teléfono';
    final ok = await confirmDialog(
      context,
      title: 'Tomar el control',
      message: 'Este teléfono pasará a llevar el torneo y $who quedará solo para consultar.\n\n'
          'Lo que $who no llegó a subir (resultados, cambios de la última ronda) se pierde: '
          'revisa la ronda actual después de tomarlo.',
      confirm: 'Tomar el control',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(syncControllerProvider.notifier).takeControl(c.tournamentId);
      if (mounted) showMessage(context, 'Ahora llevas el torneo desde este teléfono');
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = c.canTake
        ? 'Este torneo lo lleva ${c.deviceName ?? 'otro teléfono'}'
            '${c.nickname == null ? '' : ' (${c.nickname})'}$_ago. Aquí solo se consulta.'
        : 'Este torneo es de otro organizador: aquí solo se consulta.';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.draw.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.draw.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.phonelink_lock, color: AppColors.draw, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.draw)),
          ),
          if (c.canTake)
            _busy
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton(onPressed: _take, child: const Text('Tomar el control')),
        ],
      ),
    );
  }
}
