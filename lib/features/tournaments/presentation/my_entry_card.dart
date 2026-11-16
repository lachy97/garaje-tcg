import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/auth/account.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/daos/tournaments_dao.dart';
import '../../../core/registrations/registrations.dart';
import '../../../core/sync/sync_service.dart';
import '../../decks/presentation/deck_picker.dart';
import 'providers.dart';
import 'start_time.dart';

/// Jugador inscrito en un torneo que aún no empezó: con qué mazo juega y
/// botón para cambiarlo. El cambio va al servidor y lo aplica el teléfono
/// del organizador al sincronizar (como una solicitud aceptada).
class MyEntryCard extends ConsumerStatefulWidget {
  const MyEntryCard({super.key, required this.tournament});

  final Tournament tournament;

  @override
  ConsumerState<MyEntryCard> createState() => _MyEntryCardState();
}

class _MyEntryCardState extends ConsumerState<MyEntryCard> {
  bool _busy = false;

  Tournament get t => widget.tournament;

  bool get _started => hasStartTime(t.date) && !DateTime.now().isBefore(t.date);

  Future<void> _change(String? current) async {
    final api = ref.read(registrationsApiProvider);
    if (api == null || _busy) return;
    final deck = await showDeckPicker(context, current: current);
    if (deck == null || deck.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await api.request(t.id, deck);
      if (mounted) showMessage(context, 'Mazo cambiado a $deck: se aplica cuando sincronice el organizador');
      ref.invalidate(myRegistrationsProvider);
      await ref.read(syncControllerProvider.notifier).sync();
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
    final pid = ref.watch(permissionsProvider).playerId;
    if (pid == null || ref.watch(registrationsApiProvider) == null) return const SizedBox.shrink();
    final list = ref.watch(registeredProvider(t.id)).value ?? const <RegisteredPlayer>[];
    final me = list.where((r) => r.player.id == pid && r.entry.deletedAt == null).firstOrNull;
    if (me == null) return const SizedBox.shrink();
    // Cambio enviado que el organizador aún no aplicó.
    final req = ref.watch(myRegistrationsProvider).value?.requests[t.id];
    final pending = req != null &&
        req.status == RegistrationStatus.accepted &&
        req.deckName != null &&
        req.deckName != me.deck?.name;
    final deck = pending ? req.deckName : me.deck?.name;
    return NeonCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.style_outlined, color: AppColors.neon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Inscrito con ${deck ?? 'sin mazo'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  _started
                      ? 'El torneo ya empezó: el mazo solo lo cambia el organizador.'
                      : pending
                          ? 'Cambio enviado: se aplica cuando sincronice el organizador.'
                          : 'Puedes cambiarlo hasta la hora de inicio.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (!_started)
            _busy
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton(onPressed: () => _change(deck), child: const Text('Cambiar mazo')),
        ],
      ),
    );
  }
}
